package main

import (
	"encoding/json"
	"net"
	"testing"
	"time"

	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener"
)

func TestCoreDefaultsKeepPreviousTunStack(t *testing.T) {
	if got := defaultSetupParams().Config.Tun.Stack; got != constant.TunGvisor {
		t.Fatalf("dependency upgrade silently changed absent TUN stack: got %s, want gVisor", got)
	}
}

func TestCoreExplicitTunStacksRemainAccepted(t *testing.T) {
	for _, stack := range []string{"gvisor", "mixed", "system", "mips"} {
		t.Run(stack, func(t *testing.T) {
			params := defaultSetupParams()
			if err := json.Unmarshal([]byte(`{"config":{"tun":{"stack":"`+stack+`"}}}`), params); err != nil {
				t.Fatal(err)
			}
			if params.Config.Tun.Stack != constant.StackTypeMapping[stack] {
				t.Fatal("explicit stack overwritten")
			}
		})
	}
}

func TestTunStatusNeedsListenerAndWindowsInterface(t *testing.T) {
	for _, test := range []struct {
		name, listenerState, adapterState, want, reason string
		active                                          bool
	}{
		{"ready", "on", "up", "on", "", true},
		{"missing", "on", "missing", "failed", "interfaceMissing", true},
		{"down", "on", "down", "failed", "interfaceDown", true},
		{"unreadable", "on", "unknown", "unknown", "interfaceUnknown", true},
		{"no_listener", "on", "up", "unknown", "listenerUnavailable", false},
		{"permission_failure", "failed", "up", "failed", "permissionDenied", false},
		{"stopped", "off", "up", "off", "", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			input := listener.TunLifecycleStatus{Revision: 7, RequestedEnabled: true, State: test.listenerState, ListenerActive: test.active, Device: "test-device"}
			if test.name == "permission_failure" {
				input.ErrorCode = "permissionDenied"
			}
			result := makeTunStatus(input, test.adapterState, "windows", "unprivileged", time.UnixMilli(1234))
			if result.State != test.want || result.ErrorCode != test.reason {
				t.Fatalf("unexpected status: %+v", result)
			}
			if result.Revision != 7 || result.ObservedAt != 1234 || !result.RequestedEnabled {
				t.Fatalf("lost observation identity: %+v", result)
			}
		})
	}
}

func TestTunStatusRejectsRacingGeneration(t *testing.T) {
	var revision uint64
	read := func() listener.TunLifecycleStatus {
		revision++
		return listener.TunLifecycleStatus{Revision: revision, State: "on", ListenerActive: true, Device: "test"}
	}
	status := observeTunStatus(read, func(string) string { return "up" }, "windows", "elevated", time.Now())
	if status.State != "unknown" || status.ErrorCode != "transitionInProgress" {
		t.Fatalf("racing listener incorrectly marked ready: %+v", status)
	}
}

func TestTunStatusWireIsBoundedAndIndependentFromPendingPreference(t *testing.T) {
	previousPending, previousRunning := pendingTunEnable, isRunning
	pendingTunEnable, isRunning = true, true
	t.Cleanup(func() { pendingTunEnable, isRunning = previousPending, previousRunning })
	listener.Cleanup()
	status := handleGetTunStatus()
	if status.State == "on" || status.ListenerActive {
		t.Fatalf("preference became actual state: %+v", status)
	}
	encoded, err := json.Marshal(status)
	if err != nil {
		t.Fatal(err)
	}
	var wire map[string]any
	if err := json.Unmarshal(encoded, &wire); err != nil {
		t.Fatal(err)
	}
	if len(wire) > 11 || wire["schemaVersion"] != float64(1) || len(status.CoreInstanceID) != 32 {
		t.Fatalf("invalid wire: %s", encoded)
	}
	if newTunCoreInstanceID() == status.CoreInstanceID {
		t.Fatal("Core identity reused")
	}
}

func TestTunStatusAndroidDoesNotClaimDesktopListenerEvidence(t *testing.T) {
	status := makeTunStatus(listener.TunLifecycleStatus{State: "on", ListenerActive: true}, "notApplicable", "android", "unknown", time.Now())
	if status.State != "unknown" || status.ErrorCode != "unsupportedPlatform" {
		t.Fatalf("wrong ownership: %+v", status)
	}
}

func TestTunInterfaceMatchIsCaseInsensitive(t *testing.T) {
	interfaces := []net.Interface{
		{Name: "Ethernet", Flags: net.FlagUp},
		{Name: "flclashx", Flags: net.FlagUp},
		{Name: "Other", Flags: 0},
	}
	if got := matchTunInterface("FlClashX", interfaces); got != "up" {
		t.Fatalf("case-different adapter not matched: %s", got)
	}
	if got := matchTunInterface("other", interfaces); got != "down" {
		t.Fatalf("down adapter misreported: %s", got)
	}
	if got := matchTunInterface("FlClashX 2", interfaces); got != "missing" {
		t.Fatalf("prefix match accepted: %s", got)
	}
}
