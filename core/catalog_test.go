//go:build !cgo

package main

import (
	"encoding/json"
	"net"
	"strings"
	"testing"
	"time"
)

func catalogAction(t *testing.T, method string, payload any) ActionResult {
	t.Helper()
	encoded, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	responses := make(chan ActionResult, 1)
	action := &Action{Method: Method(method), Data: string(encoded)}
	handleAction(action, ActionResult{Method: action.Method, Response: func(data []byte) {
		var response ActionResult
		if err := json.Unmarshal(data, &response); err != nil {
			panic(err)
		}
		responses <- response
	}})
	select {
	case response := <-responses:
		return response
	case <-time.After(2 * time.Second):
		t.Fatal("catalog action did not complete")
		return ActionResult{}
	}
}

func TestCatalogActionPrepareReturnsOnlyNodeMetadata(t *testing.T) {
	id := "c-contract-0001"
	response := catalogAction(t, "catalogPrepare", map[string]any{
		"catalog-id": id,
		"proxies":    []map[string]any{{"name": "test-node", "type": "ss", "server": "192.0.2.10", "port": 8388, "cipher": "aes-128-gcm", "password": "PRIVATE-CATALOG-FIXTURE"}},
	})
	if response.Code != 0 {
		t.Fatalf("prepare failed: %#v", response.Data)
	}
	defer catalogAction(t, "catalogRelease", map[string]any{"catalog-id": id})
	data, ok := response.Data.(string)
	if !ok {
		t.Fatalf("expected string payload, got %T", response.Data)
	}
	if strings.Contains(data, "PRIVATE-CATALOG-FIXTURE") || strings.Contains(data, "password") {
		t.Fatal("prepare exposed raw credentials")
	}
	var result struct {
		ID    string `json:"catalog-id"`
		Nodes []struct {
			Index     int
			Name      string
			Supported bool
			Port      int
		}
	}
	if err := json.Unmarshal([]byte(data), &result); err != nil {
		t.Fatal(err)
	}
	if result.ID != id || len(result.Nodes) != 1 || result.Nodes[0].Name != "test-node" || !result.Nodes[0].Supported || result.Nodes[0].Port != 8388 {
		t.Fatalf("unexpected metadata: %s", data)
	}
}

func TestCatalogActionRejectsInvalidAndOversizedRequests(t *testing.T) {
	for _, tc := range []struct {
		name    string
		payload any
		reason  string
	}{
		{"invalid id", map[string]any{"catalog-id": "../escape", "proxies": []any{}}, "invalidParameters"},
		{"invalid container", map[string]any{"catalog-id": "c-contract-0002", "proxies": "PRIVATE-BAD-INPUT"}, "invalidParameters"},
		{"too many nodes", map[string]any{"catalog-id": "c-contract-0003", "proxies": make([]map[string]any, 2001)}, "tooManyNodes"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			response := catalogAction(t, "catalogPrepare", tc.payload)
			if response.Code != -1 || response.Data != tc.reason {
				t.Fatalf("got code=%d data=%#v", response.Code, response.Data)
			}
		})
	}
}

func TestCatalogActionUnsupportedNodesRemainVisible(t *testing.T) {
	id := "c-contract-0004"
	response := catalogAction(t, "catalogPrepare", map[string]any{"catalog-id": id, "proxies": []map[string]any{
		{"name": "chain", "type": "ss", "dialer-proxy": "other"},
		{"name": "heavy", "type": "wireguard"},
		{"name": "bad", "type": "ss", "password": "PRIVATE-PARSE-ERROR"},
	}})
	if response.Code != 0 {
		t.Fatalf("prepare failed: %#v", response.Data)
	}
	defer catalogAction(t, "catalogRelease", map[string]any{"catalog-id": id})
	var result struct {
		Nodes []struct {
			Index     int
			Supported bool
			Reason    string
		}
	}
	data := response.Data.(string)
	if err := json.Unmarshal([]byte(data), &result); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(data, "PRIVATE-PARSE-ERROR") || len(result.Nodes) != 3 {
		t.Fatalf("unexpected metadata: %s", data)
	}
	for i, reason := range []string{"chainUnsupported", "typeUnsupported", "parseFailed"} {
		if result.Nodes[i].Index != i || result.Nodes[i].Supported || result.Nodes[i].Reason != reason {
			t.Fatalf("node %d = %#v", i, result.Nodes[i])
		}
	}
}

func TestCatalogActionReleaseIsIdempotent(t *testing.T) {
	for i := 0; i < 2; i++ {
		response := catalogAction(t, "catalogRelease", map[string]any{"catalog-id": "c-missing-0001"})
		if response.Code != 0 || response.Data != true {
			t.Fatalf("release failed: %#v", response)
		}
	}
}

func TestCatalogActionTestRequiresRequestID(t *testing.T) {
	response := catalogAction(t, "catalogTestDelay", map[string]any{"catalog-id": "c-missing-0001", "index": 0, "timeout": 1})
	if response.Code != 0 {
		t.Fatalf("test response failed: %#v", response.Data)
	}
	var delay Delay
	if err := json.Unmarshal([]byte(response.Data.(string)), &delay); err != nil {
		t.Fatal(err)
	}
	if delay.Value != -1 || delay.Reason != "invalidParameters" {
		t.Fatalf("unexpected delay: %#v", delay)
	}
}

func TestCatalogSuccessfulResultNeverBroadcastsToActiveConnection(t *testing.T) {
	catalogFixture(t)
	id := "c-no-broadcast-0001"
	catalogPrepareOK(t, id, nil)
	left, right := net.Pipe()
	defer right.Close()
	output := newCoreOutput(left, time.Second, time.Second)
	connMu.Lock()
	previous := conn
	conn = output
	connMu.Unlock()
	defer func() { connMu.Lock(); conn = previous; connMu.Unlock(); output.close() }()
	done := make(chan string, 1)
	handleCatalogTestDelay(catalogRequest(id, "one-result", 1000), nil, func(data string) { done <- data })
	result := catalogResult(t, done)
	if result.Value != 17 || result.Name != "fixture" {
		t.Fatalf("unexpected catalog result: %#v", result)
	}
	// The runner has released its admission slot before delivering this callback;
	// observe its completion path before checking the uncorrelated stream queue.
	if len(delayTaskSlots) != 0 {
		t.Fatal("completion retained admission")
	}
	if len(output.queue) != 0 || output.bytes.Load() != 0 {
		t.Fatal("catalog result polluted active stream")
	}
}

func TestCatalogConnectionCloseOnlyReleasesItsOwner(t *testing.T) {
	proxies := catalogFixture(t)
	oldConn, oldPeer := net.Pipe()
	defer oldPeer.Close()
	oldDetach := attachCoreConnection(oldConn)
	defer oldDetach()
	connMu.Lock()
	oldOutput := conn
	connMu.Unlock()
	id := "c-reconnect-0001"
	catalogPrepareOK(t, id, oldOutput.owner)
	newConn, newPeer := net.Pipe()
	defer newPeer.Close()
	newDetach := attachCoreConnection(newConn)
	defer newDetach()
	connMu.Lock()
	newOutput := conn
	connMu.Unlock()
	catalogPrepareOK(t, id, newOutput.owner)
	oldDetach()
	if (*proxies)[0].closed.Load() != 1 || (*proxies)[1].closed.Load() != 0 {
		t.Fatal("stale disconnect closed current catalog")
	}
	newDetach()
	if (*proxies)[1].closed.Load() != 1 {
		t.Fatal("current disconnect retained its catalog")
	}
}
