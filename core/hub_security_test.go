package main

import (
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
