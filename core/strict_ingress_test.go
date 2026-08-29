package main

import (
	"encoding/json"
	"io"
	"net"
	"reflect"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
)

func strictIngressCredential(ch byte) string {
	return strings.Repeat(string(ch), 64)
}

func strictIngressTestConfig(t *testing.T, withWorkGroup bool) *config.Config {
	t.Helper()
	contents := []byte("{}")
	if withWorkGroup {
		contents = []byte("proxy-groups:\n  - name: Work\n    type: select\n    proxies: [DIRECT]\n")
	}
	coreConfig, err := config.Parse(contents)
	if err != nil {
		t.Fatalf("parse strict ingress test config: %v", err)
	}
	coreConfig.Listeners = map[string]C.InboundListener{}
	return coreConfig
}

func TestStrictIngressPlanIsBoundedCanonicalAndLoopbackOnly(t *testing.T) {
	request := StrictIngressRequest{
		Protocol:   strictIngressProtocol,
		Generation: 7,
		Entries: []StrictIngressRequestEntry{
			{
				TargetGroup: "Work",
				Username:    strictIngressCredential('a'),
				Password:    strictIngressCredential('b'),
			},
			{
				TargetGroup: "GLOBAL",
				Username:    strictIngressCredential('c'),
				Password:    strictIngressCredential('d'),
			},
		},
	}
	coreConfig := strictIngressTestConfig(t, true)

	listeners, ordered, err := buildStrictIngressListeners(&request, coreConfig)
	if err != nil {
		t.Fatalf("build strict ingress: %v", err)
	}
	if len(listeners) != 2 || len(ordered) != 2 {
		t.Fatalf("unexpected strict ingress cardinality: %d/%d", len(listeners), len(ordered))
	}
	if ordered[0].TargetGroup != "GLOBAL" || ordered[1].TargetGroup != "Work" {
		t.Fatalf("target groups are not canonical: %#v", ordered)
	}
	for _, entry := range ordered {
		inbound := listeners[entry.ListenerName]
		if inbound == nil {
			t.Fatalf("missing listener %q", entry.ListenerName)
		}
		if inbound.RawAddress() != "127.0.0.1:0" {
			t.Fatalf("strict ingress is not ephemeral loopback: %q", inbound.RawAddress())
		}
	}
}

func TestStrictIngressRejectsMissingGroupsDuplicatesAndWeakCredentials(t *testing.T) {
	coreConfig := strictIngressTestConfig(t, false)
	valid := StrictIngressRequest{
		Protocol:   strictIngressProtocol,
		Generation: 1,
		Entries: []StrictIngressRequestEntry{{
			TargetGroup: "GLOBAL",
			Username:    strictIngressCredential('a'),
			Password:    strictIngressCredential('b'),
		}},
	}

	missing := valid
	missing.Entries = append([]StrictIngressRequestEntry(nil), valid.Entries...)
	missing.Entries[0].TargetGroup = "Missing"
	if _, _, err := buildStrictIngressListeners(&missing, coreConfig); err == nil {
		t.Fatal("missing target group accepted")
	}

	duplicate := valid
	duplicate.Entries = append(append([]StrictIngressRequestEntry(nil), valid.Entries...), valid.Entries[0])
	if _, _, err := buildStrictIngressListeners(&duplicate, coreConfig); err == nil {
		t.Fatal("duplicate target group accepted")
	}

	weak := valid
	weak.Entries = append([]StrictIngressRequestEntry(nil), valid.Entries...)
	weak.Entries[0].Password = "password"
	if _, _, err := buildStrictIngressListeners(&weak, coreConfig); err == nil {
		t.Fatal("weak strict ingress credential accepted")
	}

	notGroup := valid
	notGroup.Entries = append([]StrictIngressRequestEntry(nil), valid.Entries...)
	notGroup.Entries[0].TargetGroup = "DIRECT"
	if _, _, err := buildStrictIngressListeners(&notGroup, coreConfig); err == nil {
		t.Fatal("ordinary proxy accepted as strict ingress target group")
	}
}

func TestStrictIngressBindsAuthenticatesIsIdempotentAndRevokes(t *testing.T) {
	if runtime.GOOS != "windows" {
		t.Skip("strict ingress is a Windows-only M3 capability")
	}
	username := strictIngressCredential('a')
	password := strictIngressCredential('b')
	request := StrictIngressRequest{
		Protocol:   strictIngressProtocol,
		Generation: 19,
		Entries: []StrictIngressRequestEntry{{
			TargetGroup: "GLOBAL",
			Username:    username,
			Password:    password,
		}},
	}
	encoded, err := json.Marshal(request)
	if err != nil {
		t.Fatalf("encode strict ingress request: %v", err)
	}
	testConfig := strictIngressTestConfig(t, false)

	runLock.Lock()
	previousConfig := currentConfig
	previousRunning := isRunning
	previousStrict := activeStrictIngress
	previousAgentAuthentication := agentCoreAuthenticated.Load()
	currentConfig = testConfig
	isRunning = true
	activeStrictIngress = nil
	agentCoreAuthenticated.Store(true)
	runLock.Unlock()
	t.Cleanup(func() {
		runLock.Lock()
		removeStrictIngressListenersLocked()
		currentConfig = previousConfig
		isRunning = previousRunning
		activeStrictIngress = previousStrict
		agentCoreAuthenticated.Store(previousAgentAuthentication)
		runLock.Unlock()
	})

	first, err := handleConfigureStrictIngress(string(encoded))
	if err != nil {
		t.Fatalf("configure strict ingress: %v", err)
	}
	second, err := handleConfigureStrictIngress(string(encoded))
	if err != nil {
		t.Fatalf("repeat strict ingress request: %v", err)
	}
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("idempotent request changed endpoint: %#v / %#v", first, second)
	}
	if len(first.Entries) != 1 {
		t.Fatalf("unexpected strict ingress result: %#v", first)
	}
	endpoint := first.Entries[0].Endpoint
	conflict := request
	conflict.Entries = append([]StrictIngressRequestEntry(nil), request.Entries...)
	conflict.Entries[0].Password = strictIngressCredential('c')
	conflictJSON, err := json.Marshal(conflict)
	if err != nil {
		t.Fatalf("encode conflicting strict ingress request: %v", err)
	}
	if _, err := handleConfigureStrictIngress(string(conflictJSON)); err == nil {
		t.Fatal("conflicting request with the active generation was accepted")
	}
	conn, err := net.DialTimeout("tcp", endpoint, time.Second)
	if err != nil {
		t.Fatalf("connect strict SOCKS ingress: %v", err)
	}
	if err := conn.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatalf("set strict SOCKS deadline: %v", err)
	}
	if _, err := conn.Write([]byte{0x05, 0x01, 0x02}); err != nil {
		t.Fatalf("write SOCKS methods: %v", err)
	}
	method := make([]byte, 2)
	if _, err := io.ReadFull(conn, method); err != nil {
		t.Fatalf("read SOCKS method: %v", err)
	}
	if !reflect.DeepEqual(method, []byte{0x05, 0x02}) {
		t.Fatalf("strict SOCKS listener did not require authentication: %v", method)
	}
	auth := []byte{0x01, byte(len(username))}
	auth = append(auth, username...)
	auth = append(auth, byte(len(password)))
	auth = append(auth, password...)
	if _, err := conn.Write(auth); err != nil {
		t.Fatalf("write SOCKS credentials: %v", err)
	}
	authResult := make([]byte, 2)
	if _, err := io.ReadFull(conn, authResult); err != nil {
		t.Fatalf("read SOCKS auth result: %v", err)
	}
	if !reflect.DeepEqual(authResult, []byte{0x01, 0x00}) {
		t.Fatalf("strict SOCKS credentials were rejected: %v", authResult)
	}
	_ = conn.Close()

	disable, err := json.Marshal(StrictIngressRequest{
		Protocol:   strictIngressProtocol,
		Generation: 20,
		Entries:    []StrictIngressRequestEntry{},
	})
	if err != nil {
		t.Fatalf("encode strict ingress disable: %v", err)
	}
	if _, err := handleConfigureStrictIngress(string(disable)); err != nil {
		t.Fatalf("disable strict ingress: %v", err)
	}
	if conn, err := net.DialTimeout("tcp", endpoint, 250*time.Millisecond); err == nil {
		_ = conn.Close()
		t.Fatal("revoked strict ingress endpoint still accepts connections")
	}

	runLock.Lock()
	currentConfig = nil
	isRunning = false
	runLock.Unlock()
	if _, err := handleConfigureStrictIngress(string(disable)); err != nil {
		t.Fatalf("idempotent revocation without an active config: %v", err)
	}
}

func TestStrictIngressRejectsUnauthenticatedMalformedAndOversizedRequests(t *testing.T) {
	previousAgentAuthentication := agentCoreAuthenticated.Load()
	agentCoreAuthenticated.Store(false)
	t.Cleanup(func() { agentCoreAuthenticated.Store(previousAgentAuthentication) })

	valid := `{"protocol":1,"generation":1,"entries":[]}`
	if _, err := handleConfigureStrictIngress(valid); err == nil {
		t.Fatal("unauthenticated strict ingress action accepted")
	}

	if _, err := parseStrictIngressRequest(valid + ` {}`); err == nil {
		t.Fatal("strict ingress request with trailing JSON accepted")
	}
	if _, err := parseStrictIngressRequest(`{"protocol":1,"generation":1,"entries":[],"unknown":true}`); err == nil {
		t.Fatal("strict ingress request with unknown fields accepted")
	}
	if _, err := parseStrictIngressRequest(strings.Repeat("x", maxStrictIngressRequestBytes+1)); err == nil {
		t.Fatal("oversized strict ingress request accepted")
	}
}
