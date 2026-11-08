package main

import (
	"bytes"
	"encoding/json"
	"runtime"
	"unsafe"

	"github.com/metacubex/mihomo/constant"
)

type Action struct {
	Id     string      `json:"id"`
	Method Method      `json:"method"`
	Data   interface{} `json:"data"`
}

func (a *Action) UnmarshalJSON(raw []byte) error {
	var wire struct {
		Id     string          `json:"id"`
		Method Method          `json:"method"`
		Data   json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal(raw, &wire); err != nil {
		return err
	}
	a.Id = wire.Id
	a.Method = wire.Method
	if len(wire.Data) > 0 {
		a.Data = wire.Data
	} else {
		a.Data = nil
	}
	return nil
}

func actionDataJSONBytes(raw interface{}) ([]byte, bool) {
	switch v := raw.(type) {
	case json.RawMessage:
		trimmed := bytes.TrimSpace(v)
		if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
			return nil, false
		}
		if trimmed[0] == '"' {
			var s string
			if err := json.Unmarshal(trimmed, &s); err != nil {
				return nil, false
			}
			return []byte(s), true
		}
		if trimmed[0] == '{' || trimmed[0] == '[' {
			return trimmed, true
		}
		return nil, false
	case string:
		return []byte(v), true
	case []byte:
		return v, true
	default:
		if raw == nil {
			return nil, false
		}
		encoded, err := json.Marshal(raw)
		if err != nil {
			return nil, false
		}
		return encoded, true
	}
}

func actionDataJSONOrString(raw interface{}) (string, bool) {
	switch v := raw.(type) {
	case string:
		return v, true
	case json.RawMessage:
		trimmed := bytes.TrimSpace(v)
		if len(trimmed) == 0 || bytes.Equal(trimmed, []byte("null")) {
			return "", false
		}
		if trimmed[0] == '"' {
			var s string
			if err := json.Unmarshal(trimmed, &s); err != nil {
				return "", false
			}
			return s, true
		}
		if trimmed[0] == '{' || trimmed[0] == '[' {
			return string(trimmed), true
		}
		return "", false
	default:
		return "", false
	}
}

func actionDataStrictString(raw interface{}) (string, bool) {
	switch v := raw.(type) {
	case string:
		return v, true
	case json.RawMessage:
		trimmed := bytes.TrimSpace(v)
		if len(trimmed) == 0 || trimmed[0] != '"' {
			return "", false
		}
		var s string
		if err := json.Unmarshal(trimmed, &s); err != nil {
			return "", false
		}
		return s, true
	default:
		return "", false
	}
}

func actionDataBool(raw interface{}) (bool, bool) {
	switch v := raw.(type) {
	case bool:
		return v, true
	case json.RawMessage:
		trimmed := bytes.TrimSpace(v)
		var b bool
		if err := json.Unmarshal(trimmed, &b); err != nil {
			return false, false
		}
		return b, true
	default:
		return false, false
	}
}

type ActionResult struct {
	Id       string         `json:"id"`
	Method   Method         `json:"method"`
	Data     interface{}    `json:"data"`
	Code     int            `json:"code"`
	Callback unsafe.Pointer `json:"-"`
	Response func([]byte)   `json:"-"`
	owner    *catalogOwner
}

func (result ActionResult) Json() ([]byte, error) {
	data, err := json.Marshal(result)
	return data, err
}

func (result ActionResult) success(data interface{}) {
	result.Code = 0
	result.Data = data
	result.send()
}

func (result ActionResult) error(data interface{}) {
	result.Code = -1
	result.Data = data
	result.send()
}

func handleAction(action *Action, result ActionResult) {
	switch action.Method {
	case catalogParseProviderMethod:
		data, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalidParameters")
			return
		}
		parsed, reason := parseCatalogProviderMessage(data)
		if reason != "" {
			result.error(reason)
		} else {
			result.success(parsed)
		}
		return
	case catalogPrepareMethod, catalogTestDelayMethod, catalogReleaseMethod:
		data, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalidParameters")
			return
		}
		switch action.Method {
		case catalogPrepareMethod:
			handleCatalogPrepare(data, result)
		case catalogReleaseMethod:
			handleCatalogRelease(data, result)
		case catalogTestDelayMethod:
			handleCatalogTestDelay(data, result.owner, func(value string) { result.success(value) })
		}
		return
	case initClashMethod:
		paramsString, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		result.success(handleInitClash(paramsString))
		return
	case getIsInitMethod:
		result.success(handleGetIsInit())
		return
	case forceGcMethod:
		handleForceGc()
		result.success(true)
		return
	case shutdownMethod:
		result.success(handleShutdown())
		return
	case validateConfigMethod:
		s, ok := actionDataStrictString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		result.success(handleValidateConfig([]byte(s)))
		return
	case updateConfigMethod:
		data, ok := actionDataJSONBytes(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		updateError := handleUpdateConfig(data)
		if runtime.GOOS == "darwin" && updateError != "" {
			result.error(updateError)
			return
		}
		result.success(updateError)
		return
	case configureStrictIngressMethod:
		s, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		data, err := handleConfigureStrictIngress(s)
		if err != nil {
			result.error("strict ingress configuration rejected")
			return
		}
		result.success(data)
		return
	case Method("restoreStrictIngressIntent"):
		s, ok := actionDataJSONOrString(action.Data)
		if !ok || handleRestoreMacStrictIngressIntent(s) != nil {
			result.error("strict ingress intent recovery rejected")
			return
		}
		result.success(true)
		return
	case setupConfigMethod:
		data, ok := actionDataJSONBytes(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		setupError := handleSetupConfig(data)
		if runtime.GOOS == "darwin" && setupError != "" {
			result.error(setupError)
			return
		}
		result.success(setupError)
		return
	case getProxiesMethod:
		result.success(handleGetProxies())
		return
	case changeProxyMethod:
		data, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		handleChangeProxy(data, func(value string) {
			result.success(value)
		})
		return
	case getTrafficMethod:
		result.success(handleGetTrafficPayload())
		return
	case getTotalTrafficMethod:
		result.success(handleGetTotalTrafficPayload())
		return
	case resetTrafficMethod:
		handleResetTraffic()
		result.success(true)
		return
	case asyncTestDelayMethod:
		data, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		handleAsyncTestDelayOwned(data, result.owner, func(value string) {
			result.success(value)
		})
		return
	case cancelTestDelayMethod:
		id, ok := actionDataStrictString(action.Data)
		if !ok || id == "" {
			result.error("invalid request id")
			return
		}
		result.success(cancelDelayTaskOwned(result.owner, id, "cancelled"))
		return
	case getConnectionsMethod:
		result.success(handleGetConnectionsRaw())
		return
	case closeConnectionsMethod:
		result.success(handleCloseConnections())
		return
	case resetConnectionsMethod:
		result.success(handleResetConnections())
		return
	case getConfigMethod:
		path, ok := actionDataStrictString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		config, err := handleGetConfig(path)
		if err != nil {
			result.error(err)
			return
		}
		result.success(config)
		return
	case getTunStatusMethod:
		result.success(handleGetTunStatus())
		return
	case getCoreVersionMethod:
		result.success(constant.Version)
		return
	case closeConnectionMethod:
		id, ok := actionDataStrictString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		result.success(handleCloseConnection(id))
		return
	case getExternalProvidersMethod:
		result.success(handleGetExternalProvidersPayload())
		return
	case getExternalProviderMethod:
		externalProviderName, ok := actionDataStrictString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		result.success(handleGetExternalProviderPayload(externalProviderName))
		return
	case updateGeoDataMethod:
		paramsString, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		var params = map[string]string{}
		err := json.Unmarshal([]byte(paramsString), &params)
		if err != nil {
			result.success(err.Error())
			return
		}
		geoType := params["geo-type"]
		geoName := params["geo-name"]
		handleUpdateGeoData(geoType, geoName, func(value string) {
			result.success(value)
		})
		return
	case updateExternalProviderMethod:
		providerName, ok := actionDataStrictString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		handleUpdateExternalProvider(providerName, func(value string) {
			result.success(value)
		})
		return
	case sideLoadExternalProviderMethod:
		paramsString, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		var params = map[string]string{}
		err := json.Unmarshal([]byte(paramsString), &params)
		if err != nil {
			result.success(err.Error())
			return
		}
		providerName := params["providerName"]
		data := params["data"]
		handleSideLoadExternalProvider(providerName, []byte(data), func(value string) {
			result.success(value)
		})
		return
	case startLogMethod:
		handleStartLog()
		result.success(true)
		return
	case stopLogMethod:
		handleStopLog()
		result.success(true)
		return
	case startListenerMethod:
		result.success(handleStartListener())
		return
	case stopListenerMethod:
		result.success(handleStopListener())
		return
	case getCountryCodeMethod:
		ip, ok := actionDataStrictString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		handleGetCountryCode(ip, func(value string) {
			result.success(value)
		})
		return
	case getMemoryMethod:
		handleGetMemory(func(value string) {
			result.success(value)
		})
		return
	case setStateMethod:
		data, ok := actionDataJSONOrString(action.Data)
		if !ok {
			result.error("invalid data type")
			return
		}
		handleSetState(data)
		result.success(true)
		return
	case healthCheckMethod:
		groupName, _ := actionDataStrictString(action.Data)
		handleHealthCheck(groupName, func(value string) {
			result.success(value)
		})
		return
	case healthProbeMethod:
		handleHealthProbe(func(value string) {
			result.success(value)
		})
		return
	case setUiActiveMethod:
		active, _ := actionDataBool(action.Data)
		handleSetUiActive(active)
		result.success(true)
		return
	case setScreenActiveMethod:
		active, _ := actionDataBool(action.Data)
		handleSetScreenActive(active)
		result.success(true)
		return
	case setRequestsActiveMethod:
		active, _ := actionDataBool(action.Data)
		handleSetRequestsActive(active)
		result.success(true)
		return
	case crashMethod:
		result.success(true)
		handleCrash()
	default:
		if !nextHandle(action, result) {
			result.error("unknown method: " + string(action.Method))
		}
	}
}
