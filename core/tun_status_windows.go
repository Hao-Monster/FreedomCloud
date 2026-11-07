//go:build windows

package main

import (
	"errors"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	iphlpapiDLL                   = windows.NewLazySystemDLL("iphlpapi.dll")
	procConvertInterfaceAliasLuid = iphlpapiDLL.NewProc("ConvertInterfaceAliasToLuid")
)

func convertWindowsInterfaceAliasToLuid(alias string) (uint64, error) {
	utf16Alias, err := windows.UTF16PtrFromString(alias)
	if err != nil {
		return 0, windows.ERROR_INVALID_PARAMETER
	}
	var luid uint64
	ret, _, _ := procConvertInterfaceAliasLuid.Call(
		uintptr(unsafe.Pointer(utf16Alias)),
		uintptr(unsafe.Pointer(&luid)),
	)
	if ret != 0 {
		return 0, windows.Errno(ret)
	}
	return luid, nil
}

func queryWindowsInterfaceOperStatus(luid uint64) (uint32, error) {
	row := windows.MibIfRow2{InterfaceLuid: luid}
	if err := windows.GetIfEntry2Ex(windows.MibIfEntryNormalWithoutStatistics, &row); err != nil {
		return 0, err
	}
	return row.OperStatus, nil
}

func isWindowsInterfaceMissingError(err error) bool {
	return errors.Is(err, windows.ERROR_FILE_NOT_FOUND) ||
		errors.Is(err, windows.ERROR_INVALID_PARAMETER) ||
		errors.Is(err, windows.ERROR_NOT_FOUND)
}

func observeWindowsTunInterfaceWith(
	name string,
	resolveLuid func(string) (uint64, error),
	readOperStatus func(uint64) (uint32, error),
	fallback func(string) string,
) string {
	luid, err := resolveLuid(name)
	if err != nil {
		if isWindowsInterfaceMissingError(err) {
			return "missing"
		}
		return fallback(name)
	}
	operStatus, err := readOperStatus(luid)
	if err != nil {
		if isWindowsInterfaceMissingError(err) {
			return "missing"
		}
		return fallback(name)
	}
	if operStatus == windows.IfOperStatusUp {
		return "up"
	}
	return "down"
}

func observePlatformTunInterface(name string) string {
	return observeWindowsTunInterfaceWith(
		name,
		convertWindowsInterfaceAliasToLuid,
		queryWindowsInterfaceOperStatus,
		observeTunInterfaceByEnumeration,
	)
}
