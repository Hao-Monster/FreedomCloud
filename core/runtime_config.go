package main

import (
 "encoding/json"
 "fmt"

 "github.com/metacubex/mihomo/config"
)

// Protected by runLock. Captured from the config actually passed to ApplyConfig,
// including the explicit fallback; never populated from an unaccepted UI draft.
var appliedRawConfig []byte

func runtimeConfigSnapshot() (*config.RawConfig, error) {
 runLock.Lock()
 defer runLock.Unlock()
 if len(appliedRawConfig) == 0 || currentConfig == nil {
  return nil, fmt.Errorf("Core has no applied configuration snapshot")
 }
 var values map[string]json.RawMessage
 if err := json.Unmarshal(appliedRawConfig, &values); err != nil { return nil, err }
 general, err := json.Marshal(currentConfig.General)
 if err != nil { return nil, err }
 var live map[string]json.RawMessage
 if err = json.Unmarshal(general, &live); err != nil { return nil, err }
 for key, value := range live { values[key] = value }
 // General.Tun.Enable stores the pending preference, while the listener is
 // intentionally stopped when the proxy is stopped.
 var tun map[string]json.RawMessage
 if err = json.Unmarshal(values["tun"], &tun); err == nil && tun != nil {
  tun["enable"], _ = json.Marshal(isRunning && pendingTunEnable)
  values["tun"], _ = json.Marshal(tun)
 }
 values["external-controller"], err = json.Marshal(currentConfig.Controller.ExternalController)
 if err != nil { return nil, err }
 data, err := json.Marshal(values)
 if err != nil { return nil, err }
 result := &config.RawConfig{}
 if err = json.Unmarshal(data, result); err != nil { return nil, err }
 return result, nil
}
