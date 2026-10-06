package main

import (
	"crypto/rand"
	"encoding/hex"
	"net"
	"runtime"
	"time"

	"github.com/metacubex/mihomo/listener"
)

const tunStatusSchemaVersion = 1

// This identifier is an observation epoch, not an authentication credential.
// A fresh Core cannot inherit a green status from a previous process.
var tunCoreInstanceID = newTunCoreInstanceID()

func newTunCoreInstanceID() string {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		panic(err)
	}
	return hex.EncodeToString(value[:])
}

type TunStatus struct {
	SchemaVersion    int    `json:"schemaVersion"`
	CoreInstanceID   string `json:"coreInstanceId"`
	Revision         uint64 `json:"revision"`
	ObservedAt       int64  `json:"observedAt"`
	RequestedEnabled bool   `json:"requestedEnabled"`
	State            string `json:"state"`
	ListenerActive   bool   `json:"listenerActive"`
	Device           string `json:"device"`
	ErrorCode        string `json:"errorCode,omitempty"`
	Privilege        string `json:"privilege"`
	InterfaceState   string `json:"interfaceState"`
}

// Querying status has no configuration, service, route or retry side effects.
// A listener snapshot is not a proxy/Internet connectivity assertion.
func handleGetTunStatus() TunStatus {
	return observeTunStatus(listener.GetTunLifecycleStatus, observeTunInterface, runtime.GOOS, corePrivilege(), time.Now())
}

func observeTunStatus(read func() listener.TunLifecycleStatus, probe func(string) string, platform, privilege string, now time.Time) TunStatus {
	for attempt := 0; attempt < 2; attempt++ {
		observed := read()
		interfaceState := "notApplicable"
		if platform == "windows" {
			interfaceState = "unknown"
			if observed.ListenerActive {
				interfaceState = probe(observed.Device)
			}
		}
		current := read()
		if current.Revision != observed.Revision {
			continue
		}
		return makeTunStatus(observed, interfaceState, platform, privilege, now)
	}
	status := makeTunStatus(read(), "unknown", platform, privilege, now)
	status.State = "unknown"
	status.ErrorCode = "transitionInProgress"
	return status
}

func makeTunStatus(observed listener.TunLifecycleStatus, interfaceState, platform, privilege string, now time.Time) TunStatus {
	status := TunStatus{
		SchemaVersion: tunStatusSchemaVersion, CoreInstanceID: tunCoreInstanceID,
		Revision: observed.Revision, ObservedAt: now.UnixMilli(),
		RequestedEnabled: observed.RequestedEnabled, State: observed.State,
		ListenerActive: observed.ListenerActive, Device: observed.Device,
		ErrorCode: observed.ErrorCode, Privilege: privilege, InterfaceState: interfaceState,
	}
	if platform == "android" {
		// Android owns TUN through VpnService, not Mihomo's desktop listener.
		status.State, status.ErrorCode = "unknown", "unsupportedPlatform"
		return status
	}
	if observed.State == "on" && !observed.ListenerActive {
		status.State, status.ErrorCode = "unknown", "listenerUnavailable"
	} else if observed.State == "on" && platform == "windows" {
		switch interfaceState {
		case "up":
		case "down":
			status.State, status.ErrorCode = "failed", "interfaceDown"
		case "missing":
			status.State, status.ErrorCode = "failed", "interfaceMissing"
		default:
			status.State, status.ErrorCode = "unknown", "interfaceUnknown"
		}
	}
	return status
}

func observeTunInterface(name string) string {
	if name == "" {
		return "unknown"
	}
	interfaces, err := net.Interfaces()
	if err != nil {
		return "unknown"
	}
	for _, adapter := range interfaces {
		if adapter.Name == name {
			if adapter.Flags&net.FlagUp != 0 {
				return "up"
			}
			return "down"
		}
	}
	return "missing"
}
