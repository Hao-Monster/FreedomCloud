//go:build !windows

package main

func corePrivilege() string { return "unknown" }
