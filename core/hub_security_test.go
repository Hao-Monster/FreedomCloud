package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func TestConfiguredHomeAllowsOnlyStartupSafePath(t *testing.T) {
	root := t.TempDir()
	allowed := filepath.Join(root, "allowed")
	other := filepath.Join(root, "other")
	if err := os.MkdirAll(allowed, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(other, 0o755); err != nil {
		t.Fatal(err)
	}

	if !configuredHomeAllowed(allowed, allowed) {
		t.Fatal("the startup safe path must be accepted")
	}
	if configuredHomeAllowed(other, allowed) {
		t.Fatal("IPC must not be able to replace the startup safe path")
	}
}

func TestGetConfigRejectsFilesOutsideCoreHome(t *testing.T) {
	previousHome := constant.Path.HomeDir()
	t.Cleanup(func() { constant.SetHomeDir(previousHome) })

	root := t.TempDir()
	home := filepath.Join(root, "home")
	outside := filepath.Join(root, "outside.yaml")
	if err := os.MkdirAll(home, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outside, []byte("port: 7890\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	constant.SetHomeDir(home)

	if _, err := handleGetConfig(outside); err == nil {
		t.Fatal("privileged core must not read a config outside its data root")
	}
}

func TestConfiguredHomeAcceptsOneEntryFromSafePathList(t *testing.T) {
	root := t.TempDir()
	first := filepath.Join(root, "first")
	second := filepath.Join(root, "second")
	for _, path := range []string{first, second} {
		if err := os.MkdirAll(path, 0o755); err != nil {
			t.Fatal(err)
		}
	}

	if !configuredHomeAllowed(second, filepath.Join(first)+string(os.PathListSeparator)+second) {
		t.Fatal("a canonical entry in SAFE_PATHS must be accepted")
	}
}

func TestConfiguredHomeAcceptsWindowsExtendedLengthEquivalent(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("Windows extended-length paths are platform-specific")
	}
	root := t.TempDir()
	home := filepath.Join(root, "home")
	if err := os.MkdirAll(home, 0o755); err != nil {
		t.Fatal(err)
	}
	extended := `\\?\` + home
	if !configuredHomeAllowed(home, extended) {
		t.Fatal("extended-length and drive-letter paths must compare as the same directory")
	}
}

func TestGetConfigActionReturnsStringErrorAndRequiresInit(t *testing.T) {
	previousHome := constant.Path.HomeDir()
	previousInit := isInit.Load()
	t.Cleanup(func() {
		constant.SetHomeDir(previousHome)
		isInit.Store(previousInit)
	})

	root := t.TempDir()
	home := filepath.Join(root, "home")
	validProfile := filepath.Join(home, "profiles", "a.yaml")
	outside := filepath.Join(root, "outside.yaml")
	if err := os.MkdirAll(filepath.Dir(validProfile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(validProfile, []byte("port: 7890\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(outside, []byte("port: 7890\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	constant.SetHomeDir(home)

	// 1. Before initClash completes (isInit == false), profile getConfig must
	// return a structured string "not_ready:core_uninitialized" instead of
	// racing constant.Path.IsSafePath or serializing a raw Go error struct.
	isInit.Store(false)
	var uninitPayload []byte
	handleAction(
		&Action{Id: "req-uninit", Method: getConfigMethod, Data: validProfile},
		ActionResult{
			Id:     "req-uninit",
			Method: getConfigMethod,
			Response: func(b []byte) {
				uninitPayload = append([]byte(nil), b...)
			},
		},
	)
	var uninitWire map[string]any
	if err := json.Unmarshal(uninitPayload, &uninitWire); err != nil {
		t.Fatalf("failed to unmarshal uninit getConfig response: %v", err)
	}
	if code, _ := uninitWire["code"].(float64); code == 0 {
		t.Fatalf("expected error code when core is uninitialized, got payload=%s", string(uninitPayload))
	}
	if msg, ok := uninitWire["data"].(string); !ok || msg != "not_ready:core_uninitialized" {
		t.Fatalf("expected string data 'not_ready:core_uninitialized', got %#v (payload=%s)", uninitWire["data"], string(uninitPayload))
	}

	// 2. When initialized (isInit == true) and handleGetConfig returns an error,
	// ActionResult must serialize err.Error() as a JSON string, never `{}`.
	isInit.Store(true)
	var errPayload []byte
	handleAction(
		&Action{Id: "req-outside", Method: getConfigMethod, Data: outside},
		ActionResult{
			Id:     "req-outside",
			Method: getConfigMethod,
			Response: func(b []byte) {
				errPayload = append([]byte(nil), b...)
			},
		},
	)
	var errWire map[string]any
	if err := json.Unmarshal(errPayload, &errWire); err != nil {
		t.Fatalf("failed to unmarshal error getConfig response: %v", err)
	}
	if code, _ := errWire["code"].(float64); code == 0 {
		t.Fatalf("expected non-zero error code for unsafe path, got payload=%s", string(errPayload))
	}
	if msg, ok := errWire["data"].(string); !ok || msg == "" {
		t.Fatalf("expected non-empty string error in ActionResult.data, got %T %#v (payload=%s)", errWire["data"], errWire["data"], string(errPayload))
	}
}
