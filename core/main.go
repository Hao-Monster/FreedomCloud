//go:build !cgo

package main

import (
	"fmt"
	"os"
)

func main() {
	args := os.Args
	if len(args) <= 1 {
		fmt.Println("Arguments error")
		os.Exit(1)
	}
	authToken := ""
	if len(args) > 2 {
		authToken = args[2]
	}
	startServer(args[1], authToken)
}
