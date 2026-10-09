//go:build !cgo

package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"net"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestCoreStreamCannotWaitForConsumer(t *testing.T) {
	left, right := net.Pipe()
	detach := attachCoreConnection(left)
	done := make(chan struct{})
	defer func() { _ = left.Close(); _ = right.Close(); <-done; detach() }()
	go func() {
		for i := 0; i < 1024; i++ {
			sendMessage(Message{Type: RequestMessage, Data: "sample"})
		}
		close(done)
	}()
	select {
	case <-done:
	case <-time.After(100 * time.Millisecond):
		t.Fatal("stream output blocked behind a consumer that does not read")
	}
}

func TestCoreOutputWriteDeadlineClosesSession(t *testing.T) {
	left, right := net.Pipe()
	defer right.Close()
	output := newCoreOutput(left, 20*time.Millisecond, 20*time.Millisecond)
	go output.writeLoop()
	if err := output.sendReliable([]byte(`{"id":"one"}`)); err != nil {
		t.Fatal(err)
	}
	select {
	case <-output.writerDone:
	case <-time.After(time.Second):
		t.Fatal("write deadline did not terminate writer")
	}
	if err := output.sendReliable([]byte("later")); err == nil {
		t.Fatal("closed session accepted reply")
	}
	if output.bytes.Load() != 0 {
		t.Fatal("queued bytes retained after close")
	}
}

func TestCoreReliableQueueFailureIsExplicit(t *testing.T) {
	left, right := net.Pipe()
	defer right.Close()
	output := newCoreOutput(left, time.Second, 20*time.Millisecond)
	for i := 0; i < 256; i++ {
		if err := output.sendReliable([]byte("reply")); err != nil {
			t.Fatal(err)
		}
	}
	if err := output.sendReliable([]byte("overflow")); err == nil {
		t.Fatal("full reliable queue silently accepted response")
	}
	select {
	case <-output.done:
	default:
		t.Fatal("reliable failure did not fail session")
	}
	go output.writeLoop()
	<-output.writerDone
	if output.bytes.Load() != 0 {
		t.Fatal("queued replies retained")
	}
}

func TestCoreOutputNormalAndConcurrentClose(t *testing.T) {
	left, right := net.Pipe()
	output := newCoreOutput(left, time.Second, time.Second)
	go output.writeLoop()
	data := make(chan string, 1)
	go func() { line, _ := bufio.NewReader(right).ReadString('\n'); data <- line }()
	if err := output.sendReliable([]byte("reply")); err != nil {
		t.Fatal(err)
	}
	if got := <-data; got != "reply\n" {
		t.Fatal(got)
	}
	var senders sync.WaitGroup
	for i := 0; i < 32; i++ {
		senders.Add(1)
		go func() {
			defer senders.Done()
			for n := 0; n < 100; n++ {
				output.sendStream([]byte("sample"))
			}
		}()
	}
	output.close()
	senders.Wait()
	right.Close()
	select {
	case <-output.writerDone:
	case <-time.After(time.Second):
		t.Fatal("close waited for writer lock")
	}
	if output.bytes.Load() != 0 {
		t.Fatalf("remaining queued bytes %d", output.bytes.Load())
	}
}

func TestCoreOutputByteBudgetAndBoundedInput(t *testing.T) {
	left, right := net.Pipe()
	defer right.Close()
	output := newCoreOutput(left, time.Second, time.Second)
	chunk := bytes.Repeat([]byte("x"), coreMaxMessageBytes-1)
	for i := 0; i < 4; i++ {
		if err := output.sendReliable(chunk); err != nil {
			t.Fatal(err)
		}
	}
	if err := output.sendReliable([]byte("more")); err == nil {
		t.Fatal("byte budget exceeded without failing session")
	}
	go output.writeLoop()
	<-output.writerDone
	for _, input := range []string{strings.Repeat("x", coreMaxMessageBytes) + "\n", "truncated"} {
		if _, err := readCoreLine(bufio.NewReaderSize(strings.NewReader(input), 32)); err == nil {
			t.Fatal("invalid input accepted")
		}
	}
	if line, err := readCoreLine(bufio.NewReader(strings.NewReader("valid\n"))); err != nil || line != "valid\n" {
		t.Fatalf("%q %v", line, err)
	}
	if _, err := readCoreLine(bufio.NewReader(strings.NewReader(""))); err != io.EOF {
		t.Fatal(err)
	}
}

func TestCoreActionAdmissionReservesCancellationCapacity(t *testing.T) {
	left, right := net.Pipe()
	defer right.Close()
	output := newCoreOutput(left, time.Second, 20*time.Millisecond)
	results := make(chan ActionResult, 72)
	handler := func(_ *Action, result ActionResult) { results <- result }
	for i := 0; i < 64; i++ {
		if !dispatchCoreAction(output, &Action{Method: asyncTestDelayMethod}, handler) {
			t.Fatal("early overload")
		}
	}
	if dispatchCoreAction(output, &Action{Method: asyncTestDelayMethod}, handler) {
		t.Fatal("unbounded action admission")
	}
	if !dispatchCoreAction(output, &Action{Method: cancelTestDelayMethod}, handler) {
		t.Fatal("work queue excluded its cancellation")
	}
	for i := 0; i < 65; i++ {
		r := <-results
		r.success(true)
		r.success(true)
	}
	if len(output.actions) != 0 || len(output.controls) != 0 {
		t.Fatal("completion retained action permits")
	}
	output.close()
	go output.writeLoop()
	<-output.writerDone
}

func TestCoreConnectionReplacementCannotReceiveOldResponse(t *testing.T) {
	oldConn, oldPeer := net.Pipe()
	defer oldPeer.Close()
	oldDetach := attachCoreConnection(oldConn)
	defer oldDetach()
	connMu.Lock()
	previous := conn
	connMu.Unlock()
	results := make(chan ActionResult, 1)
	dispatchCoreAction(previous, &Action{Method: asyncTestDelayMethod}, func(_ *Action, r ActionResult) { results <- r })
	oldResult := <-results
	newConn, newPeer := net.Pipe()
	defer newPeer.Close()
	newDetach := attachCoreConnection(newConn)
	defer newDetach()
	oldResult.success("old")
	connMu.Lock()
	current := conn
	connMu.Unlock()
	if err := current.sendReliable([]byte("new")); err != nil {
		t.Fatal(err)
	}
	_ = newPeer.SetReadDeadline(time.Now().Add(time.Second))
	if value, err := bufio.NewReader(newPeer).ReadString('\n'); err != nil || value != "new\n" {
		t.Fatalf("stale session response: %q %v", value, err)
	}
	if previous.bytes.Load() != 0 {
		<-previous.writerDone
		if previous.bytes.Load() != 0 {
			t.Fatal("old session retained bytes")
		}
	}
}

func TestCoreResponseEncodingFailureReleasesActionPermit(t *testing.T) {
	left, right := net.Pipe()
	defer right.Close()
	output := newCoreOutput(left, time.Second, time.Second)
	completed := make(chan struct{})
	dispatchCoreAction(output, &Action{Id: "invalid-result", Method: getIsInitMethod}, func(_ *Action, result ActionResult) { result.success(make(chan int)); close(completed) })
	select {
	case frame := <-output.queue:
		output.bytes.Add(-int64(len(frame)))
		var result ActionResult
		if err := json.Unmarshal(frame, &result); err != nil || result.Code != -1 || result.Id != "invalid-result" {
			t.Fatal("encoding failure did not become an explicit response")
		}
	case <-time.After(time.Second):
		t.Fatal("encoding failure lost callback")
	}
	<-completed
	output.close()
	go output.writeLoop()
	<-output.writerDone
	if len(output.actions) != 0 {
		t.Fatal("encoding failure retained an action permit")
	}
}
