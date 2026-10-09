//go:build !cgo

package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"runtime"
	"strconv"
	"sync"
)

var conn *coreOutput
var connMu sync.Mutex

// All connection ownership passes through this boundary, which also permits
// isolated net.Pipe tests without starting a Core listener or process.
func attachCoreConnection(c net.Conn) func() {
	output := newCoreOutput(c, coreWriteTimeout, coreEnqueueTimeout)
	output.onClose = func() {
		connMu.Lock()
		owned := conn == output
		if owned {
			conn = nil
		}
		connMu.Unlock()
		if owned {
			cancelAllDelayTasks("sessionClosed")
		}
	}
	connMu.Lock()
	previous := conn
	conn = output
	connMu.Unlock()
	if previous != nil {
		previous.close()
	}
	cancelAllDelayTasks("sessionClosed")
	go output.writeLoop()
	return output.close
}

func (result ActionResult) send() {
	data, err := result.Json()
	if err != nil {
		result.Code, result.Data = -1, "Core response encoding failed"
		data, _ = result.Json()
	}
	if result.Response != nil {
		result.Response(data)
		return
	}
	send(data)
}

func sendMessage(message Message) {
	result := ActionResult{
		Method: messageMethod,
		Data:   message,
	}
	data, err := result.Json()
	if err != nil {
		return
	}
	connMu.Lock()
	output := conn
	connMu.Unlock()
	if output != nil {
		output.sendStream(data)
	}
}

func send(data []byte) {
	connMu.Lock()
	output := conn
	connMu.Unlock()
	if output != nil {
		_ = output.sendReliable(data)
	}
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

	detach := attachCoreConnection(c)
	connMu.Lock()
	output := conn
	connMu.Unlock()

	defer func() {
		agentCoreAuthenticated.Store(false)
		wasMacAuthenticated := macCoreAuthenticated.Swap(false)
		detach()
		if wasMacAuthenticated {
			runLock.Lock()
			macStrictIngressIntent = nil
			removeStrictIngressListenersLocked()
			runLock.Unlock()
		}
	}()

	for {
		data, err := readCoreLine(reader)
		if err != nil {
			return
		}
		var action = &Action{}

		err = json.Unmarshal([]byte(data), action)

		if err != nil {
			fmt.Printf("startServer: invalid action json: %v\n", err)
			continue
		}

		dispatchCoreAction(output, action, handleAction)
	}
}

func dispatchCoreAction(output *coreOutput, action *Action, handler func(*Action, ActionResult)) bool {
	result := ActionResult{Id: action.Id, Method: action.Method}
	slots := output.actions
	// A full batch of asynchronous work must not exclude its cancellation.
	switch action.Method {
	case cancelTestDelayMethod, setUiActiveMethod, stopListenerMethod, shutdownMethod:
		slots = output.controls
	}
	select {
	case <-output.done:
		return false
	default:
	}
	select {
	case slots <- struct{}{}:
		var completed sync.Once
		result.Response = func(data []byte) { completed.Do(func() { defer func() { <-slots }(); _ = output.sendReliable(data) }) }
		go handler(action, result)
		return true
	default:
		result.Response = func(data []byte) { _ = output.sendReliable(data) }
		result.error("Core request capacity exceeded")
		return false
	}
}

func readCoreLine(reader *bufio.Reader) (string, error) {
	var data []byte
	for {
		fragment, err := reader.ReadSlice('\n')
		if len(data)+len(fragment) > coreMaxMessageBytes {
			return "", fmt.Errorf("Core input exceeds message limit")
		}
		data = append(data, fragment...)
		if err == nil {
			return string(data), nil
		}
		if err != bufio.ErrBufferFull {
			if err == io.EOF && len(data) != 0 {
				return "", io.ErrUnexpectedEOF
			}
			return "", err
		}
	}
}

func nextHandle(action *Action, result ActionResult) bool {
	return false
}
