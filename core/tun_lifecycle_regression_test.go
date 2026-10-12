package main

import (
	"testing"

	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
)

// This reproduces a stale enabled claim without creating a device or routes.
// Cleanup is also called outside the normal ReCreateTun(disabled) path.
func TestTunCleanupDoesNotClaimRunning(t *testing.T) {
	previous := listener.LastTunConf
	t.Cleanup(func() { listener.LastTunConf = previous })
	listener.LastTunConf = LC.Tun{Enable: true, Device: "never-created-test-device"}
	listener.Cleanup()
	if listener.GetTunConf().Enable {
		t.Fatal("TUN reports enabled after Cleanup without an active listener")
	}
}
