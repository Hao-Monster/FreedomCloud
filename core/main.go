//go:build !cgo

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"runtime"
	"strings"
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
	if runtime.GOOS == "darwin" && authToken != "" {
		if authToken != "@stdin" {
			fmt.Println("macOS control credential must use the private stdin channel")
			os.Exit(1)
		}
		line, err := bufio.NewReader(io.LimitReader(os.Stdin, 66)).ReadString('\n')
		if err != nil || len(line) != 65 || !strings.HasSuffix(line, "\n") {
			fmt.Println("macOS control credential input is invalid")
			os.Exit(1)
		}
		authToken = strings.TrimSuffix(line, "\n")
	}
	startServer(args[1], authToken)
}
