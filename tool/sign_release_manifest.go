// Command sign_release_manifest signs FreedomNet signed release manifests
// (latest.json) using Ed25519 over recursively sorted compact UTF-8 JSON.
package main

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
)

const (
	defaultKeyID                = "fn-2026-v1"
	defaultKeyEnvVar            = "FCX_RELEASE_ED25519_PRIVATE_KEY"
	defaultStage1PublicKeyB64   = "8eQ/Pe9ABxs/drZReKxG5XpNrASXxF2SuPn02ykbGXI="
	defaultStage1BootstrapJSON  = `{"payload":{"expires_at":"2028-11-16T00:00:00Z","issued_at":"2026-11-16T00:00:00Z","key_id":"fn-2026-v1","origins":[{"capabilities":["api","sub","update","geox"],"origin":"https://api.westernmoviefans.com","priority":10,"role":"primary"},{"capabilities":["api","sub","update","geox"],"origin":"https://fast.hjy.ca:8443","priority":20,"role":"direct"}],"schema_version":1,"tenant_id":"freedomnet-prod"},"signature":"0E50yFNR0krp7CYFtG_s4XiSEMOVir0OR5cpRvpTKq7MQYs6cHwjqcZELJ5gIrt3IY54WgBIOpMZj6Y7NB6uDQ"}`
	defaultManifestValidDays    = 30
	supportedManifestSchema     = 1
)

type cliOptions struct {
	inPath      string
	outPath     string
	keyEnv      string
	keyID       string
	publicKey   string
	version     string
	channel     string
	distDir     string
	baseURL     string
	notes       string
	notesFile   string
	publishedAt string
	expiresAt   string
	validDays   int
	selfTest    bool
	verify      bool
}

type targetArtifact struct {
	target    string
	priority  int
	format    string
	entry     string
	filename  string
	url       string
	size      int64
	sha256Hex string
}

func main() {
	if err := run(os.Args[1:], os.Stdin, os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "sign_release_manifest: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string, stdin io.Reader, stdout io.Writer) error {
	var opts cliOptions
	fs := flag.NewFlagSet("sign_release_manifest", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	fs.StringVar(&opts.inPath, "in", "", "Input payload JSON path (or '-' for stdin; or signed envelope with --verify)")
	fs.StringVar(&opts.outPath, "out", "", "Output signed latest.json path (or '-' / empty for stdout)")
	fs.StringVar(&opts.keyEnv, "key-env", defaultKeyEnvVar, "Environment variable containing base64 Ed25519 private key or 32-byte seed")
	fs.StringVar(&opts.keyID, "key-id", defaultKeyID, "Signing key ID embedded into generated manifest payloads")
	fs.StringVar(&opts.publicKey, "public-key", "", "Base64 or hex 32-byte Ed25519 public key for --verify (defaults to pinned fn-2026-v1 key)")
	fs.StringVar(&opts.version, "version", "", "Release version (Mode B manifest builder)")
	fs.StringVar(&opts.channel, "channel", "stable", "Release channel (stable|beta) for Mode B manifest builder")
	fs.StringVar(&opts.distDir, "dist", "", "Directory containing built release installers/archives for Mode B")
	fs.StringVar(&opts.baseURL, "base-url", "", "Base download URL prefix for artifacts in Mode B")
	fs.StringVar(&opts.notes, "notes", "", "Inline release notes string for Mode B")
	fs.StringVar(&opts.notesFile, "notes-file", "", "Markdown/text file containing release notes for Mode B")
	fs.StringVar(&opts.publishedAt, "published-at", "", "UTC RFC3339 published timestamp override for Mode B")
	fs.StringVar(&opts.expiresAt, "expires-at", "", "UTC RFC3339 expiry timestamp override for Mode B")
	fs.IntVar(&opts.validDays, "valid-days", defaultManifestValidDays, "Validity days from published_at when --expires-at is omitted")
	fs.BoolVar(&opts.selfTest, "self-test", false, "Run built-in canonicalization and Stage-1 fn-2026-v1 Ed25519 verification tests")
	fs.BoolVar(&opts.verify, "verify", false, "Verify a signed latest.json envelope instead of signing")
	fs.Usage = func() {
		fmt.Fprintf(fs.Output(), "Usage of sign_release_manifest:\n")
		fmt.Fprintf(fs.Output(), "  Mode A (sign JSON payload): go run ./tool/sign_release_manifest.go --in payload.json --out latest.json\n")
		fmt.Fprintf(fs.Output(), "  Mode B (build+sign from --dist): go run ./tool/sign_release_manifest.go --version 1.2.3 --channel stable --dist ./dist --base-url https://cdn.example/releases/v1.2.3 --out ./dist/latest.json\n")
		fmt.Fprintf(fs.Output(), "  Mode C (self-test): go run ./tool/sign_release_manifest.go --self-test\n")
		fmt.Fprintf(fs.Output(), "  Mode D (verify): go run ./tool/sign_release_manifest.go --verify --in latest.json [--public-key <b64>]\n\n")
		fs.PrintDefaults()
	}

	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}

	if opts.selfTest {
		if err := runSelfTest(); err != nil {
			return err
		}
		_, err := fmt.Fprintln(stdout, "self-test OK")
		return err
	}

	if opts.verify {
		raw, err := readInputBytes(opts.inPath, stdin)
		if err != nil {
			return err
		}
		keyID, err := verifyEnvelope(raw, opts.publicKey)
		if err != nil {
			return err
		}
		_, err = fmt.Fprintf(stdout, "verified OK (key_id=%s)\n", keyID)
		return err
	}

	privKey, err := loadPrivateKeyFromEnv(opts.keyEnv)
	if err != nil {
		return err
	}

	var payloadValue any
	switch {
	case opts.inPath != "":
		raw, err := readInputBytes(opts.inPath, stdin)
		if err != nil {
			return err
		}
		payloadValue, err = decodeSingleJSONValue(raw)
		if err != nil {
			return fmt.Errorf("parse --in JSON: %w", err)
		}
	case opts.version != "" || opts.distDir != "" || opts.baseURL != "":
		payloadValue, err = buildReleasePayload(opts)
		if err != nil {
			return err
		}
	default:
		return errors.New("specify --in <payload.json>, Mode B flags (--version, --dist, --base-url), --verify, or --self-test (use --help for usage)")
	}

	envelopeBytes, err := signPayloadValue(payloadValue, privKey)
	if err != nil {
		return err
	}
	return writeOutputBytes(opts.outPath, append(envelopeBytes, '\n'), stdout)
}

func runSelfTest() error {
	stage1Pub, err := parsePublicKey(defaultStage1PublicKeyB64)
	if err != nil {
		return fmt.Errorf("decode Stage-1 public key: %w", err)
	}
	keyID, err := verifyEnvelope([]byte(defaultStage1BootstrapJSON), base64.StdEncoding.EncodeToString(stage1Pub))
	if err != nil {
		return fmt.Errorf("verify Stage-1 bootstrap vector: %w", err)
	}
	if keyID != defaultKeyID {
		return fmt.Errorf("unexpected Stage-1 key_id %q", keyID)
	}

	canonicalSample, err := decodeSingleJSONValue([]byte(`{"z":"a&b<c>","a":{"d":2,"b":1},"arr":[{"y":true,"x":10}]}`))
	if err != nil {
		return err
	}
	canonicalBytes, err := canonicalMarshal(canonicalSample)
	if err != nil {
		return err
	}
	expectedCanonical := `{"a":{"b":1,"d":2},"arr":[{"x":10,"y":true}],"z":"a&b<c>"}`
	if string(canonicalBytes) != expectedCanonical {
		return fmt.Errorf("canonical mismatch:\n  got:  %s\n  want: %s", canonicalBytes, expectedCanonical)
	}

	pub, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return fmt.Errorf("generate ephemeral Ed25519 key: %w", err)
	}
	sampleManifest := map[string]any{
		"schema_version": json.Number(strconv.Itoa(supportedManifestSchema)),
		"key_id":         defaultKeyID,
		"channel":        "stable",
		"version":        "1.2.3",
		"published_at":   "2026-11-16T00:00:00Z",
		"expires_at":     "2026-12-16T00:00:00Z",
		"release_notes":  "Self-test release",
		"targets": map[string]any{
			"windows-x64": map[string]any{
				"format":   "inno-exe",
				"entry":    "FreedomNet.exe",
				"filename": "FreedomNet-1.2.3-windows-x64-setup.exe",
				"url":      "https://api.westernmoviefans.com/releases/1.2.3/FreedomNet-1.2.3-windows-x64-setup.exe",
				"size":     json.Number("1048576"),
				"sha256":   strings.Repeat("a", 64),
			},
		},
	}
	signedEnvelope, err := signPayloadValue(sampleManifest, priv)
	if err != nil {
		return fmt.Errorf("sign sample manifest: %w", err)
	}
	pubB64 := base64.StdEncoding.EncodeToString(pub)
	if _, err := verifyEnvelope(signedEnvelope, pubB64); err != nil {
		return fmt.Errorf("verify signed sample manifest: %w", err)
	}

	tampered := bytes.Replace(signedEnvelope, []byte(`"1.2.3"`), []byte(`"1.2.4"`), 1)
	if _, err := verifyEnvelope(tampered, pubB64); err == nil {
		return errors.New("tampered manifest unexpectedly passed verification")
	}

	tmpDist, err := os.MkdirTemp("", "fcx-manifest-selftest-*")
	if err != nil {
		return fmt.Errorf("create temp dist: %w", err)
	}
	defer os.RemoveAll(tmpDist)
	sampleName := "FreedomNet-1.2.3-windows-x64-setup.exe"
	if err := os.WriteFile(filepath.Join(tmpDist, sampleName), []byte("installer-bytes"), 0o644); err != nil {
		return fmt.Errorf("write sample artifact: %w", err)
	}
	builtPayload, err := buildReleasePayload(cliOptions{
		version:   "1.2.3",
		channel:   "stable",
		distDir:   tmpDist,
		baseURL:   "https://api.westernmoviefans.com/api/v1/client/releases/files/1.2.3",
		keyID:     defaultKeyID,
		validDays: defaultManifestValidDays,
	})
	if err != nil {
		return fmt.Errorf("build Mode B payload: %w", err)
	}
	targets, ok := builtPayload["targets"].(map[string]any)
	if !ok {
		return errors.New("Mode B payload missing targets map")
	}
	winTarget, ok := targets["windows-x64"].(map[string]any)
	if !ok {
		return errors.New("Mode B payload missing windows-x64 target")
	}
	artifacts, ok := winTarget["artifacts"].([]any)
	if !ok || len(artifacts) == 0 {
		return errors.New("Mode B windows-x64 target missing artifacts")
	}
	firstArtifact, ok := artifacts[0].(map[string]any)
	if !ok || firstArtifact["name"] != sampleName || firstArtifact["filename"] != sampleName {
		return fmt.Errorf("Mode B artifact must carry both name and filename=%q, got %#v", sampleName, artifacts[0])
	}
	builtEnvelope, err := signPayloadValue(builtPayload, priv)
	if err != nil {
		return fmt.Errorf("sign Mode B payload: %w", err)
	}
	if _, err := verifyEnvelope(builtEnvelope, pubB64); err != nil {
		return fmt.Errorf("verify signed Mode B payload: %w", err)
	}
	return nil
}

func loadPrivateKeyFromEnv(envName string) (ed25519.PrivateKey, error) {
	if strings.TrimSpace(envName) == "" {
		return nil, errors.New("--key-env cannot be empty")
	}
	raw := strings.TrimSpace(os.Getenv(envName))
	if raw == "" {
		return nil, fmt.Errorf("environment variable %s is empty or unset", envName)
	}
	decoded, err := decodeFlexibleKeyBytes(raw)
	if err != nil {
		return nil, fmt.Errorf("decode %s: %w", envName, err)
	}
	switch len(decoded) {
	case ed25519.PrivateKeySize:
		return ed25519.PrivateKey(decoded), nil
	case ed25519.SeedSize:
		return ed25519.NewKeyFromSeed(decoded), nil
	default:
		return nil, fmt.Errorf("%s must decode to 32-byte Ed25519 seed or 64-byte private key, got %d bytes", envName, len(decoded))
	}
}

func parsePublicKey(raw string) (ed25519.PublicKey, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		raw = defaultStage1PublicKeyB64
	}
	decoded, err := decodeFlexibleKeyBytes(raw)
	if err != nil {
		return nil, err
	}
	if len(decoded) != ed25519.PublicKeySize {
		return nil, fmt.Errorf("expected 32-byte Ed25519 public key, got %d bytes", len(decoded))
	}
	return ed25519.PublicKey(decoded), nil
}

func decodeFlexibleKeyBytes(raw string) ([]byte, error) {
	if (len(raw) == 64 || len(raw) == 128) && isHexString(raw) {
		if b, err := hex.DecodeString(raw); err == nil {
			return b, nil
		}
	}
	encodings := []*base64.Encoding{
		base64.StdEncoding,
		base64.RawStdEncoding,
		base64.URLEncoding,
		base64.RawURLEncoding,
	}
	for _, enc := range encodings {
		if b, err := enc.DecodeString(raw); err == nil {
			return b, nil
		}
	}
	if b, err := hex.DecodeString(raw); err == nil {
		return b, nil
	}
	return nil, errors.New("expected base64 or hex encoded key material")
}

func isHexString(s string) bool {
	for i := 0; i < len(s); i++ {
		c := s[i]
		isHex := (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
		if !isHex {
			return false
		}
	}
	return len(s) > 0
}

func signPayloadValue(payloadValue any, priv ed25519.PrivateKey) ([]byte, error) {
	payloadCanonical, err := canonicalMarshal(payloadValue)
	if err != nil {
		return nil, fmt.Errorf("canonicalize payload: %w", err)
	}
	sig := ed25519.Sign(priv, payloadCanonical)
	sigB64 := base64.RawURLEncoding.EncodeToString(sig)

	var out bytes.Buffer
	out.WriteString(`{"payload":`)
	out.Write(payloadCanonical)
	out.WriteString(`,"signature":`)
	sigJSON, err := marshalCompactString(sigB64)
	if err != nil {
		return nil, err
	}
	out.Write(sigJSON)
	out.WriteByte('}')
	return out.Bytes(), nil
}

func verifyEnvelope(raw []byte, pubKeyOverride string) (string, error) {
	val, err := decodeSingleJSONValue(raw)
	if err != nil {
		return "", fmt.Errorf("parse signed envelope: %w", err)
	}
	obj, ok := val.(map[string]any)
	if !ok {
		return "", errors.New("signed envelope must be a JSON object")
	}
	payloadVal, hasPayload := obj["payload"]
	if !hasPayload {
		return "", errors.New("signed envelope missing 'payload'")
	}
	sigRaw, _ := obj["signature"].(string)
	if strings.TrimSpace(sigRaw) == "" {
		return "", errors.New("signed envelope missing 'signature'")
	}

	var keyID string
	if payloadMap, ok := payloadVal.(map[string]any); ok {
		keyID, _ = payloadMap["key_id"].(string)
	}
	if strings.TrimSpace(pubKeyOverride) == "" && keyID != "" && keyID != defaultKeyID {
		return "", fmt.Errorf("unsupported key_id %q without --public-key", keyID)
	}
	pub, err := parsePublicKey(pubKeyOverride)
	if err != nil {
		return "", fmt.Errorf("parse public key: %w", err)
	}

	sigBytes, err := decodeSignature(sigRaw)
	if err != nil {
		return "", fmt.Errorf("decode signature: %w", err)
	}
	payloadCanonical, err := canonicalMarshal(payloadVal)
	if err != nil {
		return "", fmt.Errorf("canonicalize payload: %w", err)
	}
	if !ed25519.Verify(pub, payloadCanonical, sigBytes) {
		return "", errors.New("Ed25519 signature verification failed")
	}
	return keyID, nil
}

func decodeSignature(sig string) ([]byte, error) {
	sig = strings.TrimSpace(sig)
	for _, enc := range []*base64.Encoding{
		base64.RawURLEncoding,
		base64.URLEncoding,
		base64.StdEncoding,
		base64.RawStdEncoding,
	} {
		if b, err := enc.DecodeString(sig); err == nil && len(b) == ed25519.SignatureSize {
			return b, nil
		}
	}
	return nil, errors.New("signature must decode to 64 bytes")
}

func buildReleasePayload(opts cliOptions) (map[string]any, error) {
	version := strings.TrimPrefix(strings.TrimSpace(opts.version), "v")
	if version == "" {
		return nil, errors.New("--version is required in Mode B")
	}
	channel := strings.TrimSpace(opts.channel)
	if channel == "" {
		channel = "stable"
	}
	distDir := strings.TrimSpace(opts.distDir)
	if distDir == "" {
		return nil, errors.New("--dist is required in Mode B")
	}
	baseURL := strings.TrimRight(strings.TrimSpace(opts.baseURL), "/")
	if baseURL == "" {
		return nil, errors.New("--base-url is required in Mode B")
	}
	keyID := strings.TrimSpace(opts.keyID)
	if keyID == "" {
		keyID = defaultKeyID
	}

	publishedTime := time.Now().UTC().Truncate(time.Second)
	if strings.TrimSpace(opts.publishedAt) != "" {
		t, err := time.Parse(time.RFC3339, strings.TrimSpace(opts.publishedAt))
		if err != nil {
			return nil, fmt.Errorf("parse --published-at: %w", err)
		}
		publishedTime = t.UTC()
	}
	var expiresTime time.Time
	if strings.TrimSpace(opts.expiresAt) != "" {
		t, err := time.Parse(time.RFC3339, strings.TrimSpace(opts.expiresAt))
		if err != nil {
			return nil, fmt.Errorf("parse --expires-at: %w", err)
		}
		expiresTime = t.UTC()
	} else {
		validDays := opts.validDays
		if validDays <= 0 {
			validDays = defaultManifestValidDays
		}
		expiresTime = publishedTime.Add(time.Duration(validDays) * 24 * time.Hour)
	}

	notes := opts.notes
	if strings.TrimSpace(opts.notesFile) != "" {
		content, err := os.ReadFile(opts.notesFile)
		if err != nil {
			return nil, fmt.Errorf("read --notes-file: %w", err)
		}
		notes = strings.TrimSpace(string(content))
	}

	artifactsByTarget, err := collectDistArtifacts(distDir, baseURL)
	if err != nil {
		return nil, err
	}
	if len(artifactsByTarget) == 0 {
		return nil, fmt.Errorf("no recognized release artifacts found under %s", distDir)
	}

	targetsMap := make(map[string]any, len(artifactsByTarget))
	for target, list := range artifactsByTarget {
		sort.Slice(list, func(i, j int) bool {
			if list[i].priority != list[j].priority {
				return list[i].priority < list[j].priority
			}
			return list[i].filename < list[j].filename
		})
		primary := list[0]
		artifactEntries := make([]any, 0, len(list))
		for _, item := range list {
			artifactEntries = append(artifactEntries, map[string]any{
				"entry":    item.entry,
				"filename": item.filename,
				"format":   item.format,
				"name":     item.filename,
				"sha256":   item.sha256Hex,
				"size":     json.Number(strconv.FormatInt(item.size, 10)),
				"url":      item.url,
			})
		}
		targetsMap[target] = map[string]any{
			"artifacts": artifactEntries,
			"entry":     primary.entry,
			"filename":  primary.filename,
			"format":    primary.format,
			"sha256":    primary.sha256Hex,
			"size":      json.Number(strconv.FormatInt(primary.size, 10)),
			"url":       primary.url,
		}
	}

	return map[string]any{
		"channel":        channel,
		"expires_at":     expiresTime.Format(time.RFC3339),
		"key_id":         keyID,
		"published_at":   publishedTime.Format(time.RFC3339),
		"release_notes":  notes,
		"schema_version": json.Number(strconv.Itoa(supportedManifestSchema)),
		"targets":        targetsMap,
		"version":        version,
	}, nil
}

func collectDistArtifacts(distDir string, baseURL string) (map[string][]targetArtifact, error) {
	info, err := os.Stat(distDir)
	if err != nil {
		return nil, fmt.Errorf("stat --dist %s: %w", distDir, err)
	}
	if !info.IsDir() {
		return nil, fmt.Errorf("--dist path is not a directory: %s", distDir)
	}

	results := make(map[string][]targetArtifact)
	err = filepath.WalkDir(distDir, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if d.IsDir() {
			return nil
		}
		name := d.Name()
		lower := strings.ToLower(name)
		if lower == "latest.json" || strings.HasSuffix(lower, ".sha256") || strings.HasSuffix(lower, ".sig") || strings.HasSuffix(lower, ".json") {
			return nil
		}
		target, format, entry, priority, ok := classifyReleaseArtifact(lower)
		if !ok {
			return nil
		}
		size, sumHex, err := hashFileSHA256(path)
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(distDir, path)
		if err != nil {
			return err
		}
		relSlash := filepath.ToSlash(rel)
		results[target] = append(results[target], targetArtifact{
			target:    target,
			priority:  priority,
			format:    format,
			entry:     entry,
			filename:  name,
			url:       baseURL + "/" + strings.TrimLeft(relSlash, "/"),
			size:      size,
			sha256Hex: sumHex,
		})
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("scan --dist: %w", err)
	}
	return results, nil
}

func classifyReleaseArtifact(lowerName string) (target, format, entry string, priority int, ok bool) {
	arch := "x64"
	switch {
	case strings.Contains(lowerName, "arm64") || strings.Contains(lowerName, "aarch64"):
		arch = "arm64"
	case strings.Contains(lowerName, "x64") || strings.Contains(lowerName, "amd64") || strings.Contains(lowerName, "x86_64"):
		arch = "x64"
	}

	switch {
	case strings.HasSuffix(lowerName, ".exe"):
		if strings.Contains(lowerName, "macos") || strings.Contains(lowerName, "linux") {
			return "", "", "", 0, false
		}
		return "windows-" + arch, "inno-exe", "FreedomNet.exe", 1, true
	case strings.HasSuffix(lowerName, ".exe.p7m"):
		return "windows-" + arch, "inno-exe-p7m", "FreedomNet.exe", 3, true
	case strings.HasSuffix(lowerName, ".dmg"):
		return "macos-" + arch, "dmg", "FreedomNet.app", 1, true
	case strings.HasSuffix(lowerName, ".pkg"):
		return "macos-" + arch, "pkg", "FreedomNet.app", 2, true
	case strings.HasSuffix(lowerName, ".appimage"):
		return "linux-" + arch, "appimage", "freedomnet", 1, true
	case strings.HasSuffix(lowerName, ".deb"):
		return "linux-" + arch, "deb", "freedomnet", 2, true
	case strings.HasSuffix(lowerName, ".rpm"):
		return "linux-" + arch, "rpm", "freedomnet", 3, true
	case strings.HasSuffix(lowerName, ".tar.gz"):
		if strings.Contains(lowerName, "macos") || strings.Contains(lowerName, "darwin") {
			return "macos-" + arch, "tar-gz", "FreedomNet.app", 3, true
		}
		if strings.Contains(lowerName, "linux") {
			return "linux-" + arch, "tar-gz", "freedomnet", 4, true
		}
		return "", "", "", 0, false
	case strings.HasSuffix(lowerName, ".zip"):
		if strings.Contains(lowerName, "macos") || strings.Contains(lowerName, "darwin") {
			return "macos-" + arch, "portable-zip", "FreedomNet.app", 2, true
		}
		if strings.Contains(lowerName, "linux") {
			return "linux-" + arch, "portable-zip", "freedomnet", 5, true
		}
		return "windows-" + arch, "portable-zip", "FreedomNet.exe", 2, true
	default:
		return "", "", "", 0, false
	}
}

func hashFileSHA256(path string) (int64, string, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, "", fmt.Errorf("open %s: %w", path, err)
	}
	defer f.Close()
	h := sha256.New()
	n, err := io.Copy(h, f)
	if err != nil {
		return 0, "", fmt.Errorf("hash %s: %w", path, err)
	}
	return n, hex.EncodeToString(h.Sum(nil)), nil
}

func decodeSingleJSONValue(raw []byte) (any, error) {
	dec := json.NewDecoder(bytes.NewReader(bytes.TrimSpace(raw)))
	dec.UseNumber()
	var val any
	if err := dec.Decode(&val); err != nil {
		return nil, err
	}
	var extra any
	if err := dec.Decode(&extra); !errors.Is(err, io.EOF) {
		return nil, errors.New("unexpected trailing data after JSON value")
	}
	return val, nil
}

func canonicalMarshal(v any) ([]byte, error) {
	var buf bytes.Buffer
	if err := writeCanonicalJSON(&buf, v); err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func writeCanonicalJSON(buf *bytes.Buffer, v any) error {
	switch typed := v.(type) {
	case nil:
		buf.WriteString("null")
		return nil
	case bool:
		if typed {
			buf.WriteString("true")
		} else {
			buf.WriteString("false")
		}
		return nil
	case json.Number:
		s := typed.String()
		if _, err := strconv.ParseFloat(s, 64); err != nil {
			return fmt.Errorf("invalid JSON number %q: %w", s, err)
		}
		buf.WriteString(s)
		return nil
	case string:
		encoded, err := marshalCompactString(typed)
		if err != nil {
			return err
		}
		buf.Write(encoded)
		return nil
	case []any:
		buf.WriteByte('[')
		for i, item := range typed {
			if i > 0 {
				buf.WriteByte(',')
			}
			if err := writeCanonicalJSON(buf, item); err != nil {
				return err
			}
		}
		buf.WriteByte(']')
		return nil
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for k := range typed {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		buf.WriteByte('{')
		for i, k := range keys {
			if i > 0 {
				buf.WriteByte(',')
			}
			encodedKey, err := marshalCompactString(k)
			if err != nil {
				return err
			}
			buf.Write(encodedKey)
			buf.WriteByte(':')
			if err := writeCanonicalJSON(buf, typed[k]); err != nil {
				return err
			}
		}
		buf.WriteByte('}')
		return nil
	default:
		return fmt.Errorf("unsupported JSON value type %T", v)
	}
}

func marshalCompactString(s string) ([]byte, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(s); err != nil {
		return nil, err
	}
	return bytes.TrimSuffix(buf.Bytes(), []byte{'\n'}), nil
}

func readInputBytes(path string, stdin io.Reader) ([]byte, error) {
	if path == "-" {
		return io.ReadAll(stdin)
	}
	if strings.TrimSpace(path) == "" {
		return nil, errors.New("--in path is required")
	}
	return os.ReadFile(path)
}

func writeOutputBytes(path string, data []byte, stdout io.Writer) error {
	if strings.TrimSpace(path) == "" || path == "-" {
		_, err := stdout.Write(data)
		return err
	}
	if dir := filepath.Dir(path); dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("create output directory: %w", err)
		}
	}
	return os.WriteFile(path, data, 0o644)
}
