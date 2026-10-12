package main

import (
	"fmt"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/log"
)

// These are the actual operating-system boundaries. Tests replace them rather
// than launching proxy listeners, controller sockets or provider probes.
var applyRuntimeConfig = executor.ApplyConfig
var runtimeControllerEnabled = true

func effectiveControllerConfig(cfg *config.Config, enabled bool) *config.Config {
	if enabled {
		return cfg
	}
	candidate := *cfg
	controller := *cfg.Controller
	controller.ExternalController = ""
	controller.ExternalControllerTLS = ""
	controller.ExternalControllerUnix = ""
	controller.ExternalControllerPipe = ""
	candidate.Controller = &controller
	return &candidate
}

var recreateControllerServer = route.ReCreateServerChecked
var recreateRuntimeController = func(cfg *config.Config) error {
	if cfg == nil || cfg.Controller == nil || cfg.General == nil {
		return fmt.Errorf("controller configuration is incomplete")
	}
	c := cfg.Controller
	settings := &route.Config{
		Addr:        c.ExternalController,
		TLSAddr:     c.ExternalControllerTLS,
		UnixAddr:    c.ExternalControllerUnix,
		PipeAddr:    c.ExternalControllerPipe,
		RoutingMark: c.ExternalControllerRoutingMark,
		Secret:      c.Secret,
		DohServer:   c.ExternalDohServer,
		IsDebug:     cfg.General.LogLevel == log.DEBUG,
		Cors: route.Cors{
			AllowOrigins:        append([]string(nil), c.Cors.AllowOrigins...),
			AllowPrivateNetwork: c.Cors.AllowPrivateNetwork,
		},
	}
	if cfg.TLS != nil {
		settings.Certificate = cfg.TLS.Certificate
		settings.PrivateKey = cfg.TLS.PrivateKey
		settings.ClientAuthType = cfg.TLS.ClientAuthType
		settings.ClientAuthCert = cfg.TLS.ClientAuthCert
		settings.EchKey = cfg.TLS.EchKey
	}
	settings.UIPath = &c.ExternalUI
	return recreateControllerServer(settings)
}
var refreshRuntimeListeners = updateListeners
var clearRuntimeStrictIngress = clearStrictIngressForConfigChangeLocked
var restoreRuntimeStrictIngress = restoreMacStrictIngressLocked
var selectRuntimeGroups = patchSelectGroup
var startRuntimeHealthChecks = func() { runInitialProviderHealthChecks(); startHealthCheckForwarder() }
