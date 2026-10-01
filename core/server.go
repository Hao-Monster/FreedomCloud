//go:build !cgo

package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"net"
	"runtime"
	"strconv"
	"sync"
)

var conn net.Conn
var connMu sync.Mutex

func (result ActionResult) send() {
	data, err := result.Json()
	if err != nil {
		return
	}
	send(data)
}

func sendMessage(message Message) {
	result := ActionResult{
		Method: messageMethod,
		Data:   message,
	}
	result.send()
}

func send(data []byte) {
	connMu.Lock()
	defer connMu.Unlock()
	if conn == nil {
		return
	}
	_, _ = conn.Write(append(data, []byte("\n")...))
}

func startServer(arg string, authToken string) {
	agentCoreAuthenticated.Store(false)
	macCoreAuthenticated.Store(false)

	_, numErr := strconv.Atoi(arg)

	var c net.Conn
	var err error
	if numErr != nil {
		c, err = net.Dial("unix", arg)
	} else {
		c, err = net.Dial("tcp", fmt.Sprintf("127.0.0.1:%s", arg))
	}
	if err != nil {
		fmt.Printf("startServer: connection failed: %v\n", err)
		return
	}
	reader := bufio.NewReaderSize(c, 4096)
	if runtime.GOOS == "darwin" && authToken != "" {
		if err := authenticateMacCore(c, reader, authToken); err != nil {
			_ = c.Close()
			fmt.Println("startServer: macOS control authentication failed")
			return
		}
		macCoreAuthenticated.Store(true)
	} else if authToken != "" {
		handshake, marshalErr := json.Marshal(map[string]any{
			"_agentCore": map[string]string{"token": authToken},
		})
		if marshalErr != nil {
			_ = c.Close()
			return
		}
		if _, writeErr := c.Write(append(handshake, '\n')); writeErr != nil {
			_ = c.Close()
			return
		}
		agentCoreAuthenticated.Store(true)
	}

	connMu.Lock()
	conn = c
	connMu.Unlock()

	defer func() {
		agentCoreAuthenticated.Store(false)
		if macCoreAuthenticated.Swap(false) {
			runLock.Lock()
			macStrictIngressIntent = nil
			removeStrictIngressListenersLocked()
			runLock.Unlock()
		}
		connMu.Lock()
		if conn != nil {
			_ = conn.Close()
			conn = nil
		}
		connMu.Unlock()
	}()

	for {
		data, err := reader.ReadString('\n')
		if err != nil {
			return
		}
		var action = &Action{}

		err = json.Unmarshal([]byte(data), action)

		if err != nil {
			fmt.Printf("startServer: invalid action json: %v\n", err)
			continue
		}

		result := ActionResult{
			Id:     action.Id,
			Method: action.Method,
		}

		go handleAction(action, result)
	}
}

func nextHandle(action *Action, result ActionResult) bool {
	return false
}
