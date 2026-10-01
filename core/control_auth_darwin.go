//go:build darwin && !cgo

package main

import (
	"bufio"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"os"
	"time"

	"golang.org/x/sys/unix"
)

type macCoreAuthentication struct {
	Protocol uint32 `json:"protocol"`
	Nonce string `json:"nonce"`
	Proof string `json:"proof"`
}

// Authenticate both ends before privileged strict ingress can be configured.
// The Agent uses TCP loopback; a direct desktop host uses a same-user Unix
// socket. Neither path transmits the per-launch secret itself.
func authenticateMacCore(connection net.Conn, reader *bufio.Reader, token string) error {
	key, err := hex.DecodeString(token)
	if err != nil || len(key) != sha256.Size {
		return errors.New("invalid macOS control credential")
	}
	switch socket := connection.(type) {
	case *net.UnixConn:
		raw, err := socket.SyscallConn()
		if err != nil { return err }
		var peerErr error
		if err := raw.Control(func(fd uintptr) {
			credential, err := unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
			if err != nil { peerErr = err; return }
			if credential.Uid != uint32(os.Getuid()) {
				peerErr = errors.New("macOS control peer has a different user")
			}
		}); err != nil { return err }
		if peerErr != nil { return peerErr }
	case *net.TCPConn:
		remote, ok := socket.RemoteAddr().(*net.TCPAddr)
		if !ok || !remote.IP.IsLoopback() {
			return errors.New("macOS Agent control must be loopback")
		}
	default:
		return errors.New("unsupported macOS control transport")
	}
	if err := connection.SetDeadline(time.Now().Add(10*time.Second)); err != nil { return err }
	defer connection.SetDeadline(time.Time{})
	var nonce [32]byte
	if _, err := rand.Read(nonce[:]); err != nil { return err }
	nonceHex := hex.EncodeToString(nonce[:])
	proof := func(role string) []byte {
		mac := hmac.New(sha256.New, key)
		_, _ = mac.Write([]byte("FCX-MAC-CORE/1/" + role + "/" + nonceHex))
		return mac.Sum(nil)
	}
	envelope := struct { Authentication macCoreAuthentication `json:"_macCore"` }{
		Authentication: macCoreAuthentication{Protocol: 1, Nonce: nonceHex, Proof: hex.EncodeToString(proof("core"))},
	}
	message, err := json.Marshal(envelope)
	if err != nil { return err }
	if _, err := connection.Write(append(message, '\n')); err != nil { return err }
	// ReadSlice preserves any subsequent ordinary action already in the reader.
	line, err := reader.ReadSlice('\n')
	if err != nil || len(line) > 4096 { return errors.New("invalid macOS control response") }
	var response struct { Authentication macCoreAuthentication `json:"_macCore"` }
	if err := json.Unmarshal(line, &response); err != nil { return err }
	actual, err := hex.DecodeString(response.Authentication.Proof)
	if err != nil || response.Authentication.Protocol != 1 || response.Authentication.Nonce != nonceHex ||
		!hmac.Equal(actual, proof("host")) {
		return errors.New("macOS control response authentication failed")
	}
	return nil
}
