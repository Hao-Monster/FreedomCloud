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
	"hash"
	"io"
	"net"
	"net/netip"
	"reflect"
	"runtime"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/pool"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
)

const (
	strictIngressProtocol            uint32 = 2
	maxStrictIngressEntries                 = 128
	maxStrictIngressRequestBytes            = 128 * 1024
	strictIngressNamePrefix                 = "flclashx-strict-"
	strictUDPHealthFrameBytes               = 80
	strictUDPHealthKeyIDBytes               = 16
	strictUDPHealthMagicOffset              = 0
	strictUDPHealthVersionOffset            = 4
	strictUDPHealthKindOffset               = 5
	strictUDPHealthReservedOffset           = 6
	strictUDPHealthGenerationOffset         = 8
	strictUDPHealthKeyIDOffset              = 16
	strictUDPHealthNonceOffset              = 32
	strictUDPHealthTagOffset                = 48
	strictUDPHealthVersion           byte   = 1
	strictUDPHealthPing              byte   = 1
	strictUDPHealthPong              byte   = 2
	strictUDPDataHeaderBytes                = 80
	strictUDPDataMaxPayloadBytes            = 16 * 1024
	strictUDPDataMaxFrameBytes              = strictUDPDataHeaderBytes + strictUDPDataMaxPayloadBytes + sha256.Size
	strictUDPDataMaxAssociations            = 1024
	strictUDPDataMaxInFlight                = 256
	strictUDPReceiveBufferBytes             = 256 * 1024
	strictUDPDataVersionOffset              = 4
	strictUDPDataKindOffset                 = 5
	strictUDPDataFlagsOffset                = 6
	strictUDPDataGenerationOffset           = 8
	strictUDPDataKeyIDOffset                = 16
	strictUDPDataAssociationOffset          = 32
	strictUDPDataSequenceOffset             = 48
	strictUDPDataAddressFamilyOffset        = 56
	strictUDPDataPortOffset                 = 58
	strictUDPDataAddressOffset              = 60
	strictUDPDataPayloadLengthOffset        = 76
	strictUDPDataVersion             byte   = 1
	strictUDPDataOutbound            byte   = 1
	strictUDPDataInbound             byte   = 2
	strictUDPDataAddressIPv4         byte   = 4
	strictUDPDataAddressIPv6         byte   = 6
)

const (
	strictUDPDataAssociationIdle = 90 * time.Second
	strictUDPDataSweepInterval   = time.Second
)

var (
	strictUDPHealthMagic = []byte{'F', 'C', 'X', 'U'}
	strictUDPDataMagic   = []byte{'F', 'C', 'X', 'D'}
)

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
	request    StrictIngressRequest
	result     StrictIngressResult
	listeners  map[string]C.InboundListener
	udpIngress *strictUDPIngressService
}

type strictUDPIngressService struct {
	connection  *net.UDPConn
	endpoint    string
	local       netip.AddrPort
	generation  uint64
	credentials map[[strictUDPHealthKeyIDBytes]byte]*strictUDPIngressCredential
	tunnel      C.Tunnel
	done        chan struct{}
	packetSlots chan struct{}
	closeOnce   sync.Once
	closed      atomic.Bool
}

type strictUDPIngressCredential struct {
	targetGroup string
	key         [sha256.Size]byte
	macPool     sync.Pool
}

func newStrictUDPIngressCredential(targetGroup string, key [sha256.Size]byte) *strictUDPIngressCredential {
	credential := &strictUDPIngressCredential{targetGroup: targetGroup, key: key}
	credential.macPool.New = func() any {
		return hmac.New(sha256.New, credential.key[:])
	}
	return credential
}

func (credential *strictUDPIngressCredential) authenticate(message, tag []byte) bool {
	mac := credential.macPool.Get().(hash.Hash)
	mac.Reset()
	_, _ = mac.Write(message)
	var expected [sha256.Size]byte
	digest := mac.Sum(expected[:0])
	valid := hmac.Equal(tag, digest)
	mac.Reset()
	credential.macPool.Put(mac)
	return valid
}

func (credential *strictUDPIngressCredential) sign(message, tag []byte) {
	mac := credential.macPool.Get().(hash.Hash)
	mac.Reset()
	_, _ = mac.Write(message)
	_ = mac.Sum(tag[:0])
	mac.Reset()
	credential.macPool.Put(mac)
}

type strictUDPDataAssociation struct {
	id           [16]byte
	keyID        [strictUDPHealthKeyIDBytes]byte
	credential   *strictUDPIngressCredential
	source       net.UDPAddr
	address      strictUDPAssociationAddress
	lastSeen     atomic.Int64
	nextResponse atomic.Uint64
	replay       strictUDPReplayWindow
	active       atomic.Bool
}

type strictUDPReplayWindow struct {
	highest uint64
	bitmap  uint64
}

type strictUDPAssociationAddress struct {
	value string
}

func (address strictUDPAssociationAddress) Network() string {
	return "flclash-strict-udp"
}

func (address strictUDPAssociationAddress) String() string {
	return address.value
}

type strictUDPDataPacket struct {
	service     *strictUDPIngressService
	association *strictUDPDataAssociation
	payload     []byte
	dropOnce    sync.Once
}

var (
	activeStrictIngress    *strictIngressSession
	agentCoreAuthenticated atomic.Bool
	strictUDPIPv4Padding   [12]byte
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

func startStrictUDPIngressService(request *StrictIngressRequest, strictTunnel C.Tunnel) (*strictUDPIngressService, error) {
	if err := validateStrictIngressRequestShape(request); err != nil {
		return nil, err
	}
	if len(request.Entries) == 0 {
		return nil, errors.New("strict UDP ingress service requires an active ingress")
	}
	if strictTunnel == nil {
		return nil, errors.New("strict UDP ingress service requires the Core tunnel")
	}
	credentials := make(map[[strictUDPHealthKeyIDBytes]byte]*strictUDPIngressCredential, len(request.Entries))
	for _, entry := range request.Entries {
		username, err := hex.DecodeString(entry.Username)
		if err != nil || len(username) != sha256.Size {
			return nil, errors.New("strict UDP ingress username is invalid")
		}
		password, err := hex.DecodeString(entry.Password)
		if err != nil || len(password) != sha256.Size {
			return nil, errors.New("strict UDP ingress password is invalid")
		}
		var keyID [strictUDPHealthKeyIDBytes]byte
		copy(keyID[:], username[:strictUDPHealthKeyIDBytes])
		var key [sha256.Size]byte
		copy(key[:], password)
		if _, duplicate := credentials[keyID]; duplicate {
			return nil, errors.New("strict UDP health key identifier is duplicated")
		}
		credentials[keyID] = newStrictUDPIngressCredential(entry.TargetGroup, key)
	}
	connection, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		return nil, errors.New("strict UDP health endpoint failed to bind")
	}
	if err := connection.SetReadBuffer(strictUDPReceiveBufferBytes); err != nil {
		_ = connection.Close()
		return nil, errors.New("strict UDP health receive buffer setup failed")
	}
	endpoint, err := netip.ParseAddrPort(connection.LocalAddr().String())
	if err != nil || endpoint.Addr() != netip.MustParseAddr("127.0.0.1") || endpoint.Port() == 0 {
		_ = connection.Close()
		return nil, errors.New("strict UDP health endpoint is not exact IPv4 loopback")
	}
	service := &strictUDPIngressService{
		connection:  connection,
		endpoint:    endpoint.String(),
		local:       endpoint,
		generation:  request.Generation,
		credentials: credentials,
		tunnel:      strictTunnel,
		done:        make(chan struct{}),
		packetSlots: make(chan struct{}, strictUDPDataMaxInFlight),
	}
	go service.serve()
	return service, nil
}

func (service *strictUDPIngressService) serve() {
	associations := make(map[[16]byte]*strictUDPDataAssociation)
	defer func() {
		for _, association := range associations {
			association.active.Store(false)
		}
		close(service.done)
	}()
	var packet [strictUDPDataMaxFrameBytes + 1]byte
	lastSweep := time.Now()
	for {
		count, source, err := service.connection.ReadFromUDP(packet[:])
		if err != nil {
			// Windows reports WSAEMSGSIZE with the truncated byte count after
			// consuming an oversized datagram. Discard it without letting an
			// untrusted local sender terminate the generation-scoped service.
			if count > 0 {
				continue
			}
			return
		}
		if source == nil || !source.IP.Equal(net.IPv4(127, 0, 0, 1)) {
			continue
		}
		frame := packet[:count]
		switch {
		case count == strictUDPHealthFrameBytes && bytes.Equal(frame[:len(strictUDPHealthMagic)], strictUDPHealthMagic):
			service.handleHealthFrame(frame, source)
		case count >= strictUDPDataHeaderBytes+sha256.Size && count <= strictUDPDataMaxFrameBytes &&
			bytes.Equal(frame[:len(strictUDPDataMagic)], strictUDPDataMagic):
			now := time.Now()
			if now.Sub(lastSweep) >= strictUDPDataSweepInterval {
				sweepStrictUDPDataAssociations(associations, now)
				lastSweep = now
			}
			service.handleDataFrame(frame, source, associations, now)
		}
	}
}

func (service *strictUDPIngressService) handleHealthFrame(frame []byte, source *net.UDPAddr) {
	if !bytes.Equal(frame[strictUDPHealthMagicOffset:strictUDPHealthVersionOffset], strictUDPHealthMagic) ||
		frame[strictUDPHealthVersionOffset] != strictUDPHealthVersion ||
		frame[strictUDPHealthKindOffset] != strictUDPHealthPing ||
		frame[strictUDPHealthReservedOffset] != 0 || frame[strictUDPHealthReservedOffset+1] != 0 ||
		binary.BigEndian.Uint64(frame[strictUDPHealthGenerationOffset:strictUDPHealthKeyIDOffset]) != service.generation {
		return
	}
	var keyID [strictUDPHealthKeyIDBytes]byte
	copy(keyID[:], frame[strictUDPHealthKeyIDOffset:strictUDPHealthNonceOffset])
	credential, exists := service.credentials[keyID]
	if !exists {
		return
	}
	if !credential.authenticate(frame[:strictUDPHealthTagOffset], frame[strictUDPHealthTagOffset:]) {
		return
	}
	frame[strictUDPHealthKindOffset] = strictUDPHealthPong
	credential.sign(frame[:strictUDPHealthTagOffset], frame[strictUDPHealthTagOffset:])
	_, _ = service.connection.WriteToUDP(frame[:], source)
}

func (service *strictUDPIngressService) handleDataFrame(
	frame []byte,
	source *net.UDPAddr,
	associations map[[16]byte]*strictUDPDataAssociation,
	now time.Time,
) {
	if frame[strictUDPDataVersionOffset] != strictUDPDataVersion ||
		frame[strictUDPDataKindOffset] != strictUDPDataOutbound ||
		frame[strictUDPDataFlagsOffset] != 0 || frame[strictUDPDataFlagsOffset+1] != 0 ||
		binary.BigEndian.Uint64(frame[strictUDPDataGenerationOffset:strictUDPDataKeyIDOffset]) != service.generation ||
		frame[57] != 0 || frame[78] != 0 || frame[79] != 0 {
		return
	}
	payloadLength := int(binary.BigEndian.Uint16(frame[strictUDPDataPayloadLengthOffset:strictUDPDataHeaderBytes]))
	if payloadLength == 0 || payloadLength > strictUDPDataMaxPayloadBytes ||
		len(frame) != strictUDPDataHeaderBytes+payloadLength+sha256.Size {
		return
	}
	var keyID [strictUDPHealthKeyIDBytes]byte
	copy(keyID[:], frame[strictUDPDataKeyIDOffset:strictUDPDataAssociationOffset])
	credential, exists := service.credentials[keyID]
	if !exists {
		return
	}
	tagOffset := len(frame) - sha256.Size
	if !credential.authenticate(frame[:tagOffset], frame[tagOffset:]) {
		return
	}
	var associationID [16]byte
	copy(associationID[:], frame[strictUDPDataAssociationOffset:strictUDPDataSequenceOffset])
	if associationID == [16]byte{} {
		return
	}
	sequence := binary.BigEndian.Uint64(frame[strictUDPDataSequenceOffset:strictUDPDataAddressFamilyOffset])
	if sequence == 0 {
		return
	}
	destination, ok := parseStrictUDPDataDestination(frame)
	if !ok {
		return
	}
	association, exists := associations[associationID]
	if !exists {
		if len(associations) >= strictUDPDataMaxAssociations {
			sweepStrictUDPDataAssociations(associations, now)
			if len(associations) >= strictUDPDataMaxAssociations {
				return
			}
		}
		association = &strictUDPDataAssociation{
			id:         associationID,
			keyID:      keyID,
			credential: credential,
			source: net.UDPAddr{
				IP:   append(net.IP(nil), source.IP...),
				Port: source.Port,
				Zone: source.Zone,
			},
			address: strictUDPAssociationAddress{
				value: fmt.Sprintf("flclash-strict-udp:%d:%x:%x", service.generation, keyID, associationID),
			},
		}
		association.active.Store(true)
		associations[associationID] = association
	} else if association.keyID != keyID || !sameStrictUDPSource(&association.source, source) {
		return
	}
	if !association.replay.accept(sequence) {
		return
	}
	association.lastSeen.Store(now.UnixNano())
	select {
	case service.packetSlots <- struct{}{}:
	default:
		return
	}
	payload := pool.Get(payloadLength)
	copy(payload, frame[strictUDPDataHeaderBytes:tagOffset])
	packet := &strictUDPDataPacket{
		service:     service,
		association: association,
		payload:     payload,
	}
	sourceAddress := source.AddrPort().Addr().Unmap()
	metadata := &C.Metadata{
		NetWork:      C.UDP,
		Type:         C.INNER,
		SrcIP:        sourceAddress,
		SrcPort:      uint16(source.Port),
		DstIP:        destination.Addr().Unmap(),
		DstPort:      destination.Port(),
		InIP:         service.local.Addr(),
		InPort:       service.local.Port(),
		InName:       "flclashx-strict-udp",
		SpecialProxy: association.credential.targetGroup,
		RawSrcAddr:   source,
		RawDstAddr:   net.UDPAddrFromAddrPort(destination),
	}
	service.tunnel.HandleUDPPacket(packet, metadata)
}

func parseStrictUDPDataDestination(frame []byte) (netip.AddrPort, bool) {
	port := binary.BigEndian.Uint16(frame[strictUDPDataPortOffset:strictUDPDataAddressOffset])
	if port == 0 {
		return netip.AddrPort{}, false
	}
	var address netip.Addr
	switch frame[strictUDPDataAddressFamilyOffset] {
	case strictUDPDataAddressIPv4:
		if !bytes.Equal(frame[strictUDPDataAddressOffset+4:strictUDPDataPayloadLengthOffset], strictUDPIPv4Padding[:]) {
			return netip.AddrPort{}, false
		}
		var raw [4]byte
		copy(raw[:], frame[strictUDPDataAddressOffset:strictUDPDataAddressOffset+4])
		address = netip.AddrFrom4(raw)
	case strictUDPDataAddressIPv6:
		var raw [16]byte
		copy(raw[:], frame[strictUDPDataAddressOffset:strictUDPDataPayloadLengthOffset])
		address = netip.AddrFrom16(raw)
		if address.Is4In6() {
			return netip.AddrPort{}, false
		}
	default:
		return netip.AddrPort{}, false
	}
	if !safeStrictUDPAddr(address) {
		return netip.AddrPort{}, false
	}
	return netip.AddrPortFrom(address, port), true
}

func sameStrictUDPSource(left, right *net.UDPAddr) bool {
	return left != nil && right != nil && left.Port == right.Port && left.Zone == right.Zone && left.IP.Equal(right.IP)
}

func (window *strictUDPReplayWindow) accept(sequence uint64) bool {
	if sequence == 0 {
		return false
	}
	if window.highest == 0 {
		window.highest = sequence
		window.bitmap = 1
		return true
	}
	if sequence > window.highest {
		shift := sequence - window.highest
		if shift >= 64 {
			window.bitmap = 1
		} else {
			window.bitmap = (window.bitmap << shift) | 1
		}
		window.highest = sequence
		return true
	}
	offset := window.highest - sequence
	if offset >= 64 {
		return false
	}
	mask := uint64(1) << offset
	if window.bitmap&mask != 0 {
		return false
	}
	window.bitmap |= mask
	return true
}

func sweepStrictUDPDataAssociations(associations map[[16]byte]*strictUDPDataAssociation, now time.Time) {
	cutoff := now.Add(-strictUDPDataAssociationIdle).UnixNano()
	for id, association := range associations {
		if association.lastSeen.Load() < cutoff {
			association.active.Store(false)
			delete(associations, id)
		}
	}
}

func (packet *strictUDPDataPacket) Data() []byte {
	return packet.payload
}

func (packet *strictUDPDataPacket) WriteBack(payload []byte, address net.Addr) (int, error) {
	if len(payload) == 0 || len(payload) > strictUDPDataMaxPayloadBytes {
		return 0, errors.New("strict UDP response payload size is invalid")
	}
	if packet.service.closed.Load() || !packet.association.active.Load() {
		return 0, errors.New("strict UDP association is no longer active")
	}
	destination, ok := strictUDPAddrPort(address)
	if !ok {
		return 0, errors.New("strict UDP response source is invalid")
	}
	sequence := packet.association.nextResponse.Add(1)
	if sequence == 0 {
		packet.association.active.Store(false)
		return 0, errors.New("strict UDP response sequence overflow")
	}
	frame := pool.Get(strictUDPDataHeaderBytes + len(payload) + sha256.Size)
	defer func() { _ = pool.Put(frame) }()
	for index := range frame[:strictUDPDataHeaderBytes] {
		frame[index] = 0
	}
	copy(frame, strictUDPDataMagic)
	frame[strictUDPDataVersionOffset] = strictUDPDataVersion
	frame[strictUDPDataKindOffset] = strictUDPDataInbound
	binary.BigEndian.PutUint64(frame[strictUDPDataGenerationOffset:], packet.service.generation)
	copy(frame[strictUDPDataKeyIDOffset:], packet.association.keyID[:])
	copy(frame[strictUDPDataAssociationOffset:], packet.association.id[:])
	binary.BigEndian.PutUint64(frame[strictUDPDataSequenceOffset:], sequence)
	writeStrictUDPDataAddress(frame, destination)
	binary.BigEndian.PutUint16(frame[strictUDPDataPayloadLengthOffset:], uint16(len(payload)))
	copy(frame[strictUDPDataHeaderBytes:], payload)
	tagOffset := len(frame) - sha256.Size
	packet.association.credential.sign(frame[:tagOffset], frame[tagOffset:])
	written, err := packet.service.connection.WriteToUDP(frame, &packet.association.source)
	if err != nil {
		return 0, err
	}
	if written != len(frame) {
		return 0, errors.New("strict UDP response frame was truncated")
	}
	packet.association.lastSeen.Store(time.Now().UnixNano())
	return len(payload), nil
}

func strictUDPAddrPort(address net.Addr) (netip.AddrPort, bool) {
	if address == nil {
		return netip.AddrPort{}, false
	}
	if value, ok := address.(interface{ AddrPort() netip.AddrPort }); ok {
		endpoint := value.AddrPort()
		if endpoint.IsValid() {
			endpoint = netip.AddrPortFrom(endpoint.Addr().Unmap(), endpoint.Port())
		}
		return endpoint, safeStrictUDPAddrPort(endpoint)
	}
	endpoint, err := netip.ParseAddrPort(address.String())
	if err != nil {
		return netip.AddrPort{}, false
	}
	endpoint = netip.AddrPortFrom(endpoint.Addr().Unmap(), endpoint.Port())
	return endpoint, safeStrictUDPAddrPort(endpoint)
}

func safeStrictUDPAddrPort(endpoint netip.AddrPort) bool {
	return endpoint.IsValid() && endpoint.Port() != 0 && safeStrictUDPAddr(endpoint.Addr())
}

func safeStrictUDPAddr(address netip.Addr) bool {
	return address.IsValid() && address.Zone() == "" && address.IsGlobalUnicast()
}

func writeStrictUDPDataAddress(frame []byte, endpoint netip.AddrPort) {
	address := endpoint.Addr().Unmap()
	binary.BigEndian.PutUint16(frame[strictUDPDataPortOffset:], endpoint.Port())
	if address.Is4() {
		frame[strictUDPDataAddressFamilyOffset] = strictUDPDataAddressIPv4
		raw := address.As4()
		copy(frame[strictUDPDataAddressOffset:], raw[:])
		return
	}
	frame[strictUDPDataAddressFamilyOffset] = strictUDPDataAddressIPv6
	raw := address.As16()
	copy(frame[strictUDPDataAddressOffset:], raw[:])
}

func (packet *strictUDPDataPacket) Drop() {
	packet.dropOnce.Do(func() {
		_ = pool.Put(packet.payload)
		packet.payload = nil
		<-packet.service.packetSlots
	})
}

func (packet *strictUDPDataPacket) LocalAddr() net.Addr {
	return packet.association.address
}

func (service *strictUDPIngressService) close() {
	if service == nil {
		return
	}
	service.closeOnce.Do(func() {
		service.closed.Store(true)
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
	udpIngress, err := startStrictUDPIngressService(request, tunnel.Tunnel)
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
		UDPEndpoint: udpIngress.endpoint,
		Entries:     make([]StrictIngressResultEntry, 0, len(ordered)),
	}
	for _, entry := range ordered {
		endpoint := strictListeners[entry.ListenerName].Address()
		address, parseErr := netip.ParseAddrPort(endpoint)
		if parseErr != nil || address.Addr() != netip.MustParseAddr("127.0.0.1") || address.Port() == 0 {
			udpIngress.close()
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
		request:    *request,
		result:     result,
		listeners:  strictListeners,
		udpIngress: udpIngress,
	}
	if previous != nil {
		previous.udpIngress.close()
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
		previous.udpIngress.close()
	}
}

func clearStrictIngressForConfigChangeLocked() {
	previous := activeStrictIngress
	activeStrictIngress = nil
	if previous != nil {
		previous.udpIngress.close()
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
