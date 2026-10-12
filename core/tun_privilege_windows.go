//go:build windows

package main

import (
	"unsafe"

	"golang.org/x/sys/windows"
)

func corePrivilege() string {
	token, err := windows.OpenCurrentProcessToken()
	if err != nil {
		return "unknown"
	}
	defer token.Close()
	var elevated, returned uint32
	if err := windows.GetTokenInformation(token, windows.TokenElevation, (*byte)(unsafe.Pointer(&elevated)), uint32(unsafe.Sizeof(elevated)), &returned); err != nil {
		return "unknown"
	}
	if elevated != 0 {
		return "elevated"
	}
	return "unprivileged"
}
