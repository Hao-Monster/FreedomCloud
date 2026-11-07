//go:build windows

package main

import (
	"errors"
	"net"
	"strings"
	"testing"
	"time"

	"golang.org/x/sys/windows"
)

func TestObserveWindowsTunInterfaceUsesTargetedLookupWithoutFullEnumeration(t *testing.T) {
	fallbackCalls := 0
	fallback := func(string) string {
		fallbackCalls++
		return "up"
	}

	got := observeWindowsTunInterfaceWith(
		"FlClashX Meta Tunnel",
		func(alias string) (uint64, error) {
			if alias != "FlClashX Meta Tunnel" {
				t.Fatalf("unexpected alias: %s", alias)
			}
			return 42, nil
		},
		func(luid uint64) (uint32, error) {
			if luid != 42 {
				t.Fatalf("unexpected luid: %d", luid)
			}
			return windows.IfOperStatusUp, nil
		},
		fallback,
	)
	if got != "up" || fallbackCalls != 0 {
		t.Fatalf("expected fast up with 0 fallbacks, got state=%s fallbacks=%d", got, fallbackCalls)
	}

	got = observeWindowsTunInterfaceWith(
		"FlClashX Meta Tunnel",
		func(string) (uint64, error) { return 42, nil },
		func(uint64) (uint32, error) { return windows.IfOperStatusDown, nil },
		fallback,
	)
	if got != "down" || fallbackCalls != 0 {
		t.Fatalf("expected fast down with 0 fallbacks, got state=%s fallbacks=%d", got, fallbackCalls)
	}

	for _, missingErr := range []error{
		windows.ERROR_FILE_NOT_FOUND,
		windows.ERROR_INVALID_PARAMETER,
		windows.ERROR_NOT_FOUND,
	} {
		got = observeWindowsTunInterfaceWith(
			"Missing Tunnel",
			func(string) (uint64, error) { return 0, missingErr },
			func(uint64) (uint32, error) {
				t.Fatal("status query must not run when alias does not exist")
				return 0, nil
			},
			fallback,
		)
		if got != "missing" || fallbackCalls != 0 {
			t.Fatalf("expected fast missing for %v with 0 fallbacks, got state=%s fallbacks=%d", missingErr, got, fallbackCalls)
		}
	}

	got = observeWindowsTunInterfaceWith(
		"FlClashX Meta Tunnel",
		func(string) (uint64, error) { return 0, errors.New("unexpected rpc error") },
		func(uint64) (uint32, error) { return 0, nil },
		fallback,
	)
	if got != "up" || fallbackCalls != 1 {
		t.Fatalf("expected fallback on unexpected error, got state=%s fallbacks=%d", got, fallbackCalls)
	}
}

func TestObserveWindowsTunInterfaceLiveAdapterMatchesCaseInsensitivelyAndIsFast(t *testing.T) {
	interfaces, err := net.Interfaces()
	if err != nil || len(interfaces) == 0 {
		t.Skipf("no Windows interfaces available: %v", err)
	}

	var target net.Interface
	for _, candidate := range interfaces {
		if candidate.Name != "" {
			target = candidate
			if candidate.Flags&net.FlagUp != 0 {
				break
			}
		}
	}
	if target.Name == "" {
		t.Skip("no named Windows interface found")
	}
	want := matchTunInterface(target.Name, interfaces)

	started := time.Now()
	gotExact := observeTunInterface(target.Name)
	elapsed := time.Since(started)
	if gotExact != want {
		t.Fatalf("live fast probe mismatch for %q: got %s, want %s", target.Name, gotExact, want)
	}
	if elapsed > 50*time.Millisecond {
		t.Fatalf("targeted GetIfEntry2Ex probe took too long: %v", elapsed)
	}

	swappedCase := strings.ToUpper(target.Name)
	if swappedCase == target.Name {
		swappedCase = strings.ToLower(target.Name)
	}
	if gotCase := observeTunInterface(swappedCase); gotCase != want {
		t.Fatalf("case-changed probe mismatch for %q: got %s, want %s", swappedCase, gotCase, want)
	}

	if gotMissing := observeTunInterface("FlClashX-NonExistent-Adapter-Test-9f8e7d"); gotMissing != "missing" {
		t.Fatalf("expected missing for non-existent adapter, got %s", gotMissing)
	}
}
