package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const dialTimeout = 40 * time.Millisecond
const fanOutWaitLimit = 180 * time.Millisecond

func runForward(input io.Reader, env runtimeEnv) error {
	payload, err := io.ReadAll(io.LimitReader(input, 8<<20))
	if err != nil || len(payload) == 0 {
		return nil
	}
	if !json.Valid(bytes.TrimSpace(payload)) {
		return nil
	}
	fanOut(payload, socketPath(), parsePorts(os.Getenv("ORBIT_HOOK_PORTS")), dialTimeout, fanOutWaitLimit)
	return nil
}

func parsePorts(value string) []int {
	seen := map[int]bool{}
	var ports []int
	for _, field := range strings.Split(value, ",") {
		port, err := strconv.Atoi(strings.TrimSpace(field))
		if err != nil || port < 1 || port > 65535 || seen[port] {
			continue
		}
		seen[port] = true
		ports = append(ports, port)
	}
	return ports
}

func fanOut(payload []byte, unixPath string, ports []int, timeout, waitLimit time.Duration) {
	framed := append(append([]byte(nil), payload...), '\n')
	targets := make([]struct{ network, address string }, 0, len(ports)+1)
	if unixPath != "" {
		targets = append(targets, struct{ network, address string }{"unix", unixPath})
	}
	host := detectDockerHost()
	for _, port := range ports {
		targets = append(targets, struct{ network, address string }{"tcp", net.JoinHostPort(host, strconv.Itoa(port))})
	}
	var group sync.WaitGroup
	group.Add(len(targets))
	for _, target := range targets {
		go func(network, address string) {
			defer group.Done()
			dialSocket(network, address, framed, timeout)
		}(target.network, target.address)
	}
	complete := make(chan struct{})
	go func() { group.Wait(); close(complete) }()
	select {
	case <-complete:
	case <-time.After(waitLimit):
	}
}

func dialSocket(network, address string, payload []byte, timeout time.Duration) {
	connection, err := net.DialTimeout(network, address, timeout)
	if err != nil {
		return
	}
	defer connection.Close()
	_ = connection.SetWriteDeadline(time.Now().Add(timeout))
	_, _ = connection.Write(payload)
}

func dialTCPSingle(host string, port int, payload []byte, timeout time.Duration) {
	dialSocket("tcp", net.JoinHostPort(host, strconv.Itoa(port)), payload, timeout)
}

func getDefaultGateway() string {
	file, err := os.Open("/proc/net/route")
	if err != nil {
		return ""
	}
	defer file.Close()
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 3 || fields[1] != "00000000" {
			continue
		}
		raw, err := strconv.ParseUint(fields[2], 16, 32)
		if err != nil {
			continue
		}
		return net.IPv4(byte(raw), byte(raw>>8), byte(raw>>16), byte(raw>>24)).String()
	}
	return ""
}
