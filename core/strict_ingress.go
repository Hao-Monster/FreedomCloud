package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"reflect"
	"runtime"
	"sort"
	"sync"
	"sync/atomic"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
)

const (
	strictIngressProtocol           uint32 = 2
	maxStrictIngressEntries                = 128
	maxStrictIngressRequestBytes           = 128 * 1024
	strictIngressNamePrefix                = "flclashx-strict-"
	strictUDPHealthFrameBytes              = 80
	strictUDPHealthKeyIDBytes              = 16
	strictUDPHealthMagicOffset             = 0
	strictUDPHealthVersionOffset           = 4
	strictUDPHealthKindOffset              = 5
	strictUDPHealthReservedOffset          = 6
	strictUDPHealthGenerationOffset        = 8
	strictUDPHealthKeyIDOffset             = 16
	strictUDPHealthNonceOffset             = 32
	strictUDPHealthTagOffset               = 48
	strictUDPHealthVersion          byte   = 1
	strictUDPHealthPing             byte   = 1
	strictUDPHealthPong             byte   = 2
)

var strictUDPHealthMagic = []byte{'F', 'C', 'X', 'U'}

type StrictIngressRequest struct {
	Protocol   uint32                      `json:"protocol"`
	Generation uint64                      `json:"generation"`
	Entries    []StrictIngressRequestEntry `json:"entries"`
}

type StrictIngressRequestEntry struct {
	TargetGroup string `json:"targetGroup"`
	Username    string `json:"username"`
	Password    string `json:"password"`
}

type StrictIngressResult struct {
	Protocol    uint32                     `json:"protocol"`
	Generation  uint64                     `json:"generation"`
	UDPEndpoint string                     `json:"udpEndpoint,omitempty"`
	Entries     []StrictIngressResultEntry `json:"entries"`
}

type StrictIngressResultEntry struct {
	TargetGroup string `json:"targetGroup"`
	Endpoint    string `json:"endpoint"`
}

type strictIngressBuildEntry struct {
	TargetGroup  string
	ListenerName string
}

type strictIngressSession struct {
	request   StrictIngressRequest
	result    StrictIngressResult
	listeners map[string]C.InboundListener
	udpHealth *strictUDPHealthService
}

type strictUDPHealthService struct {
	connection *net.UDPConn
	endpoint   string
	generation uint64
	keys       map[[strictUDPHealthKeyIDBytes]byte][sha256.Size]byte
	done       chan struct{}
	closeOnce  sync.Once
}

var (
	activeStrictIngress    *strictIngressSession
	agentCoreAuthenticated atomic.Bool
)

func parseStrictIngressRequest(data string) (*StrictIngressRequest, error) {
	if len(data) > maxStrictIngressRequestBytes {
		return nil, errors.New("strict ingress request is too large")
	}
	decoder := json.NewDecoder(bytes.NewBufferString(data))
	decoder.DisallowUnknownFields()
	var request StrictIngressRequest
	if err := decoder.Decode(&request); err != nil {
		return nil, err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return nil, errors.New("strict ingress request has trailing data")
	}
	return &request, nil
}

func validateStrictIngressRequestShape(request *StrictIngressRequest) error {
	if request == nil {
		return errors.New("strict ingress request is missing")
	}
	if request.Protocol != strictIngressProtocol || request.Generation == 0 {
		return errors.New("strict ingress protocol or generation is invalid")
	}
	if len(request.Entries) > maxStrictIngressEntries {
		return errors.New("strict ingress entry limit exceeded")
	}
	return nil
}

func canonicalStrictIngressRequest(request *StrictIngressRequest) StrictIngressRequest {
	canonical := *request
	canonical.Entries = append([]StrictIngressRequestEntry(nil), request.Entries...)
	sort.Slice(canonical.Entries, func(left, right int) bool {
		return canonical.Entries[left].TargetGroup < canonical.Entries[right].TargetGroup
	})
	return canonical
}

func buildStrictIngressListeners(
	request *StrictIngressRequest,
	coreConfig *config.Config,
) (map[string]C.InboundListener, []strictIngressBuildEntry, error) {
	if coreConfig == nil {
		return nil, nil, errors.New("strict ingress requires an active Core configuration")
	}
	if err := validateStrictIngressRequestShape(request); err != nil {
		return nil, nil, err
	}

	entries := append([]StrictIngressRequestEntry(nil), request.Entries...)
	sort.Slice(entries, func(left, right int) bool {
		return entries[left].TargetGroup < entries[right].TargetGroup
	})
	listeners := make(map[string]C.InboundListener, len(entries))
	ordered := make([]strictIngressBuildEntry, 0, len(entries))
	for index, entry := range entries {
		if !validStrictTargetGroup(entry.TargetGroup) {
			return nil, nil, errors.New("strict ingress target group is invalid")
		}
		if index > 0 && entries[index-1].TargetGroup == entry.TargetGroup {
			return nil, nil, errors.New("strict ingress target group is duplicated")
		}
		proxy, exists := coreConfig.Proxies[entry.TargetGroup]
		if !exists || proxy == nil {
			return nil, nil, errors.New("strict ingress target group is unavailable")
		}
		if _, isGroup := proxy.Adapter().(outboundgroup.ProxyGroup); !isGroup {
			return nil, nil, errors.New("strict ingress target is not a proxy group")
		}
		if !validStrictCredential(entry.Username) || !validStrictCredential(entry.Password) {
			return nil, nil, errors.New("strict ingress credential is invalid")
		}

		name := fmt.Sprintf("%s%d-%03d", strictIngressNamePrefix, request.Generation, index)
		if _, collision := coreConfig.Listeners[name]; collision {
			return nil, nil, errors.New("strict ingress listener name is reserved")
		}
		inbound, err := listener.ParseListener(map[string]any{
			"name":   name,
			"type":   "socks",
			"listen": "127.0.0.1",
			"port":   "0",
			"udp":    false,
			"proxy":  entry.TargetGroup,
			"users": []map[string]string{{
				"username": entry.Username,
				"password": entry.Password,
			}},
		})
		if err != nil {
			return nil, nil, errors.New("strict ingress listener configuration is invalid")
		}
		listeners[name] = inbound
		ordered = append(ordered, strictIngressBuildEntry{
			TargetGroup:  entry.TargetGroup,
			ListenerName: name,
		})
	}
	return listeners, ordered, nil
}

func startStrictUDPHealthService(request *StrictIngressRequest) (*strictUDPHealthService, error) {
	if err := validateStrictIngressRequestShape(request); err != nil {
		return nil, err
	}
	if len(request.Entries) == 0 {
		return nil, errors.New("strict UDP health service requires an active ingress")
	}
	keys := make(map[[strictUDPHealthKeyIDBytes]byte][sha256.Size]byte, len(request.Entries))
	for _, entry := range request.Entries {
		username, err := hex.DecodeString(entry.Username)
		if err != nil || len(username) != sha256.Size {
			return nil, errors.New("strict UDP health username is invalid")
		}
		password, err := hex.DecodeString(entry.Password)
		if err != nil || len(password) != sha256.Size {
			return nil, errors.New("strict UDP health password is invalid")
		}
		var keyID [strictUDPHealthKeyIDBytes]byte
		copy(keyID[:], username[:strictUDPHealthKeyIDBytes])
		var key [sha256.Size]byte
		copy(key[:], password)
		if _, duplicate := keys[keyID]; duplicate {
			return nil, errors.New("strict UDP health key identifier is duplicated")
		}
		keys[keyID] = key
	}
	connection, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		return nil, errors.New("strict UDP health endpoint failed to bind")
	}
	if err := connection.SetReadBuffer(64 * 1024); err != nil {
		_ = connection.Close()
		return nil, errors.New("strict UDP health receive buffer setup failed")
	}
	endpoint, err := netip.ParseAddrPort(connection.LocalAddr().String())
	if err != nil || endpoint.Addr() != netip.MustParseAddr("127.0.0.1") || endpoint.Port() == 0 {
		_ = connection.Close()
		return nil, errors.New("strict UDP health endpoint is not exact IPv4 loopback")
	}
	service := &strictUDPHealthService{
		connection: connection,
		endpoint:   endpoint.String(),
		generation: request.Generation,
		keys:       keys,
		done:       make(chan struct{}),
	}
	go service.serve()
	return service, nil
}

func (service *strictUDPHealthService) serve() {
	defer close(service.done)
	// One extra byte makes oversized datagrams observable instead of accepting
	// a valid authenticated prefix after UDP truncation.
	var packet [strictUDPHealthFrameBytes + 1]byte
	for {
		count, source, err := service.connection.ReadFromUDP(packet[:])
		if err != nil {
			return
		}
		if count != strictUDPHealthFrameBytes || source == nil || !source.IP.Equal(net.IPv4(127, 0, 0, 1)) {
			continue
		}
		frame := packet[:strictUDPHealthFrameBytes]
		if !bytes.Equal(frame[strictUDPHealthMagicOffset:strictUDPHealthVersionOffset], strictUDPHealthMagic) ||
			frame[strictUDPHealthVersionOffset] != strictUDPHealthVersion ||
			frame[strictUDPHealthKindOffset] != strictUDPHealthPing ||
			frame[strictUDPHealthReservedOffset] != 0 || frame[strictUDPHealthReservedOffset+1] != 0 ||
			binary.BigEndian.Uint64(frame[strictUDPHealthGenerationOffset:strictUDPHealthKeyIDOffset]) != service.generation {
			continue
		}
		var keyID [strictUDPHealthKeyIDBytes]byte
		copy(keyID[:], frame[strictUDPHealthKeyIDOffset:strictUDPHealthNonceOffset])
		key, exists := service.keys[keyID]
		if !exists {
			continue
		}
		mac := hmac.New(sha256.New, key[:])
		_, _ = mac.Write(frame[:strictUDPHealthTagOffset])
		if !hmac.Equal(frame[strictUDPHealthTagOffset:], mac.Sum(nil)) {
			continue
		}
		frame[strictUDPHealthKindOffset] = strictUDPHealthPong
		mac = hmac.New(sha256.New, key[:])
		_, _ = mac.Write(frame[:strictUDPHealthTagOffset])
		copy(frame[strictUDPHealthTagOffset:], mac.Sum(nil))
		_, _ = service.connection.WriteToUDP(frame[:], source)
	}
}

func (service *strictUDPHealthService) close() {
	if service == nil {
		return
	}
	service.closeOnce.Do(func() {
		_ = service.connection.Close()
		<-service.done
	})
}

func handleConfigureStrictIngress(data string) (StrictIngressResult, error) {
	if runtime.GOOS != "windows" || !agentCoreAuthenticated.Load() {
		return StrictIngressResult{}, errors.New("strict ingress requires an authenticated Windows Agent channel")
	}
	request, err := parseStrictIngressRequest(data)
	if err != nil {
		return StrictIngressResult{}, err
	}
	if err := validateStrictIngressRequestShape(request); err != nil {
		return StrictIngressResult{}, err
	}
	canonical := canonicalStrictIngressRequest(request)
	request = &canonical

	runLock.Lock()
	defer runLock.Unlock()
	if len(request.Entries) == 0 {
		removeStrictIngressListenersLocked()
		return StrictIngressResult{
			Protocol:   strictIngressProtocol,
			Generation: request.Generation,
			Entries:    []StrictIngressResultEntry{},
		}, nil
	}
	if currentConfig == nil {
		return StrictIngressResult{}, errors.New("Core configuration is unavailable")
	}
	if !isRunning {
		return StrictIngressResult{}, errors.New("Core listeners are stopped")
	}
	if activeStrictIngress != nil && reflect.DeepEqual(activeStrictIngress.request, *request) {
		return activeStrictIngress.result, nil
	}
	if activeStrictIngress != nil && request.Generation <= activeStrictIngress.request.Generation {
		return StrictIngressResult{}, errors.New("strict ingress generation is stale")
	}

	strictListeners, ordered, err := buildStrictIngressListeners(request, currentConfig)
	if err != nil {
		return StrictIngressResult{}, err
	}
	udpHealth, err := startStrictUDPHealthService(request)
	if err != nil {
		return StrictIngressResult{}, err
	}
	merged := normalInboundListenersLocked()
	for name, inbound := range strictListeners {
		merged[name] = inbound
	}
	listener.PatchInboundListeners(merged, tunnel.Tunnel, true)

	result := StrictIngressResult{
		Protocol:    strictIngressProtocol,
		Generation:  request.Generation,
		UDPEndpoint: udpHealth.endpoint,
		Entries:     make([]StrictIngressResultEntry, 0, len(ordered)),
	}
	for _, entry := range ordered {
		endpoint := strictListeners[entry.ListenerName].Address()
		address, parseErr := netip.ParseAddrPort(endpoint)
		if parseErr != nil || address.Addr() != netip.MustParseAddr("127.0.0.1") || address.Port() == 0 {
			udpHealth.close()
			removeStrictIngressListenersLocked()
			return StrictIngressResult{}, errors.New("strict ingress listener failed to bind")
		}
		result.Entries = append(result.Entries, StrictIngressResultEntry{
			TargetGroup: entry.TargetGroup,
			Endpoint:    endpoint,
		})
	}
	previous := activeStrictIngress
	activeStrictIngress = &strictIngressSession{
		request:   *request,
		result:    result,
		listeners: strictListeners,
		udpHealth: udpHealth,
	}
	if previous != nil {
		previous.udpHealth.close()
	}
	return result, nil
}

func inboundListenersWithStrictLocked() map[string]C.InboundListener {
	merged := normalInboundListenersLocked()
	if activeStrictIngress == nil {
		return merged
	}
	for name, inbound := range activeStrictIngress.listeners {
		merged[name] = inbound
	}
	return merged
}

func normalInboundListenersLocked() map[string]C.InboundListener {
	listeners := make(map[string]C.InboundListener)
	if currentConfig == nil {
		return listeners
	}
	for name, inbound := range currentConfig.Listeners {
		listeners[name] = inbound
	}
	return listeners
}

func removeStrictIngressListenersLocked() {
	previous := activeStrictIngress
	activeStrictIngress = nil
	if isRunning {
		listener.PatchInboundListeners(normalInboundListenersLocked(), tunnel.Tunnel, true)
	}
	if previous != nil {
		previous.udpHealth.close()
	}
}

func clearStrictIngressForConfigChangeLocked() {
	previous := activeStrictIngress
	activeStrictIngress = nil
	if previous != nil {
		previous.udpHealth.close()
	}
}

func validStrictTargetGroup(value string) bool {
	return value != "" &&
		len(value) <= 256 &&
		value == string(bytes.TrimSpace([]byte(value))) &&
		!bytes.ContainsAny([]byte(value), "\x00\r\n")
}

func validStrictCredential(value string) bool {
	if len(value) != 64 {
		return false
	}
	for _, character := range []byte(value) {
		if !((character >= '0' && character <= '9') ||
			(character >= 'a' && character <= 'f') ||
			(character >= 'A' && character <= 'F')) {
			return false
		}
	}
	return true
}
