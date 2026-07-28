package main

import (
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"reflect"

	"testing"
	"time"
)

func TestParsePortsFiltersInvalidValuesAndDeduplicates(t *testing.T) {
	got := parsePorts(" 8642,9000,8642,0,65536,nope ")
	want := []int{8642, 9000}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

func TestMergeManagedHookSetIsJSONCTolerantAndIdempotent(t *testing.T) {
	input := []byte("{\n // keep user config\n \"theme\": \"dark\",\n \"hooks\": {\"user\": {\"command\": \"custom\",},},\n}")
	once, err := mergeManagedHookSet(input, "/tmp/orbit-hook")
	if err != nil {
		t.Fatal(err)
	}
	twice, err := mergeManagedHookSet(once, "/tmp/orbit-hook")
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(once, twice) {
		t.Fatal("second merge changed canonical config")
	}
	var decoded map[string]any
	if err := json.Unmarshal(once, &decoded); err != nil {
		t.Fatal(err)
	}
	hooks := decoded["hooks"].(map[string]any)
	if _, ok := hooks["user"]; !ok {
		t.Fatal("user hook was removed")
	}
	if _, ok := hooks["orbit"]; !ok {
		t.Fatal("managed hook missing")
	}
}

func TestAtomicManagedConfigWriteIsIdempotent(t *testing.T) {
	path := filepath.Join(t.TempDir(), "settings.json")
	if err := os.WriteFile(path, []byte("{\"user\":true}"), 0o600); err != nil {
		t.Fatal(err)
	}
	changed, err := writeManagedConfig(path, "/tmp/orbit-hook")
	if err != nil || !changed {
		t.Fatalf("first write: changed=%v err=%v", changed, err)
	}
	before, _ := os.ReadFile(path)
	changed, err = writeManagedConfig(path, "/tmp/orbit-hook")
	if err != nil || changed {
		t.Fatalf("second write: changed=%v err=%v", changed, err)
	}
	after, _ := os.ReadFile(path)
	if !reflect.DeepEqual(before, after) {
		t.Fatal("idempotent write changed bytes")
	}
}

func TestFanOutDeliversToUnixAndEveryLiveTCPListener(t *testing.T) {
	t.Setenv("ORBIT_DOCKER_HOST", "127.0.0.1")
	socketPath := fmt.Sprintf("/tmp/orbit-hook-test-%d-%d.sock", os.Getpid(), time.Now().UnixNano())
	defer os.Remove(socketPath)
	unixListener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatal(err)
	}
	defer unixListener.Close()
	tcpListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer tcpListener.Close()
	payload := []byte(`{"schema":1}`)
	received := make(chan []byte, 2)
	accept := func(listener net.Listener) {
		connection, acceptErr := listener.Accept()
		if acceptErr != nil {
			return
		}
		defer connection.Close()
		buffer := make([]byte, 128)
		count, _ := connection.Read(buffer)
		received <- buffer[:count]
	}
	go accept(unixListener)
	go accept(tcpListener)
	port := tcpListener.Addr().(*net.TCPAddr).Port
	fanOut(payload, socketPath, []int{port}, 100*time.Millisecond, 300*time.Millisecond)
	for range 2 {
		select {
		case got := <-received:
			if string(got) != string(payload)+"\n" {
				t.Fatalf("unexpected payload %q", got)
			}
		case <-time.After(time.Second):
			t.Fatal("listener did not receive payload")
		}
	}
}

func TestNormalizePayloadsProduceCanonicalEnvelope(t *testing.T) {
	codex := normalizeCodexPayload(map[string]any{"type": "agent-turn-complete", "thread-id": "abc", "cwd": "/tmp/work"}, runtimeEnv{TTY: "/dev/ttys001"})
	if codex.Schema != 1 || codex.HookConfigID != "codex" || codex.Event != "stop" || codex.Session.ID != "abc" {
		t.Fatalf("unexpected codex envelope: %+v", codex)
	}
	cursor := normalizeCursorPayload(map[string]any{"hook_event_name": "preToolUse", "conversation_id": "xyz", "tool_name": "Shell"}, runtimeEnv{})
	if cursor.HookConfigID != "cursor" || cursor.Event != "pre_tool" || cursor.Tool.Name != "Shell" {
		t.Fatalf("unexpected cursor envelope: %+v", cursor)
	}
}

func TestReadCompleteTailReturnsWholeLinesWithinLimit(t *testing.T) {
	path := filepath.Join(t.TempDir(), "transcript.jsonl")
	if err := os.WriteFile(path, []byte("one\ntwo\nthree\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	got, err := readCompleteTail(path, 8)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != "three\n" {
		t.Fatalf("got %q", got)
	}
}

func TestTTYProcessFallbackParser(t *testing.T) {
	if got := ttyFromProcStat("1 (shell) S 0 1 1 34817 1"); got != "/dev/pts/1" {
		t.Fatalf("got %q", got)
	}
	if got := ttyFromProcStat("malformed"); got != "" {
		t.Fatalf("got %q", got)
	}
}

func TestStdoutPolicyOnlyAllowsInteractiveSources(t *testing.T) {
	if !shouldPrintCLIResponse("claude", "permission.request") {
		t.Fatal("interactive response suppressed")
	}
	if shouldPrintCLIResponse("gemini", "post_tool") {
		t.Fatal("fire-and-forget response printed")
	}
}
