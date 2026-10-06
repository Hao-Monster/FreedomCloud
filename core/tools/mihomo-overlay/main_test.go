package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCheckedSourceRejectsTampering(t *testing.T) {
	path := filepath.Join(t.TempDir(), "source.go")
	initial := []byte("package original\n")
	if err := os.WriteFile(path, initial, 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := checkedSource(path, digest(initial)); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("package changed\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := checkedSource(path, digest(initial)); err == nil {
		t.Fatal("changed upstream source accepted")
	}
}

const minimalListener = `package listener
import (
	"github.com/metacubex/mihomo/listener/sing_tun"
)
var tunLister *sing_tun.Listener
func GetTunConf() LC.Tun { return LastTunConf }
func ReCreateTun(tunConf LC.Tun, tunnel C.Tunnel) {}
func closeTunListener() {}
func Cleanup() {}
`

func TestPatchIsDeterministicAndRejectsChangedShape(t *testing.T) {
	first, err := patchListener([]byte(minimalListener))
	if err != nil {
		t.Fatal(err)
	}
	second, err := patchListener([]byte(minimalListener))
	if err != nil || !bytes.Equal(first, second) {
		t.Fatalf("patch is nondeterministic: %v", err)
	}
	if !bytes.Contains(first, []byte("fcxCreateTun")) || !bytes.Contains(first, []byte("tunMux.Lock()")) {
		t.Fatal("lifecycle patch missing")
	}
	changed := strings.Replace(minimalListener, "func Cleanup() {}", "", 1)
	if _, err := patchListener([]byte(changed)); err == nil {
		t.Fatal("missing upstream function accepted")
	}
}

func TestProvenanceDigestIgnoresMapOrderAndDetectsAnyFileChange(t *testing.T) {
	left := map[string]string{"b": digest([]byte("b")), "a": digest([]byte("a"))}
	right := map[string]string{"a": digest([]byte("a")), "b": digest([]byte("b"))}
	if aggregateHashes(left) != aggregateHashes(right) {
		t.Fatal("manifest ordering affects digest")
	}
	right["b"] = digest([]byte("tampered"))
	if aggregateHashes(left) == aggregateHashes(right) {
		t.Fatal("manifest missed changed file")
	}
}

func TestModuleCopyDoesNotModifySourceOrReuseOldFiles(t *testing.T) {
	source, target := t.TempDir(), t.TempDir()
	if err := os.WriteFile(filepath.Join(source, "module.go"), []byte("original"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := copyModule(source, target); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(target, "module.go"), []byte("modified"), 0600); err != nil {
		t.Fatal(err)
	}
	contents, err := os.ReadFile(filepath.Join(source, "module.go"))
	if err != nil || string(contents) != "original" {
		t.Fatalf("module source changed: %q %v", contents, err)
	}
	fresh := t.TempDir()
	if err := copyModule(source, fresh); err != nil {
		t.Fatal(err)
	}
	hashes, err := treeHashes(fresh)
	if err != nil || hashes["module.go"] != digest([]byte("original")) {
		t.Fatal("fresh copy inherited altered output")
	}
}

func TestContentAddressedPublicationRejectsInjectedFilesAndRetainsEvidence(t *testing.T) {
	root := t.TempDir()
	staging, destination := filepath.Join(root, "staging"), filepath.Join(root, "published")
	if err := os.Mkdir(staging, 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(staging, "legitimate.go"), []byte("original"), 0600); err != nil {
		t.Fatal(err)
	}
	expected, err := treeHashes(staging)
	if err != nil {
		t.Fatal(err)
	}
	if err := publishModuleCopy(staging, destination, expected); err != nil {
		t.Fatal(err)
	}
	if err := publishModuleCopy(staging, destination, expected); err != nil {
		t.Fatal("identical source tree rejected:", err)
	}
	injected := filepath.Join(destination, "injected.go")
	if err := os.WriteFile(injected, []byte("unexpected"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := publishModuleCopy(staging, destination, expected); err == nil {
		t.Fatal("extra build input accepted")
	}
	if contents, err := os.ReadFile(injected); err != nil || string(contents) != "unexpected" {
		t.Fatal("untrusted existing source was changed or deleted")
	}
}
