//go:build !windows

package main

func observePlatformTunInterface(name string) string {
	return observeTunInterfaceByEnumeration(name)
}
