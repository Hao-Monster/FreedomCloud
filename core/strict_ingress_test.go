package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/netip"
	"reflect"
	"runtime"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
)

func strictIngressUDPHealthPing(t *testing.T, generation uint64, username, password string, nonce byte) []byte {
	t.Helper()
	usernameBytes, err := hex.DecodeString(username)
	if err != nil {
		t.Fatalf("decode strict UDP username: %v", err)
	}
	passwordBytes, err := hex.DecodeString(password)
	if err != nil {
		t.Fatalf("decode strict UDP password: %v", err)
	}
	frame := make([]byte, strictUDPHealthFrameBytes)
	copy(frame[strictUDPHealthMagicOffset:], strictUDPHealthMagic)
	frame[strictUDPHealthVersionOffset] = strictUDPHealthVersion
	frame[strictUDPHealthKindOffset] = strictUDPHealthPing
	binary.BigEndian.PutUint64(frame[strictUDPHealthGenerationOffset:], generation)
	copy(frame[strictUDPHealthKeyIDOffset:], usernameBytes[:strictUDPHealthKeyIDBytes])
	for index := strictUDPHealthNonceOffset; index < strictUDPHealthTagOffset; index++ {
		frame[index] = nonce
	}
	mac := hmac.New(sha256.New, passwordBytes)
	_, _ = mac.Write(frame[:strictUDPHealthTagOffset])
	copy(frame[strictUDPHealthTagOffset:], mac.Sum(nil))
	return frame
}

type strictIngressTestHelper interface {
	Helper()
	Fatalf(string, ...any)
}

func strictIngressUDPDataFrame(
	t strictIngressTestHelper,
	generation uint64,
	username, password string,
	association [16]byte,
	sequence uint64,
	destination netip.AddrPort,
	payload []byte,
) []byte {
	t.Helper()
	usernameBytes, err := hex.DecodeString(username)
	if err != nil {
		t.Fatalf("decode strict UDP data username: %v", err)
	}
	passwordBytes, err := hex.DecodeString(password)
	if err != nil {
		t.Fatalf("decode strict UDP data password: %v", err)
	}
	frame := make([]byte, strictUDPDataHeaderBytes+len(payload)+sha256.Size)
	copy(frame, strictUDPDataMagic)
	frame[strictUDPDataVersionOffset] = strictUDPDataVersion
	frame[strictUDPDataKindOffset] = strictUDPDataOutbound
	binary.BigEndian.PutUint64(frame[strictUDPDataGenerationOffset:], generation)
	copy(frame[strictUDPDataKeyIDOffset:], usernameBytes[:strictUDPHealthKeyIDBytes])
	copy(frame[strictUDPDataAssociationOffset:], association[:])
	binary.BigEndian.PutUint64(frame[strictUDPDataSequenceOffset:], sequence)
	if destination.Addr().Is4() {
		frame[strictUDPDataAddressFamilyOffset] = strictUDPDataAddressIPv4
		address := destination.Addr().As4()
		copy(frame[strictUDPDataAddressOffset:], address[:])
	} else {
		frame[strictUDPDataAddressFamilyOffset] = strictUDPDataAddressIPv6
		address := destination.Addr().As16()
		copy(frame[strictUDPDataAddressOffset:], address[:])
	}
	binary.BigEndian.PutUint16(frame[strictUDPDataPortOffset:], destination.Port())
	binary.BigEndian.PutUint16(frame[strictUDPDataPayloadLengthOffset:], uint16(len(payload)))
	copy(frame[strictUDPDataHeaderBytes:], payload)
	mac := hmac.New(sha256.New, passwordBytes)
	_, _ = mac.Write(frame[:len(frame)-sha256.Size])
	copy(frame[len(frame)-sha256.Size:], mac.Sum(nil))
	return frame
}

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

func TestStrictUDPHealthWireVectorMatchesBroker(t *testing.T) {
	frame := strictIngressUDPHealthPing(
		t,
		7,
		strings.Repeat("11", 32),
		strings.Repeat("33", 32),
		0x22,
	)
	if tag := hex.EncodeToString(frame[strictUDPHealthTagOffset:]); tag != "99b007f39a825086c1ee37b3e4a1f2b6d67c0395ba78186422a5aa19ca32b2c4" {
		t.Fatalf("strict UDP health wire HMAC changed: %s", tag)
	}
}

func TestStrictUDPDataWireVectorMatchesBroker(t *testing.T) {
	var association [16]byte
	for index := range association {
		association[index] = 0x44
	}
	frame := strictIngressUDPDataFrame(
		t,
		7,
		strictIngressCredential('1'),
		strictIngressCredential('3'),
		association,
		9,
		netip.MustParseAddrPort("8.8.8.8:443"),
		[]byte("strict-udp-vector"),
	)
	if tag := hex.EncodeToString(frame[len(frame)-sha256.Size:]); tag != "8715701d2e9a6cdaf7713968a7a55a1e91b0cea2d9cf447a2a8014f6f35079a9" {
		t.Fatalf("strict UDP data wire vector drifted: %s", tag)
	}
}

func TestStrictUDPCredentialMACIsConcurrentAndIsolated(t *testing.T) {
	var key [sha256.Size]byte
	for index := range key {
		key[index] = byte(index + 1)
	}
	credential := newStrictUDPIngressCredential("GLOBAL", key)
	const workers = 32
	const iterations = 128
	failures := make(chan string, 1)
	var wait sync.WaitGroup
	wait.Add(workers)
	for worker := 0; worker < workers; worker++ {
		go func(worker byte) {
			defer wait.Done()
			for iteration := 0; iteration < iterations; iteration++ {
				message := []byte{worker, byte(iteration), byte(iteration >> 8)}
				var tag [sha256.Size]byte
				credential.sign(message, tag[:])
				if !credential.authenticate(message, tag[:]) {
					select {
					case failures <- "valid concurrent MAC was rejected":
					default:
					}
					return
				}
				tag[0] ^= 0xff
				if credential.authenticate(message, tag[:]) {
					select {
					case failures <- "forged concurrent MAC was accepted":
					default:
					}
					return
				}
			}
		}(byte(worker))
	}
	wait.Wait()
	select {
	case failure := <-failures:
		t.Fatal(failure)
	default:
	}
}

type strictUDPFakeTunnel struct {
	packets chan strictUDPFakePacket
}

type strictUDPDroppingTunnel struct{}

type strictUDPFakePacket struct {
	packet   C.UDPPacket
	metadata *C.Metadata
}

func (tunnel *strictUDPFakeTunnel) HandleTCPConn(net.Conn, *C.Metadata) {}

func (tunnel *strictUDPFakeTunnel) HandleUDPPacket(packet C.UDPPacket, metadata *C.Metadata) {
	tunnel.packets <- strictUDPFakePacket{packet: packet, metadata: metadata}
}

func (tunnel *strictUDPFakeTunnel) NatTable() C.NatTable { return nil }

func (strictUDPDroppingTunnel) HandleTCPConn(net.Conn, *C.Metadata) {}

func (strictUDPDroppingTunnel) HandleUDPPacket(packet C.UDPPacket, _ *C.Metadata) {
	packet.Drop()
}

func (strictUDPDroppingTunnel) NatTable() C.NatTable { return nil }

func TestStrictUDPDataIngressAuthenticatesRoutesRepliesAndRejectsReplay(t *testing.T) {
	username := strictIngressCredential('1')
	password := strictIngressCredential('3')
	request := StrictIngressRequest{
		Protocol:   strictIngressProtocol,
		Generation: 23,
		Entries: []StrictIngressRequestEntry{{
			TargetGroup: "GLOBAL",
			Username:    username,
			Password:    password,
		}},
	}
	fakeTunnel := &strictUDPFakeTunnel{packets: make(chan strictUDPFakePacket, 1)}
	service, err := startStrictUDPIngressService(&request, fakeTunnel)
	if err != nil {
		t.Fatalf("start strict UDP data ingress: %v", err)
	}
	defer service.close()
	connection, err := net.DialTimeout("udp4", service.endpoint, time.Second)
	if err != nil {
		t.Fatalf("connect strict UDP data ingress: %v", err)
	}
	defer connection.Close()
	if err := connection.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatalf("set strict UDP data deadline: %v", err)
	}
	association := [16]byte{0x44, 0x55, 0x66}
	destination := netip.MustParseAddrPort("8.8.8.8:443")
	frame := strictIngressUDPDataFrame(
		t,
		request.Generation,
		username,
		password,
		association,
		1,
		destination,
		[]byte("request"),
	)
	forged := append([]byte(nil), frame...)
	forged[len(forged)-1] ^= 0xff
	if _, err := connection.Write(forged); err != nil {
		t.Fatalf("write forged strict UDP data frame: %v", err)
	}
	select {
	case <-fakeTunnel.packets:
		t.Fatal("strict UDP data ingress accepted a forged frame")
	case <-time.After(100 * time.Millisecond):
	}
	if _, err := connection.Write(frame); err != nil {
		t.Fatalf("write strict UDP data frame: %v", err)
	}

	var received strictUDPFakePacket
	select {
	case received = <-fakeTunnel.packets:
	case <-time.After(time.Second):
		t.Fatal("strict UDP data frame did not reach the Core tunnel")
	}
	if string(received.packet.Data()) != "request" ||
		received.metadata.NetWork != C.UDP ||
		received.metadata.SpecialProxy != "GLOBAL" ||
		received.metadata.DstIP != destination.Addr() ||
		received.metadata.DstPort != destination.Port() ||
		received.metadata.Type != C.INNER {
		t.Fatalf("strict UDP data routing metadata is invalid: %#v", received.metadata)
	}
	if _, err := received.packet.WriteBack([]byte("response"), net.UDPAddrFromAddrPort(destination)); err != nil {
		t.Fatalf("write strict UDP data response: %v", err)
	}
	reply := make([]byte, strictUDPDataMaxFrameBytes+1)
	count, err := connection.Read(reply)
	if err != nil {
		t.Fatalf("read strict UDP data response: %v", err)
	}
	reply = reply[:count]
	if err := validateStrictUDPDataTestReply(reply, request.Generation, password, association, destination, []byte("response")); err != nil {
		t.Fatal(err)
	}
	received.packet.Drop()
	received.packet.Drop()

	if _, err := connection.Write(frame); err != nil {
		t.Fatalf("write replayed strict UDP data frame: %v", err)
	}
	select {
	case <-fakeTunnel.packets:
		t.Fatal("strict UDP data ingress accepted a replayed sequence")
	case <-time.After(100 * time.Millisecond):
	}
}

func TestStrictUDPDataAssociationRejectsCrossCredentialCollision(t *testing.T) {
	request := StrictIngressRequest{
		Protocol:   strictIngressProtocol,
		Generation: 24,
		Entries: []StrictIngressRequestEntry{
			{TargetGroup: "GROUP-A", Username: strictIngressCredential('1'), Password: strictIngressCredential('3')},
			{TargetGroup: "GROUP-B", Username: strictIngressCredential('2'), Password: strictIngressCredential('4')},
		},
	}
	fakeTunnel := &strictUDPFakeTunnel{packets: make(chan strictUDPFakePacket, 2)}
	service, err := startStrictUDPIngressService(&request, fakeTunnel)
	if err != nil {
		t.Fatalf("start credential-isolated strict UDP ingress: %v", err)
	}
	defer service.close()
	connection, err := net.DialTimeout("udp4", service.endpoint, time.Second)
	if err != nil {
		t.Fatalf("connect credential-isolated strict UDP ingress: %v", err)
	}
	defer connection.Close()
	association := [16]byte{0xcc}
	for index, entry := range request.Entries {
		frame := strictIngressUDPDataFrame(
			t,
			request.Generation,
			entry.Username,
			entry.Password,
			association,
			1,
			netip.MustParseAddrPort("8.8.8.8:443"),
			[]byte{byte(index + 1)},
		)
		if _, err := connection.Write(frame); err != nil {
			t.Fatalf("write credential-isolated strict UDP frame: %v", err)
		}
	}
	select {
	case received := <-fakeTunnel.packets:
		if received.metadata.SpecialProxy != "GROUP-A" {
			t.Fatalf("strict UDP association collision changed its target group: %s", received.metadata.SpecialProxy)
		}
		received.packet.Drop()
	case <-time.After(time.Second):
		t.Fatal("first strict UDP association frame was rejected")
	}
	select {
	case received := <-fakeTunnel.packets:
		received.packet.Drop()
		t.Fatal("strict UDP association ID collision crossed credential boundaries")
	case <-time.After(100 * time.Millisecond):
	}
}

func validateStrictUDPDataTestReply(
	frame []byte,
	generation uint64,
	password string,
	association [16]byte,
	source netip.AddrPort,
	payload []byte,
) error {
	if len(frame) != strictUDPDataHeaderBytes+len(payload)+sha256.Size {
		return errors.New("strict UDP data reply size failed")
	}
	responseSource, sourceOK := parseStrictUDPDataDestination(frame)
	if !bytes.Equal(frame[:len(strictUDPDataMagic)], strictUDPDataMagic) ||
		frame[strictUDPDataVersionOffset] != strictUDPDataVersion ||
		frame[strictUDPDataKindOffset] != strictUDPDataInbound ||
		frame[strictUDPDataFlagsOffset] != 0 || frame[strictUDPDataFlagsOffset+1] != 0 ||
		binary.BigEndian.Uint64(frame[strictUDPDataGenerationOffset:]) != generation ||
		!bytes.Equal(frame[strictUDPDataAssociationOffset:strictUDPDataSequenceOffset], association[:]) ||
		binary.BigEndian.Uint64(frame[strictUDPDataSequenceOffset:]) == 0 ||
		!sourceOK || responseSource != source ||
		frame[57] != 0 || frame[78] != 0 || frame[79] != 0 ||
		!bytes.Equal(frame[strictUDPDataHeaderBytes:len(frame)-sha256.Size], payload) {
		return errors.New("strict UDP data reply correlation failed")
	}
	passwordBytes, err := hex.DecodeString(password)
	if err != nil {
		return err
	}
	mac := hmac.New(sha256.New, passwordBytes)
	_, _ = mac.Write(frame[:len(frame)-sha256.Size])
	if !hmac.Equal(frame[len(frame)-sha256.Size:], mac.Sum(nil)) {
		return errors.New("strict UDP data reply authentication failed")
	}
	return nil
}

func TestStrictUDPReplayWindowAcceptsBoundedReordering(t *testing.T) {
	var window strictUDPReplayWindow
	for _, sequence := range []uint64{100, 98, 99, 37, 200} {
		if !window.accept(sequence) {
			t.Fatalf("fresh sequence %d was rejected", sequence)
		}
	}
	for _, sequence := range []uint64{0, 100, 37, 136} {
		if window.accept(sequence) {
			t.Fatalf("replayed or stale sequence %d was accepted", sequence)
		}
	}
}

func TestStrictUDPDataAddressValidationIsCanonicalAndSafe(t *testing.T) {
	username := strictIngressCredential('1')
	password := strictIngressCredential('3')
	association := [16]byte{1}
	frame := strictIngressUDPDataFrame(
		t,
		1,
		username,
		password,
		association,
		1,
		netip.MustParseAddrPort("8.8.8.8:53"),
		[]byte{1},
	)
	if endpoint, ok := parseStrictUDPDataDestination(frame); !ok || endpoint != netip.MustParseAddrPort("8.8.8.8:53") {
		t.Fatalf("canonical IPv4 destination was rejected: %v, %t", endpoint, ok)
	}

	nonCanonical := append([]byte(nil), frame...)
	nonCanonical[strictUDPDataAddressOffset+4] = 1
	if _, ok := parseStrictUDPDataDestination(nonCanonical); ok {
		t.Fatal("non-zero IPv4 padding was accepted")
	}
	loopback := strictIngressUDPDataFrame(
		t,
		1,
		username,
		password,
		association,
		2,
		netip.MustParseAddrPort("127.0.0.1:53"),
		[]byte{1},
	)
	if _, ok := parseStrictUDPDataDestination(loopback); ok {
		t.Fatal("loopback destination was accepted")
	}
	mapped := append([]byte(nil), frame...)
	mapped[strictUDPDataAddressFamilyOffset] = strictUDPDataAddressIPv6
	rawMapped := netip.MustParseAddr("::ffff:8.8.8.8").As16()
	copy(mapped[strictUDPDataAddressOffset:strictUDPDataPayloadLengthOffset], rawMapped[:])
	if _, ok := parseStrictUDPDataDestination(mapped); ok {
		t.Fatal("IPv4-mapped IPv6 destination was accepted")
	}

	if _, ok := strictUDPAddrPort(net.UDPAddrFromAddrPort(netip.MustParseAddrPort("127.0.0.1:53"))); ok {
		t.Fatal("unsafe UDP response source was accepted")
	}
	endpoint, ok := strictUDPAddrPort(net.UDPAddrFromAddrPort(netip.MustParseAddrPort("[2001:4860:4860::8888]:53")))
	if !ok || endpoint != netip.MustParseAddrPort("[2001:4860:4860::8888]:53") {
		t.Fatalf("safe IPv6 UDP response source was rejected: %v, %t", endpoint, ok)
	}
}

func TestStrictUDPDataAssociationSweepExpiresBoundedState(t *testing.T) {
	now := time.Now()
	expired := &strictUDPDataAssociation{}
	expired.active.Store(true)
	expired.lastSeen.Store(now.Add(-strictUDPDataAssociationIdle - time.Second).UnixNano())
	fresh := &strictUDPDataAssociation{}
	fresh.active.Store(true)
	fresh.lastSeen.Store(now.UnixNano())
	expiredID := [16]byte{1}
	freshID := [16]byte{2}
	associations := map[[16]byte]*strictUDPDataAssociation{
		expiredID: expired,
		freshID:   fresh,
	}

	sweepStrictUDPDataAssociations(associations, now)

	if _, exists := associations[expiredID]; exists || expired.active.Load() {
		t.Fatal("expired strict UDP association was retained")
	}
	if _, exists := associations[freshID]; !exists || !fresh.active.Load() {
		t.Fatal("fresh strict UDP association was removed")
	}
}

func TestStrictUDPDataIngressBoundsInFlightPayloadMemory(t *testing.T) {
	username := strictIngressCredential('1')
	password := strictIngressCredential('3')
	request := StrictIngressRequest{
		Protocol:   strictIngressProtocol,
		Generation: 29,
		Entries: []StrictIngressRequestEntry{{
			TargetGroup: "GLOBAL",
			Username:    username,
			Password:    password,
		}},
	}
	fakeTunnel := &strictUDPFakeTunnel{packets: make(chan strictUDPFakePacket, strictUDPDataMaxInFlight+1)}
	service, err := startStrictUDPIngressService(&request, fakeTunnel)
	if err != nil {
		t.Fatalf("start bounded strict UDP data ingress: %v", err)
	}
	defer service.close()
	associations := make(map[[16]byte]*strictUDPDataAssociation)
	source := &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 54321}
	association := [16]byte{0xaa}
	for sequence := uint64(1); sequence <= strictUDPDataMaxInFlight+1; sequence++ {
		frame := strictIngressUDPDataFrame(
			t,
			request.Generation,
			username,
			password,
			association,
			sequence,
			netip.MustParseAddrPort("8.8.8.8:443"),
			[]byte{1},
		)
		service.handleDataFrame(frame, source, associations, time.Now())
	}
	if count := len(fakeTunnel.packets); count != strictUDPDataMaxInFlight {
		t.Fatalf("strict UDP in-flight bound was not enforced: got %d, want %d", count, strictUDPDataMaxInFlight)
	}
	for len(fakeTunnel.packets) > 0 {
		received := <-fakeTunnel.packets
		received.packet.Drop()
	}
	if slots := len(service.packetSlots); slots != 0 {
		t.Fatalf("strict UDP packet slots leaked after Drop: %d", slots)
	}
}

func TestStrictUDPDataIngressBoundsAssociationState(t *testing.T) {
	username := strictIngressCredential('1')
	password := strictIngressCredential('3')
	usernameBytes, err := hex.DecodeString(username)
	if err != nil {
		t.Fatal(err)
	}
	passwordBytes, err := hex.DecodeString(password)
	if err != nil {
		t.Fatal(err)
	}
	var keyID [strictUDPHealthKeyIDBytes]byte
	copy(keyID[:], usernameBytes)
	var key [sha256.Size]byte
	copy(key[:], passwordBytes)
	service := &strictUDPIngressService{
		local:       netip.MustParseAddrPort("127.0.0.1:54320"),
		generation:  30,
		credentials: map[[strictUDPHealthKeyIDBytes]byte]*strictUDPIngressCredential{keyID: newStrictUDPIngressCredential("GLOBAL", key)},
		tunnel:      strictUDPDroppingTunnel{},
		packetSlots: make(chan struct{}, strictUDPDataMaxInFlight),
	}
	associations := make(map[[16]byte]*strictUDPDataAssociation)
	source := &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 54321}
	now := time.Now()
	for index := 1; index <= strictUDPDataMaxAssociations+1; index++ {
		var association [16]byte
		binary.BigEndian.PutUint64(association[8:], uint64(index))
		frame := strictIngressUDPDataFrame(
			t,
			service.generation,
			username,
			password,
			association,
			1,
			netip.MustParseAddrPort("8.8.8.8:443"),
			[]byte{1},
		)
		service.handleDataFrame(frame, source, associations, now)
	}
	if count := len(associations); count != strictUDPDataMaxAssociations {
		t.Fatalf("strict UDP association bound was not enforced: got %d, want %d", count, strictUDPDataMaxAssociations)
	}
}

func TestStrictUDPAssociationKeyStringDoesNotAllocate(t *testing.T) {
	address := strictUDPAssociationAddress{value: "flclash-strict-udp:1:00112233445566778899aabbccddeeff"}
	allocations := testing.AllocsPerRun(1000, func() {
		if address.String() == "" {
			t.Fatal("strict UDP association key is empty")
		}
	})
	if allocations != 0 {
		t.Fatalf("strict UDP association key allocated on the packet hot path: %.2f", allocations)
	}
}

func BenchmarkStrictUDPDataIngressAuthenticatedDatagram(b *testing.B) {
	username := strictIngressCredential('1')
	password := strictIngressCredential('3')
	usernameBytes, err := hex.DecodeString(username)
	if err != nil {
		b.Fatal(err)
	}
	passwordBytes, err := hex.DecodeString(password)
	if err != nil {
		b.Fatal(err)
	}
	var keyID [strictUDPHealthKeyIDBytes]byte
	copy(keyID[:], usernameBytes)
	var key [sha256.Size]byte
	copy(key[:], passwordBytes)
	service := &strictUDPIngressService{
		local:      netip.MustParseAddrPort("127.0.0.1:54320"),
		generation: 31,
		credentials: map[[strictUDPHealthKeyIDBytes]byte]*strictUDPIngressCredential{
			keyID: newStrictUDPIngressCredential("GLOBAL", key),
		},
		tunnel:      strictUDPDroppingTunnel{},
		packetSlots: make(chan struct{}, strictUDPDataMaxInFlight),
	}
	associationID := [16]byte{0xbb}
	frame := strictIngressUDPDataFrame(
		b,
		service.generation,
		username,
		password,
		associationID,
		1,
		netip.MustParseAddrPort("8.8.8.8:443"),
		[]byte("benchmark-payload"),
	)
	source := &net.UDPAddr{IP: net.IPv4(127, 0, 0, 1), Port: 54321}
	associations := make(map[[16]byte]*strictUDPDataAssociation)
	service.handleDataFrame(frame, source, associations, time.Now())
	association := associations[associationID]
	if association == nil {
		b.Fatal("strict UDP benchmark association was not created")
	}

	b.ReportAllocs()
	b.SetBytes(int64(len(frame)))
	b.ResetTimer()
	for index := 0; index < b.N; index++ {
		association.replay = strictUDPReplayWindow{}
		service.handleDataFrame(frame, source, associations, time.Now())
	}
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
	if first.Protocol != 2 || first.UDPEndpoint == "" {
		t.Fatalf("strict ingress did not publish its authenticated UDP health endpoint: %#v", first)
	}
	endpoint := first.Entries[0].Endpoint
	udpConnection, err := net.DialTimeout("udp4", first.UDPEndpoint, time.Second)
	if err != nil {
		t.Fatalf("connect strict UDP health endpoint: %v", err)
	}
	defer udpConnection.Close()
	if err := udpConnection.SetDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatalf("set strict UDP health deadline: %v", err)
	}
	ping := strictIngressUDPHealthPing(t, request.Generation, username, password, 0x5a)
	if _, err := udpConnection.Write(ping); err != nil {
		t.Fatalf("write strict UDP health ping: %v", err)
	}
	pong := make([]byte, strictUDPHealthFrameBytes)
	if _, err := io.ReadFull(udpConnection, pong); err != nil {
		t.Fatalf("read strict UDP health pong: %v", err)
	}
	if pong[strictUDPHealthKindOffset] != strictUDPHealthPong ||
		!bytes.Equal(pong[strictUDPHealthNonceOffset:strictUDPHealthTagOffset], ping[strictUDPHealthNonceOffset:strictUDPHealthTagOffset]) {
		t.Fatalf("strict UDP health response is not correlated: %x", pong)
	}
	passwordBytes, err := hex.DecodeString(password)
	if err != nil {
		t.Fatalf("decode strict UDP health response key: %v", err)
	}
	responseMAC := hmac.New(sha256.New, passwordBytes)
	_, _ = responseMAC.Write(pong[:strictUDPHealthTagOffset])
	if !hmac.Equal(pong[strictUDPHealthTagOffset:], responseMAC.Sum(nil)) {
		t.Fatal("strict UDP health response is not authenticated")
	}
	invalid := append([]byte(nil), ping...)
	invalid[len(invalid)-1] ^= 0xff
	if _, err := udpConnection.Write(invalid); err != nil {
		t.Fatalf("write invalid strict UDP health ping: %v", err)
	}
	if err := udpConnection.SetReadDeadline(time.Now().Add(100 * time.Millisecond)); err != nil {
		t.Fatalf("set invalid strict UDP health deadline: %v", err)
	}
	if _, err := udpConnection.Read(pong); err == nil {
		t.Fatal("strict UDP health endpoint answered an unauthenticated frame")
	}
	oversized := append(append([]byte(nil), ping...), 0)
	if _, err := udpConnection.Write(oversized); err != nil {
		t.Fatalf("write oversized strict UDP health ping: %v", err)
	}
	if err := udpConnection.SetReadDeadline(time.Now().Add(100 * time.Millisecond)); err != nil {
		t.Fatalf("set oversized strict UDP health deadline: %v", err)
	}
	if _, err := udpConnection.Read(pong); err == nil {
		t.Fatal("strict UDP health endpoint accepted an oversized authenticated prefix")
	}
	oversizedDatagram := make([]byte, strictUDPDataMaxFrameBytes+2)
	copy(oversizedDatagram, strictUDPDataMagic)
	if _, err := udpConnection.Write(oversizedDatagram); err != nil {
		t.Fatalf("write oversized strict UDP datagram: %v", err)
	}
	if _, err := udpConnection.Write(ping); err != nil {
		t.Fatalf("write strict UDP health ping after oversized datagram: %v", err)
	}
	if err := udpConnection.SetReadDeadline(time.Now().Add(time.Second)); err != nil {
		t.Fatalf("set strict UDP health recovery deadline: %v", err)
	}
	if _, err := io.ReadFull(udpConnection, pong); err != nil {
		t.Fatalf("strict UDP endpoint did not survive an oversized datagram: %v", err)
	}
	if pong[strictUDPHealthKindOffset] != strictUDPHealthPong {
		t.Fatalf("strict UDP endpoint returned the wrong frame after an oversized datagram: %x", pong)
	}
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
	if err := udpConnection.SetReadDeadline(time.Now().Add(100 * time.Millisecond)); err != nil {
		t.Fatalf("set revoked strict UDP deadline: %v", err)
	}
	if _, err := udpConnection.Write(ping); err == nil {
		if _, err := udpConnection.Read(pong); err == nil {
			t.Fatal("revoked strict UDP health endpoint still answers probes")
		}
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

	valid := `{"protocol":2,"generation":1,"entries":[]}`
	if _, err := handleConfigureStrictIngress(valid); err == nil {
		t.Fatal("unauthenticated strict ingress action accepted")
	}

	if _, err := parseStrictIngressRequest(valid + ` {}`); err == nil {
		t.Fatal("strict ingress request with trailing JSON accepted")
	}
	if _, err := parseStrictIngressRequest(`{"protocol":2,"generation":1,"entries":[],"unknown":true}`); err == nil {
		t.Fatal("strict ingress request with unknown fields accepted")
	}
	if _, err := parseStrictIngressRequest(strings.Repeat("x", maxStrictIngressRequestBytes+1)); err == nil {
		t.Fatal("oversized strict ingress request accepted")
	}
}
