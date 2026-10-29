package main

import (
	"bytes"
	"compress/gzip"
	"encoding/base64"
	"encoding/json"
	"github.com/metacubex/mihomo/adapter/provider"
	"io"
)

var catalogProviderParseSlots = make(chan struct{}, 2)

const catalogPayloadFrameBytes = 512 * 1024
const catalogPayloadDecodedBytes = 12 * 1024 * 1024

// The envelope leaves room for Action metadata below the shared 1 MiB IPC
// ceiling. It does not retain credentials or create a chunk/session cache.
func decodeCatalogPayload(data string) (string, string) {
	escaped, err := json.Marshal(data)
	if err != nil || len(escaped) > catalogPayloadFrameBytes {
		return "", "providerTooLarge"
	}
	var envelope struct {
		Payload string `json:"payload-gzip"`
	}
	if json.Unmarshal([]byte(data), &envelope) != nil || envelope.Payload == "" {
		return "", "invalidParameters"
	}
	compressed, err := base64.StdEncoding.DecodeString(envelope.Payload)
	if err != nil {
		return "", "invalidParameters"
	}
	reader, err := gzip.NewReader(bytes.NewReader(compressed))
	if err != nil {
		return "", "invalidParameters"
	}
	defer reader.Close()
	decoded, err := io.ReadAll(io.LimitReader(reader, catalogPayloadDecodedBytes+1))
	if len(decoded) > catalogPayloadDecodedBytes {
		return "", "providerTooLarge"
	}
	if err != nil {
		return "", "invalidParameters"
	}
	return string(decoded), ""
}

func encodeCatalogPayload(data string) (string, string) {
	if len(data) > catalogPayloadDecodedBytes {
		return "", "providerTooLarge"
	}
	var output bytes.Buffer
	writer := gzip.NewWriter(&output)
	if _, err := writer.Write([]byte(data)); err != nil {
		return "", "parseFailed"
	}
	if writer.Close() != nil {
		return "", "parseFailed"
	}
	encoded, err := json.Marshal(map[string]string{"payload-gzip": base64.StdEncoding.EncodeToString(output.Bytes())})
	if err != nil {
		return "", "parseFailed"
	}
	escaped, err := json.Marshal(string(encoded))
	if err != nil || len(escaped) > catalogPayloadFrameBytes {
		return "", "providerTooLarge"
	}
	return string(encoded), ""
}

func parseCatalogProviderMessage(data string) (string, string) {
	select {
	case catalogProviderParseSlots <- struct{}{}:
		defer func() { <-catalogProviderParseSlots }()
	default:
		return "", "overloaded"
	}
	decoded, reason := decodeCatalogPayload(data)
	if reason != "" {
		return "", reason
	}
	parsed, reason := parseCatalogProviderDecoded(decoded)
	if reason != "" {
		return "", reason
	}
	return encodeCatalogPayload(parsed)
}

// parseCatalogProvider is a pure, bounded provider decoding boundary.
func parseCatalogProvider(data string) (string, string) {
	select {
	case catalogProviderParseSlots <- struct{}{}:
		defer func() { <-catalogProviderParseSlots }()
	default:
		return "", "overloaded"
	}
	return parseCatalogProviderDecoded(data)
}

func parseCatalogProviderDecoded(data string) (string, string) {
	if len(data) > 12*1024*1024 {
		return "", "providerTooLarge"
	}
	var params struct {
		Content    string         `json:"content-base64"`
		Definition map[string]any `json:"definition"`
	}
	if json.Unmarshal([]byte(data), &params) != nil || params.Definition == nil {
		return "", "invalidParameters"
	}
	definitionBytes, err := json.Marshal(params.Definition)
	if err != nil || len(definitionBytes) > 8*1024*1024 {
		return "", "providerTooLarge"
	}
	content, err := base64.StdEncoding.DecodeString(params.Content)
	if err != nil {
		return "", "invalidParameters"
	}
	proxies, rejected, err := provider.FCXParseCatalogProvider(content, params.Definition)
	if err != nil {
		switch err.Error() {
		case "providerTooLarge", "providerOptionsUnsupported", "deadlineExceeded":
			return "", err.Error()
		}
		return "", "parseFailed"
	}
	if proxies == nil {
		proxies = []map[string]any{}
	}
	encoded, err := json.Marshal(struct {
		Proxies  []map[string]any `json:"proxies"`
		Rejected int              `json:"rejected"`
	}{proxies, rejected})
	if err != nil {
		return "", "parseFailed"
	}
	if len(encoded) > 12*1024*1024 {
		return "", "providerTooLarge"
	}
	return string(encoded), ""
}
