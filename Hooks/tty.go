package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"runtime"
	"strconv"
	"strings"
	"time"
)

const ttyProbeTimeout = 75 * time.Millisecond

func ttyFromFd(fd uintptr) string {
	link, err := os.Readlink(fmt.Sprintf("/proc/self/fd/%d", fd))
	if err == nil && strings.HasPrefix(link, "/dev/") {
		return link
	}
	if runtime.GOOS == "windows" {
		return ""
	}
	probeContext, cancel := context.WithTimeout(context.Background(), ttyProbeTimeout)
	defer cancel()
	command := exec.CommandContext(probeContext, "tty")
	command.Stdin = os.NewFile(fd, "stdin")
	output, err := command.Output()
	if err != nil {
		return ""
	}
	value := strings.TrimSpace(string(output))
	if strings.HasPrefix(value, "/dev/") {
		return value
	}
	return ""
}

func ttyFromProc() string {
	if runtime.GOOS == "linux" {
		data, err := os.ReadFile("/proc/self/stat")
		if err == nil {
			return ttyFromProcStat(string(data))
		}
	}
	probeContext, cancel := context.WithTimeout(context.Background(), ttyProbeTimeout)
	defer cancel()
	output, err := exec.CommandContext(probeContext, "ps", "-o", "tty=", "-p", strconv.Itoa(os.Getpid())).Output()
	if err != nil {
		return ""
	}
	value := strings.TrimSpace(string(output))
	if value == "" || value == "??" {
		return ""
	}
	if strings.HasPrefix(value, "/dev/") {
		return value
	}
	return "/dev/" + value
}

func ttyFromProcStat(stat string) string {
	closeIndex := strings.LastIndex(stat, ")")
	if closeIndex < 0 {
		return ""
	}
	fields := strings.Fields(stat[closeIndex+1:])
	if len(fields) < 5 {
		return ""
	}
	raw, err := strconv.ParseUint(fields[4], 10, 64)
	if err != nil || raw == 0 {
		return ""
	}
	major := (raw >> 8) & 0xfff
	minor := (raw & 0xff) | ((raw >> 12) & 0xfff00)
	if major >= 136 && major <= 143 {
		return fmt.Sprintf("/dev/pts/%d", minor)
	}
	return fmt.Sprintf("/dev/tty%d", minor)
}
