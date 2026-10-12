//go:build android && cgo

package main

import "C"
import (
	"context"
	"core/platform"
	"core/state"
	t "core/tun"
	"encoding/json"
	"errors"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"golang.org/x/sync/semaphore"
	"net"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

type TunHandler struct {
	listener  *sing_tun.Listener
	callback  unsafe.Pointer
	limit     *semaphore.Weighted
	resource  *retiredResource
	ready     atomic.Bool
	ctx       context.Context
	cancel    context.CancelFunc
	closeOnce sync.Once
}

func (t *TunHandler) close() {
	t.closeOnce.Do(func() {
		t.ready.Store(false)
		t.cancel()
		removeTunHook()
		t.resource.Retire()
		l := t.listener
		t.listener = nil
		if l != nil {
			_ = l.Close()
		}
	})
	// JNI calls may outlive this bounded stop. Their leases retain the immutable
	// callback until the last late return, which then releases it exactly once.
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := t.resource.Wait(ctx); err != nil {
		log.Warnln("TunHandler.close: waiting for late JNI calls; pending retired handlers=%d", pendingRetiredResources())
	}
}

func (t *TunHandler) acquireCallback() (func(), bool) {
	if !t.ready.Load() || t.limit.Acquire(t.ctx, 1) != nil {
		return nil, false
	}
	lease, ok := t.resource.Acquire()
	if !ok {
		t.limit.Release(1)
		return nil, false
	}
	return func() { lease(); t.limit.Release(1) }, true
}

func (t *TunHandler) handleProtect(fd int) {
	release, ok := t.acquireCallback()
	if !ok {
		return
	}
	defer release()
	Protect(t.callback, fd)
}

func (t *TunHandler) handleResolveProcess(source, target net.Addr) string {
	release, ok := t.acquireCallback()
	if !ok {
		return ""
	}
	defer release()
	var protocol int
	uid := -1
	switch source.Network() {
	case "udp", "udp4", "udp6":
		protocol = syscall.IPPROTO_UDP
	case "tcp", "tcp4", "tcp6":
		protocol = syscall.IPPROTO_TCP
	}
	if version.Load() < 29 {
		uid = platform.QuerySocketUidFromProcFs(source, target)
	}
	return ResolveProcess(t.callback, protocol, source.String(), target.String(), uid)
}

var (
	tunLock    sync.Mutex
	runTime    *time.Time
	errBlocked = errors.New("blocked")
	tunHandler *TunHandler
)

func handleStopTun() {
	tunLock.Lock()
	defer tunLock.Unlock()
	runTime = nil
	tunUp.Store(false)
	if tunHandler != nil {
		tunHandler.close()
	}
}

func handleStartTun(fd int, callback unsafe.Pointer) bool {
	handleStopTun()
	runLock.Lock()
	if currentConfig == nil {
		runLock.Unlock()
		// The Kotlin caller now only closes the fd when the core was never reached
		// (loader.start threw before handing it off). Once startTun is entered the
		// core owns it; the fd was never wrapped by sing-tun on this path, so close
		// it here to avoid leaking it.
		if fd != 0 {
			_ = syscall.Close(fd)
		}
		if callback != nil {
			releaseObject(callback)
		}
		return false
	}
	tunCfg := currentConfig.General.Tun
	runLock.Unlock()
	tunLock.Lock()
	defer tunLock.Unlock()
	now := time.Now()
	runTime = &now
	if fd != 0 {
		tunHandler = &TunHandler{
			callback: callback,
			limit:    semaphore.NewWeighted(4),
		}
		tunHandler.ctx, tunHandler.cancel = context.WithCancel(context.Background())
		tunHandler.resource = newRetiredResource(func() {
			if callback != nil {
				releaseObject(callback)
			}
		})
		initTunHook()
		tunListener, err := t.Start(fd, tunCfg)
		if err != nil {
			log.Errorln("handleStartTun: t.Start failed: %v", err)
			// fd ownership: the Kotlin caller no longer closes the fd on a false
			// return (it sets fdHandedToCore=true before Core.startTun). Once startTun
			// is entered the fd belongs to sing-tun, which closes it exactly once via
			// Listener.Close on a post-wrap failure (NewStack/tunStack.Start). Do NOT
			// add an unconditional syscall.Close(fd) here — that would double-close a
			// number sing-tun may have already closed/reused. (A rare pre-wrap sing-tun
			// failure would leak this one fd; accepted over a double-close.)
			if tunHandler != nil {
				tunHandler.close()
				tunHandler = nil
			}
			runTime = nil
			return false
		}
		if tunListener != nil {
			log.Infoln("TUN address: %v", tunListener.Address())
			tunHandler.listener = tunListener
			tunHandler.ready.Store(true)
		} else {
			if tunHandler != nil {
				tunHandler.close()
				tunHandler = nil
			}
			runTime = nil
			return false
		}
	} else if callback != nil {
		releaseObject(callback)
	}
	// The TUN is up. A headless tile/boot start reaches here without ever calling
	// startListener (so isRunning stays false); tunUp lets the connections "Journal"
	// forwarder run for this tunnel once the UI is foregrounded (see hub.go).
	tunUp.Store(true)
	return true
}

func handleGetRunTime() string {
	tunLock.Lock()
	defer tunLock.Unlock()
	if runTime == nil {
		return ""
	}
	return strconv.FormatInt(runTime.UnixMilli(), 10)
}

func initTunHook() {
	// Capture the handler locally so the hooks bind to THIS generation's handler.
	// The global tunHandler is set to nil on failure paths (after removeTunHook);
	// a dial goroutine that read the hook before removeTunHook would otherwise
	// deref a nil global and panic the whole :remote process. handleProtect/
	// handleResolveProcess nil-guard their own listener, so a stale-but-non-nil
	// handler is safe. This also prevents cross-generation callback bleed.
	h := tunHandler
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		if platform.ShouldBlockConnection() {
			return errBlocked
		}
		return conn.Control(func(fd uintptr) {
			h.handleProtect(int(fd))
		})
	}
	process.DefaultPackageNameResolver = func(metadata *constant.Metadata) (string, error) {
		src, dst := metadata.RawSrcAddr, metadata.RawDstAddr
		if src == nil || dst == nil {
			return "", process.ErrInvalidNetwork
		}
		return h.handleResolveProcess(src, dst), nil
	}
}

func removeTunHook() {
	dialer.DefaultSocketHook = nil
	process.DefaultPackageNameResolver = nil
}

func handleGetAndroidVpnOptions() string {
	runLock.Lock()
	defer runLock.Unlock()
	if currentConfig == nil {
		return ""
	}
	mixedPort := currentConfig.General.MixedPort
	// With the HTTP/SOCKS inbound disabled there is no proxy endpoint to
	// advertise via VpnService.setHttpProxy — force it off so Android doesn't
	// end up with a ProxyInfo pointing at 127.0.0.1:0.
	systemProxy := state.CurrentState.VpnProps.SystemProxy && mixedPort != 0
	options := state.AndroidVpnOptions{
		Enable:           state.CurrentState.VpnProps.Enable,
		Port:             mixedPort,
		Ipv4Address:      state.DefaultIpv4Address,
		Ipv6Address:      state.GetIpv6Address(),
		AccessControl:    state.CurrentState.VpnProps.AccessControl,
		SystemProxy:      systemProxy,
		AllowBypass:      state.CurrentState.VpnProps.AllowBypass,
		RouteAddress:     currentConfig.General.Tun.RouteAddress,
		BypassDomain:     state.CurrentState.BypassDomain,
		DnsServerAddress: state.GetDnsServerAddress(),
		IncludePackage:   currentConfig.General.Tun.IncludePackage,
		ExcludePackage:   currentConfig.General.Tun.ExcludePackage,
	}
	data, err := json.Marshal(options)
	if err != nil {
		log.Errorln("Error: %v", err)
		return ""
	}
	return string(data)
}

func handleUpdateDns(value string) {
	var dnsServers []string
	if err := json.Unmarshal([]byte(value), &dnsServers); err != nil {
		// Fallback to comma-split for backward compatibility
		dnsServers = strings.Split(value, ",")
	}
	go func() {
		log.Infoln("[DNS] updateDns %s", value)
		dns.UpdateSystemDNS(dnsServers)
		dns.FlushCacheWithDefaultResolver()
	}()
}

func handleGetCurrentProfileName() string {
	runLock.Lock()
	defer runLock.Unlock()
	if state.CurrentState == nil {
		return ""
	}
	return state.CurrentState.CurrentProfileName
}

func nextHandle(action *Action, result ActionResult) bool {
	switch action.Method {
	case getAndroidVpnOptionsMethod:
		result.success(handleGetAndroidVpnOptions())
		return true
	case updateDnsMethod:
		data, ok := action.Data.(string)
		if !ok {
			result.error("invalid data type")
			return true
		}
		handleUpdateDns(data)
		result.success(true)
		return true
	case getRunTimeMethod:
		result.success(handleGetRunTime())
		return true
	case getCurrentProfileNameMethod:
		result.success(handleGetCurrentProfileName())
		return true
	}
	return false
}

//export quickStart
func quickStart(initParamsChar *C.char, paramsChar *C.char, stateParamsChar *C.char, callback unsafe.Pointer) {
	paramsString := C.GoString(initParamsChar)
	bytes := []byte(C.GoString(paramsChar))
	stateParams := C.GoString(stateParamsChar)
	go func() {
		// Callback lifetime is managed on the JVM side: invoke_callback_impl deletes
		// the global ref after delivering onResult. Every path below fires the
		// callback exactly once.
		if !handleInitClash(paramsString) {
			invokeCallback(callback, "init error")
			return
		}
		handleSetState(stateParams)
		invokeCallback(callback, handleSetupConfig(bytes))
	}()
}

//export startTUN
func startTUN(fd C.int, callback unsafe.Pointer) bool {
	return handleStartTun(int(fd), callback)
}

//export getRunTime
func getRunTime() *C.char {
	return C.CString(handleGetRunTime())
}

//export stopTun
func stopTun() {
	handleStopTun()
}

//export getCurrentProfileName
func getCurrentProfileName() *C.char {
	return C.CString(handleGetCurrentProfileName())
}

//export getAndroidVpnOptions
func getAndroidVpnOptions() *C.char {
	return C.CString(handleGetAndroidVpnOptions())
}

//export setState
func setState(s *C.char) {
	paramsString := C.GoString(s)
	handleSetState(paramsString)
}

//export updateDns
func updateDns(s *C.char) {
	dnsList := C.GoString(s)
	handleUpdateDns(dnsList)
}

//export resetConnections
func resetConnections() {
	go func() {
		runLock.Lock()
		defer runLock.Unlock()
		resolver.ResetConnection()
		closeConnections()
		log.Infoln("[Network] connections reset after network change")
	}()
}
