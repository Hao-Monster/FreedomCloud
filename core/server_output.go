//go:build !cgo

package main

import (
	"errors"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

const (
	coreMaxMessageBytes = 1024 * 1024 // matches Agent's frame budget
	coreMaxOutputBytes  = 4 * coreMaxMessageBytes
	coreWriteTimeout    = 5 * time.Second
	coreEnqueueTimeout  = 2 * time.Second
)

type coreOutput struct {
	connection                   net.Conn
	queue                        chan []byte
	actions                      chan struct{}
	controls                     chan struct{}
	done                         chan struct{}
	writerDone                   chan struct{}
	once                         sync.Once
	admission                    sync.Mutex
	closed                       bool
	senders                      sync.WaitGroup
	onClose                      func()
	bytes                        atomic.Int64
	writeTimeout, enqueueTimeout time.Duration
}

func newCoreOutput(c net.Conn, writeTimeout, enqueueTimeout time.Duration) *coreOutput {
	return &coreOutput{connection: c, queue: make(chan []byte, 256), actions: make(chan struct{}, 64), controls: make(chan struct{}, 8), done: make(chan struct{}), writerDone: make(chan struct{}), writeTimeout: writeTimeout, enqueueTimeout: enqueueTimeout}
}

func (o *coreOutput) close() {
	o.once.Do(func() {
		o.admission.Lock()
		o.closed = true
		close(o.done)
		o.admission.Unlock()
		_ = o.connection.Close() // never waits for a mutex held across Write
		if o.onClose != nil {
			o.onClose()
		}
	})
}

func (o *coreOutput) beginSend() bool {
	o.admission.Lock()
	defer o.admission.Unlock()
	if o.closed {
		return false
	}
	o.senders.Add(1)
	return true
}

func (o *coreOutput) frame(data []byte) ([]byte, error) {
	if len(data)+1 > coreMaxMessageBytes {
		return nil, errors.New("Core output exceeds message limit")
	}
	size := int64(len(data) + 1)
	for {
		used := o.bytes.Load()
		if used+size > coreMaxOutputBytes {
			return nil, errors.New("Core output byte budget exhausted")
		}
		if o.bytes.CompareAndSwap(used, used+size) {
			break
		}
	}
	frame := make([]byte, len(data)+1)
	copy(frame, data)
	frame[len(data)] = '\n'
	return frame, nil
}

func (o *coreOutput) sendStream(data []byte) {
	if !o.beginSend() {
		return
	}
	defer o.senders.Done()
	// Leave room for replies. Stream drops are an explicit protocol property.
	if len(o.queue) >= cap(o.queue)-32 {
		return
	}
	frame, err := o.frame(data)
	if err != nil {
		return
	}
	select {
	case <-o.done:
		o.bytes.Add(-int64(len(frame)))
	case o.queue <- frame:
	default:
		o.bytes.Add(-int64(len(frame)))
	}
}

func (o *coreOutput) sendReliable(data []byte) error {
	if !o.beginSend() {
		return net.ErrClosed
	}
	defer o.senders.Done()
	frame, err := o.frame(data)
	if err != nil {
		o.close()
		return err
	}
	timer := time.NewTimer(o.enqueueTimeout)
	defer timer.Stop()
	select {
	case <-o.done:
		o.bytes.Add(-int64(len(frame)))
		return net.ErrClosed
	case o.queue <- frame:
		return nil
	case <-timer.C:
		o.bytes.Add(-int64(len(frame)))
		o.close()
		return errors.New("Core response consumer stalled")
	}
}

func (o *coreOutput) writeLoop() {
	defer close(o.writerDone)
	defer func() {
		o.senders.Wait()
		for {
			select {
			case frame := <-o.queue:
				o.bytes.Add(-int64(len(frame)))
			default:
				return
			}
		}
	}()
	for {
		select {
		case <-o.done:
			return
		case frame := <-o.queue:
			err := o.connection.SetWriteDeadline(time.Now().Add(o.writeTimeout))
			if err == nil {
				remaining := frame
				for len(remaining) > 0 {
					var n int
					n, err = o.connection.Write(remaining)
					if err != nil {
						break
					}
					if n == 0 {
						err = io.ErrShortWrite
						break
					}
					remaining = remaining[n:]
				}
			}
			o.bytes.Add(-int64(len(frame)))
			if err != nil {
				o.close()
				return
			}
		}
	}
}
