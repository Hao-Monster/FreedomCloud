package main

import (
	"encoding/json"
	"fmt"
	"slices"

	"github.com/metacubex/mihomo/config"
)

// Protected by runLock. Captured from the config actually passed to ApplyConfig,
// including the explicit fallback; never populated from an unaccepted UI draft.
var appliedRawConfig []byte

func runtimeConfigSnapshot() (*config.RawConfig, error) {
	runLock.Lock()
	if len(appliedRawConfig) == 0 || currentConfig == nil || currentConfig.General == nil || currentConfig.Controller == nil {
		runLock.Unlock()
		return nil, fmt.Errorf("Core has no applied configuration snapshot")
	}
	raw := appliedRawConfig
	general := *currentConfig.General
	general.SkipAuthPrefixes = slices.Clone(general.SkipAuthPrefixes)
	general.LanAllowedIPs = slices.Clone(general.LanAllowedIPs)
	general.LanDisAllowedIPs = slices.Clone(general.LanDisAllowedIPs)
	externalController := currentConfig.Controller.ExternalController
	tunActive := isRunning && pendingTunEnable
	runLock.Unlock()

	result := &config.RawConfig{}
	if err := json.Unmarshal(raw, result); err != nil {
		return nil, err
	}

	result.Port = general.Port
	result.SocksPort = general.SocksPort
	result.RedirPort = general.RedirPort
	result.TProxyPort = general.TProxyPort
	result.MixedPort = general.MixedPort
	result.ShadowSocksConfig = general.ShadowSocksConfig
	result.VmessConfig = general.VmessConfig
	result.InboundTfo = general.InboundTfo
	result.InboundMPTCP = general.InboundMPTCP
	result.SkipAuthPrefixes = general.SkipAuthPrefixes
	result.LanAllowedIPs = general.LanAllowedIPs
	result.LanDisAllowedIPs = general.LanDisAllowedIPs
	result.AllowLan = general.AllowLan
	result.BindAddress = general.BindAddress
	result.Mode = general.Mode
	result.UnifiedDelay = general.UnifiedDelay
	result.LogLevel = general.LogLevel
	result.IPv6 = general.IPv6
	result.ExternalController = externalController
	result.Interface = general.Interface
	result.RoutingMark = general.RoutingMark
	result.GeoAutoUpdate = general.GeoAutoUpdate
	result.GeoUpdateInterval = general.GeoUpdateInterval
	result.GeodataMode = general.GeodataMode
	result.GeodataLoader = general.GeodataLoader
	result.GeositeMatcher = general.GeositeMatcher
	result.TCPConcurrent = general.TCPConcurrent
	result.FindProcessMode = general.FindProcessMode
	result.GlobalUA = general.GlobalUA
	result.ETagSupport = general.ETagSupport
	result.KeepAliveIdle = general.KeepAliveIdle
	result.KeepAliveInterval = general.KeepAliveInterval
	result.DisableKeepAlive = general.DisableKeepAlive
	result.GeoXUrl = config.RawGeoXUrl{
		GeoIp:   general.GeoXUrl.GeoIp,
		Mmdb:    general.GeoXUrl.Mmdb,
		ASN:     general.GeoXUrl.ASN,
		GeoSite: general.GeoXUrl.GeoSite,
	}

	// Copy small live Tun (~300 B) into RawTun and reflect runtime listener state.
	if tunBytes, err := json.Marshal(general.Tun); err == nil {
		_ = json.Unmarshal(tunBytes, &result.Tun)
	}
	result.Tun.Enable = tunActive
	return result, nil
}
