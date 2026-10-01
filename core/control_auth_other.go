//go:build !darwin && !cgo

package main

import (
	"bufio"
	"errors"
	"net"
)

func authenticateMacCore(net.Conn, *bufio.Reader, string) error {
	return errors.New("macOS control authentication is unavailable")
}
