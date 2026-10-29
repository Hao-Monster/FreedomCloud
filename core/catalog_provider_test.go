package main

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"encoding/json"
	logrus "github.com/sirupsen/logrus"
	"math/rand"
	"strings"
	"testing"
)

func TestCatalogProviderMalformedURINeverLogsCredentials(t *testing.T) {
	var captured bytes.Buffer
	logger := logrus.StandardLogger()
	previous := logger.Out
	logger.SetOutput(&captured)
	t.Cleanup(func() { logger.SetOutput(previous) })
	_, reason := parseCatalogProvider(providerPayload("vless://PRIVATE-CREDENTIAL@fixture.invalid#PRIVATE-NAME\n", map[string]any{"type": "http"}))
	if reason != "" {
		t.Fatalf("unexpected reason: %s", reason)
	}
	if captured.Len() != 0 {
		t.Fatal("provider parser emitted a raw URI diagnostic")
	}
}

func TestCatalogProviderCompressedMessageRoundTrip(t *testing.T) {
	var content strings.Builder
	content.WriteString("proxies:\n")
	for i := 0; i < 12000; i++ {
		content.WriteString("- {name: Fixture, type: ss, server: fixture.invalid, port: 443, password: PRIVATE}\n")
	}
	raw := providerPayload(content.String(), map[string]any{"type": "file"})
	if len(raw) < 1024*1024 {
		t.Fatal("fixture must exceed uncompressed frame")
	}
	encoded, reason := encodeCatalogPayload(raw)
	if reason != "" {
		t.Fatal(reason)
	}
	response, reason := parseCatalogProviderMessage(encoded)
	if reason != "" {
		t.Fatal(reason)
	}
	decoded, reason := decodeCatalogPayload(response)
	if reason != "" {
		t.Fatal(reason)
	}
	var result struct {
		Proxies []map[string]any `json:"proxies"`
	}
	if json.Unmarshal([]byte(decoded), &result) != nil || len(result.Proxies) != 12000 {
		t.Fatal("compressed provider lost nodes")
	}
	if result.Proxies[11999]["password"] != "PRIVATE" {
		t.Fatal("mapping altered")
	}
}

func TestCatalogProviderEnvelopeBoundsAndMalformed(t *testing.T) {
	var bomb bytes.Buffer
	w := gzip.NewWriter(&bomb)
	w.Write(bytes.Repeat([]byte("x"), catalogPayloadDecodedBytes+1))
	w.Close()
	encoded, _ := json.Marshal(map[string]string{"payload-gzip": base64.StdEncoding.EncodeToString(bomb.Bytes())})
	if _, reason := parseCatalogProviderMessage(string(encoded)); reason != "providerTooLarge" {
		t.Fatalf("bomb: %s", reason)
	}
	for _, bad := range []string{`PRIVATE`, `{"payload-gzip":"PRIVATE"}`, `{"payload-gzip":"eA=="}`} {
		if _, reason := parseCatalogProviderMessage(bad); reason != "invalidParameters" {
			t.Fatalf("malformed: %s", reason)
		}
	}
	entropy := make([]byte, 700000)
	rand.New(rand.NewSource(42)).Read(entropy)
	if _, reason := encodeCatalogPayload(base64.StdEncoding.EncodeToString(entropy)); reason != "providerTooLarge" {
		t.Fatalf("entropy: %s", reason)
	}
	if _, reason := decodeCatalogPayload(strings.Repeat("x", catalogPayloadFrameBytes)); reason != "providerTooLarge" {
		t.Fatalf("frame: %s", reason)
	}
}

func providerPayload(content string, definition map[string]any) string {
	b, _ := json.Marshal(map[string]any{"content-base64": base64.StdEncoding.EncodeToString([]byte(content)), "definition": definition})
	return string(b)
}

func TestCatalogProviderPureParse(t *testing.T) {
	encoded, reason := parseCatalogProvider(providerPayload("proxies:\n  - {name: One, type: ss, server: example.invalid, port: 443, password: PRIVATE}\n  - {name: Two, type: ss, server: example.invalid, port: 443}\n", map[string]any{"type": "http", "filter": "One", "override": map[string]any{"additional-prefix": "Pref-", "udp": true}}))
	if reason != "" {
		t.Fatalf("parse rejected: %s", reason)
	}
	var result struct {
		Proxies  []map[string]any `json:"proxies"`
		Rejected int              `json:"rejected"`
	}
	if err := json.Unmarshal([]byte(encoded), &result); err != nil {
		t.Fatal(err)
	}
	if len(result.Proxies) != 1 || result.Proxies[0]["name"] != "Pref-One" || result.Proxies[0]["password"] != "PRIVATE" || result.Proxies[0]["udp"] != true || result.Rejected != 0 {
		t.Fatal("provider semantics were not preserved")
	}
}

func TestCatalogProviderURIsReportRejectedLines(t *testing.T) {
	content := "trojan://fixture-password@example.invalid:443#Good\nunknown://PRIVATE\nbroken-private-line\n"
	encoded, reason := parseCatalogProvider(providerPayload(base64.StdEncoding.EncodeToString([]byte(content)), map[string]any{"type": "http"}))
	if reason != "" {
		t.Fatalf("parse rejected: %s", reason)
	}
	var result struct {
		Proxies  []map[string]any `json:"proxies"`
		Rejected int              `json:"rejected"`
	}
	if err := json.Unmarshal([]byte(encoded), &result); err != nil {
		t.Fatal(err)
	}
	if len(result.Proxies) != 1 || result.Rejected != 2 {
		t.Fatalf("missing explicit rejected count: %d/%d", len(result.Proxies), result.Rejected)
	}
}

func TestCatalogProviderInlineAndMalformedSlots(t *testing.T) {
	encoded, reason := parseCatalogProvider(providerPayload("", map[string]any{"type": "inline", "payload": []any{map[string]any{"name": "A", "type": "tuic", "server": "example.invalid", "port": 443}, map[string]any{"name": "Broken"}}, "dialer-proxy": "Upstream"}))
	if reason != "" {
		t.Fatalf("parse rejected: %s", reason)
	}
	var result struct {
		Proxies []map[string]any `json:"proxies"`
	}
	if err := json.Unmarshal([]byte(encoded), &result); err != nil {
		t.Fatal(err)
	}
	if len(result.Proxies) != 2 || result.Proxies[0]["dialer-proxy"] != "Upstream" {
		t.Fatal("lost unsupported or malformed nodes")
	}
}

func TestCatalogProviderErrorsAreFixedCodes(t *testing.T) {
	for _, data := range []string{"PRIVATE", providerPayload("proxies: PRIVATE", map[string]any{"type": "http"}), providerPayload("proxies: []", map[string]any{"filter": "[PRIVATE"}), strings.Repeat("x", 12*1024*1024+1)} {
		encoded, reason := parseCatalogProvider(data)
		if encoded != "" || (reason != "parseFailed" && reason != "invalidParameters" && reason != "providerTooLarge") {
			t.Fatalf("unsafe error result: encoded length %d, reason %q", len(encoded), reason)
		}
	}
}

func TestCatalogProviderBoundsExpandedOutputAndUnsafeExpressions(t *testing.T) {
	proxies := make([]map[string]any, 100)
	for i := range proxies {
		proxies[i] = map[string]any{"name": "N", "type": "ss"}
	}
	_, reason := parseCatalogProvider(providerPayload("", map[string]any{"type": "inline", "payload": proxies, "override": map[string]any{"additional-prefix": strings.Repeat("x", 100000)}}))
	if reason != "providerTooLarge" {
		t.Fatalf("expanded output was not bounded: %s", reason)
	}
	_, reason = parseCatalogProvider(providerPayload("", map[string]any{"type": "inline", "payload": proxies, "override": map[string]any{"override-expr": []string{".name = \"x\" * 1000000000"}}}))
	if reason != "providerOptionsUnsupported" {
		t.Fatalf("unbounded expression accepted: %s", reason)
	}
	_, reason = parseCatalogProvider(providerPayload("", map[string]any{"type": "inline", "payload": []any{map[string]any{"name": "small-name", "type": "ss"}}, "override": map[string]any{"proxy-name": []any{map[string]any{"pattern": ".", "target": strings.Repeat("x", 1024)}}}}))
	if reason != "providerOptionsUnsupported" {
		t.Fatalf("unbounded replacement accepted: %s", reason)
	}
}

func TestCatalogProviderBadEntriesDoNotDiscardHealthyNodes(t *testing.T) {
	for _, input := range []struct {
		content    string
		definition map[string]any
	}{
		{"proxies:\n- {name: First, type: ss, server: fixture.invalid, port: 443}\n- PRIVATE-BAD-SCALAR\n- {name: Last, type: ss, server: fixture.invalid, port: 443}\n", map[string]any{"type": "file"}},
		{"", map[string]any{"type": "inline", "payload": []any{map[string]any{"name": "First", "type": "ss"}, "PRIVATE-BAD-SCALAR", map[string]any{"name": "Last", "type": "ss"}}}},
	} {
		encoded, reason := parseCatalogProvider(providerPayload(input.content, input.definition))
		if reason != "" {
			t.Fatalf("healthy nodes lost: %s", reason)
		}
		var result struct {
			Proxies  []map[string]any `json:"proxies"`
			Rejected int              `json:"rejected"`
		}
		if err := json.Unmarshal([]byte(encoded), &result); err != nil {
			t.Fatal(err)
		}
		if len(result.Proxies) != 2 || result.Rejected != 1 {
			t.Fatalf("wrong mixed result %d/%d", len(result.Proxies), result.Rejected)
		}
	}
}

func TestCatalogProviderMalformedYAMLDoesNotInventURICounts(t *testing.T) {
	for _, content := range []string{"proxies: [\n- bad\n", "- {name: A, type: ss}\n- bad\n"} {
		encoded, reason := parseCatalogProvider(providerPayload(content, map[string]any{"type": "file"}))
		if encoded != "" || reason != "parseFailed" {
			t.Fatalf("malformed YAML was treated as URI nodes: %s", reason)
		}
	}
}
