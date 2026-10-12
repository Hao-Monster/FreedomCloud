package main

import (
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/hub/route"
	"testing"
)

func TestControllerRuntimeBoundaryPreservesFullConfiguration(t *testing.T) {
	original := recreateControllerServer
	t.Cleanup(func() { recreateControllerServer = original })
	var received *route.Config
	recreateControllerServer = func(cfg *route.Config) error { received = cfg; return nil }
	cfg := &config.Config{General: &config.General{}, Controller: &config.Controller{ExternalController: "127.0.0.1:9090", ExternalControllerTLS: "127.0.0.1:9091", ExternalControllerUnix: "synthetic.sock", ExternalControllerPipe: `\\.\pipe\synthetic`, ExternalControllerRoutingMark: 42, Secret: "audit-secret", ExternalDohServer: "/dns-query", Cors: config.Cors{AllowOrigins: []string{"https://example.test"}, AllowPrivateNetwork: true}}, TLS: &config.TLS{Certificate: "certificate", PrivateKey: "key", ClientAuthType: "RequireAndVerifyClientCert", ClientAuthCert: "ca", EchKey: "ech"}}
	if err := recreateRuntimeController(cfg); err != nil {
		t.Fatal(err)
	}
	if received == nil || received.Secret != "audit-secret" || received.TLSAddr != "127.0.0.1:9091" || received.UnixAddr != "synthetic.sock" || received.PipeAddr != `\\.\pipe\synthetic` || received.RoutingMark != 42 || received.Certificate != "certificate" || received.PrivateKey != "key" || received.ClientAuthType != "RequireAndVerifyClientCert" || received.ClientAuthCert != "ca" || received.EchKey != "ech" || received.DohServer != "/dns-query" || len(received.Cors.AllowOrigins) != 1 || !received.Cors.AllowPrivateNetwork {
		t.Fatal("controller construction dropped security or transport configuration")
	}
}

func TestControllerToggleClosesEveryTransportAndRetainsConfiguredOptions(t *testing.T) {
	isolateConfigRuntime(t)
	currentConfig = &config.Config{General: &config.General{}, Controller: &config.Controller{ExternalController: "127.0.0.1:9191", ExternalControllerTLS: "127.0.0.1:9192", ExternalControllerUnix: "synthetic.sock", Secret: "keep-secret"}}
	var received *config.Config
	recreateRuntimeController = func(cfg *config.Config) error { received = cfg; return nil }
	off := ""
	disabled := false
	if err := updateConfig(&UpdateParams{ExternalController: &off, ControllerEnabled: &disabled}); err != nil {
		t.Fatal(err)
	}
	if received.Controller.ExternalController != "" || received.Controller.ExternalControllerTLS != "" || received.Controller.ExternalControllerUnix != "" {
		t.Fatal("disable kept an effective listener")
	}
	if currentConfig.Controller.ExternalControllerTLS != "127.0.0.1:9192" || currentConfig.Controller.Secret != "keep-secret" {
		t.Fatal("disable discarded configured options")
	}
	on := "127.0.0.1:9191"
	enabled := true
	if err := updateConfig(&UpdateParams{ExternalController: &on, ControllerEnabled: &enabled}); err != nil {
		t.Fatal(err)
	}
	if received.Controller.ExternalController != on || received.Controller.ExternalControllerTLS != "127.0.0.1:9192" || received.Controller.Secret != "keep-secret" {
		t.Fatal("enable lost profile configuration")
	}
}
