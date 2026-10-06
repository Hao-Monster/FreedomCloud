// mihomo-overlay creates a checked Go build overlay without modifying the module
// cache. The fixed upstream source hashes make dependency drift a build error.
package main

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"go/ast"
	"go/format"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed patches/*.txt
var patchFiles embed.FS

const upstreamVersion = "v1.19.32"
const upstreamCommit = "88dcbf7f1614a67c3b36b848ee3592dfa92ada36"
const upstreamModuleSum = "h1:uD7ZC3P77isWD554NNvtee65L+99+/C5hyc+Lk8rVEk="
const listenerSHA256 = "1a11cda3fb4a87875d817fe29f1e79973cb8cb6eeccc0ae5e22db15df1277758"
const configsSHA256 = "d11710296ea68a8d12f7593ec50cec9fef830272b3a54f64f707ec86920baf9f"

func main() {
	out := flag.String("out", ".generated/mihomo-overlay.json", "generated overlay path")
	flag.Parse()
	if err := generate(*out); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func checkedSource(path, expected string) ([]byte, error) {
	source, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	digest := sha256.Sum256(source)
	if hex.EncodeToString(digest[:]) != expected {
		return nil, fmt.Errorf("upstream source hash mismatch: %s", path)
	}
	return source, nil
}

type replacement struct {
	start, end int
	text       string
}

func patchListener(source []byte) ([]byte, error) {
	fset := token.NewFileSet()
	file, err := parser.ParseFile(fset, "listener.go", source, 0)
	if err != nil {
		return nil, err
	}
	names := map[string]string{
		"GetTunConf": "get_tun_conf.txt", "ReCreateTun": "recreate_tun.txt",
		"closeTunListener": "close_tun.txt", "Cleanup": "cleanup.txt",
	}
	var changes []replacement
	for _, declaration := range file.Decls {
		fn, ok := declaration.(*ast.FuncDecl)
		if !ok {
			continue
		}
		name, ok := names[fn.Name.Name]
		if !ok {
			continue
		}
		body, err := patchFiles.ReadFile("patches/" + name)
		if err != nil {
			return nil, err
		}
		changes = append(changes, replacement{fset.Position(fn.Pos()).Offset, fset.Position(fn.End()).Offset, string(body)})
	}
	if len(changes) != len(names) {
		return nil, fmt.Errorf("upstream TUN function set changed")
	}
	sort.Slice(changes, func(i, j int) bool { return changes[i].start > changes[j].start })
	patched := string(source)
	for _, change := range changes {
		patched = patched[:change.start] + change.text + patched[change.end:]
	}
	if strings.Count(patched, "*sing_tun.Listener") != 1 {
		return nil, fmt.Errorf("upstream TUN listener declaration changed")
	}
	patched = strings.Replace(patched, "*sing_tun.Listener", "fcxTunListener", 1)
	patched = strings.Replace(patched, "\t\"github.com/metacubex/mihomo/listener/sing_tun\"\n", "", 1)
	return format.Source([]byte(patched))
}

func generate(out string) error {
	command := exec.Command("go", "list", "-m", "-json", "github.com/metacubex/mihomo")
	data, err := command.Output()
	if err != nil {
		return fmt.Errorf("resolve pinned mihomo module: %w", err)
	}
	var module struct {
		Version, Dir, Sum string
		Replace           json.RawMessage
	}
	if err := json.Unmarshal(data, &module); err != nil {
		return err
	}
	if module.Version != upstreamVersion || len(module.Replace) != 0 {
		return fmt.Errorf("expected unmodified mihomo %s module", upstreamVersion)
	}
	command = exec.Command("go", "mod", "download", "-json", "github.com/metacubex/mihomo@"+upstreamVersion)
	data, err = command.Output()
	if err != nil {
		return fmt.Errorf("download pinned mihomo module: %w", err)
	}
	if err := json.Unmarshal(data, &module); err != nil {
		return err
	}
	if module.Dir == "" || module.Sum != upstreamModuleSum {
		return fmt.Errorf("pinned mihomo module checksum mismatch")
	}
	if output, err := exec.Command("go", "mod", "verify").CombinedOutput(); err != nil {
		return fmt.Errorf("module integrity verification failed: %w: %s", err, output)
	}
	listenerPath := filepath.Join(module.Dir, "listener", "listener.go")
	listenerSource, err := checkedSource(listenerPath, listenerSHA256)
	if err != nil {
		return err
	}
	patchedListener, err := patchListener(listenerSource)
	if err != nil {
		return err
	}
	configsPath := filepath.Join(module.Dir, "hub", "route", "configs.go")
	configsSource, err := checkedSource(configsPath, configsSHA256)
	if err != nil {
		return err
	}
	if strings.Count(string(configsSource), "listener.LastTunConf") != 1 {
		return fmt.Errorf("upstream TUN route configuration access changed")
	}
	patchedConfigs := []byte(strings.Replace(string(configsSource), "listener.LastTunConf", "listener.GetTunConf()", 1))
	out, err = filepath.Abs(out)
	if err != nil {
		return err
	}
	directory := filepath.Join(filepath.Dir(out), "mihomo-"+upstreamVersion)
	if err := os.MkdirAll(directory, 0755); err != nil {
		return err
	}
	// Go deliberately forbids overlays inside GOMODCACHE. Build against an
	// isolated generated module copy instead; never alter cached dependency files.
	stagingDirectory, err := os.MkdirTemp(filepath.Dir(out), "mihomo-"+upstreamVersion+"-staging-")
	if err != nil {
		return err
	}
	if err := copyModule(module.Dir, stagingDirectory); err != nil {
		return err
	}
	stagingHashes, err := treeHashes(stagingDirectory)
	if err != nil {
		return err
	}
	sourceDirectory := filepath.Join(filepath.Dir(out), "mihomo-"+upstreamVersion+"-source-"+aggregateHashes(stagingHashes))
	if err := publishModuleCopy(stagingDirectory, sourceDirectory, stagingHashes); err != nil {
		return err
	}
	listenerPath = filepath.Join(sourceDirectory, "listener", "listener.go")
	configsPath = filepath.Join(sourceDirectory, "hub", "route", "configs.go")
	replacements := map[string]string{}
	write := func(original, name string, contents []byte) error {
		target := filepath.Join(directory, name)
		if err := os.WriteFile(target, contents, 0644); err != nil {
			return err
		}
		replacements[original] = target
		return nil
	}
	if err := write(listenerPath, "listener.go", patchedListener); err != nil {
		return err
	}
	if err := write(configsPath, "configs.go", patchedConfigs); err != nil {
		return err
	}
	for _, name := range []string{"tun_status_fcx.go", "tun_status_fcx_test.go"} {
		contents, err := patchFiles.ReadFile("patches/" + name + ".txt")
		if err != nil {
			return err
		}
		contents, err = format.Source(contents)
		if err != nil {
			return err
		}
		if err := write(filepath.Join(sourceDirectory, "listener", name), name, contents); err != nil {
			return err
		}
	}
	encoded, err := json.MarshalIndent(struct{ Replace map[string]string }{replacements}, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(out, append(encoded, '\n'), 0644); err != nil {
		return err
	}
	modfile := filepath.Join(filepath.Dir(out), "go.mod")
	for _, name := range []string{"go.mod", "go.sum"} {
		contents, err := os.ReadFile(name)
		if err != nil {
			return err
		}
		if err := os.WriteFile(filepath.Join(filepath.Dir(out), name), contents, 0644); err != nil {
			return err
		}
	}
	workingDirectory, err := os.Getwd()
	if err != nil {
		return err
	}
	relativeSource, err := filepath.Rel(workingDirectory, sourceDirectory)
	if err != nil {
		return err
	}
	relativeSource = filepath.ToSlash(relativeSource)
	if !strings.HasPrefix(relativeSource, "../") {
		relativeSource = "./" + relativeSource
	}
	command = exec.Command("go", "mod", "edit", "-modfile="+modfile, "-replace=github.com/metacubex/mihomo="+relativeSource)
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("create isolated module file: %w: %s", err, output)
	}
	patchHashes := map[string]string{}
	patchEntries, err := patchFiles.ReadDir("patches")
	if err != nil {
		return err
	}
	for _, entry := range patchEntries {
		contents, err := patchFiles.ReadFile("patches/" + entry.Name())
		if err != nil {
			return err
		}
		patchHashes[entry.Name()] = digest(contents)
	}
	moduleHashes, err := treeHashes(sourceDirectory)
	if err != nil {
		return err
	}
	for original, overlay := range replacements {
		relative, err := filepath.Rel(sourceDirectory, original)
		if err != nil {
			return err
		}
		contents, err := os.ReadFile(overlay)
		if err != nil {
			return err
		}
		moduleHashes[filepath.ToSlash(relative)] = digest(contents)
	}
	generatorSource, err := os.ReadFile(filepath.Join("tools", "mihomo-overlay", "main.go"))
	if err != nil {
		return err
	}
	rootMod, err := os.ReadFile("go.mod")
	if err != nil {
		return err
	}
	manifest, err := json.MarshalIndent(map[string]any{
		"schemaVersion": 1, "module": "github.com/metacubex/mihomo", "version": upstreamVersion,
		"commit": upstreamCommit, "moduleSum": module.Sum,
		"upstreamSourceSHA256": map[string]string{"listener/listener.go": listenerSHA256, "hub/route/configs.go": configsSHA256},
		"patchesSHA256":        patchHashes, "generatorSHA256": digest(generatorSource), "projectGoModSHA256": digest(rootMod),
		"effectiveModuleSHA256": aggregateHashes(moduleHashes), "effectiveModuleFiles": moduleHashes,
	}, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(directory, "manifest.json"), append(manifest, '\n'), 0644); err != nil {
		return err
	}
	fmt.Println(out)
	return nil
}

// Publication never overwrites or deletes an existing generated source tree.
// Every file and extra path is checked before a content-addressed tree is reused.
func publishModuleCopy(staging, destination string, expected map[string]string) error {
	if _, err := os.Lstat(destination); os.IsNotExist(err) {
		if err := os.Rename(staging, destination); err != nil {
			return fmt.Errorf("publish generated module: %w", err)
		}
		return nil
	} else if err != nil {
		return err
	}
	actual, err := treeHashes(destination)
	if err != nil {
		return err
	}
	if aggregateHashes(actual) != aggregateHashes(expected) {
		return fmt.Errorf("generated module integrity mismatch; refusing existing source tree: %s", destination)
	}
	return nil
}

func digest(contents []byte) string {
	value := sha256.Sum256(contents)
	return hex.EncodeToString(value[:])
}

func aggregateHashes(hashes map[string]string) string {
	paths := make([]string, 0, len(hashes))
	for path := range hashes {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	var content strings.Builder
	for _, path := range paths {
		content.WriteString(path + "\x00" + hashes[path] + "\n")
	}
	return digest([]byte(content.String()))
}

func treeHashes(root string) (map[string]string, error) {
	result := map[string]string{}
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("unexpected symlink in source tree: %s", path)
		}
		if entry.IsDir() {
			return nil
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		result[filepath.ToSlash(relative)] = digest(contents)
		return nil
	})
	return result, err
}

func copyModule(source, destination string) error {
	return filepath.WalkDir(source, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		target := filepath.Join(destination, relative)
		if entry.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("unexpected symlink in verified module: %s", relative)
		}
		if entry.IsDir() {
			return os.MkdirAll(target, 0755)
		}
		contents, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		return os.WriteFile(target, contents, 0644)
	})
}
