package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestHookEventDerivesSourceAndRecordsRunState(t *testing.T) {
	state := t.TempDir()
	t.Setenv("ORBIT_STATE_DIR", state)
	socket := fmt.Sprintf("/tmp/orbit-hook-completion-%d.sock", os.Getpid())
	_ = os.Remove(socket)
	defer os.Remove(socket)
	t.Setenv("ORBIT_SOCKET_PATH", socket)
	listener, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	received := make(chan eventEnvelope, 1)
	go func() {
		connection, acceptErr := listener.Accept()
		if acceptErr != nil {
			return
		}
		defer connection.Close()
		var event eventEnvelope
		_ = json.NewDecoder(connection).Decode(&event)
		received <- event
	}()
	input := strings.NewReader(`{"hookConfigId":"cursor","hook_event_name":"sessionStart","conversation_id":"session-1"}`)
	if err := runHookEvent("event", input, &bytes.Buffer{}, runtimeEnv{}); err != nil {
		t.Fatal(err)
	}
	select {
	case event := <-received:
		if event.HookConfigID != "cursor" || event.Event != "session.start" {
			t.Fatalf("unexpected event: %+v", event)
		}
	case <-time.After(time.Second):
		t.Fatal("event was not forwarded")
	}
	for _, name := range []string{"orbit.pid", "orbit.lastrun"} {
		if data, readErr := os.ReadFile(filepath.Join(state, name)); readErr != nil || len(bytes.TrimSpace(data)) == 0 {
			t.Fatalf("missing %s: %v", name, readErr)
		}
	}
}

func TestCursorApprovalSentinelControlsCLIResponse(t *testing.T) {
	state := t.TempDir()
	t.Setenv("ORBIT_STATE_DIR", state)
	t.Setenv("ORBIT_SOCKET_PATH", filepath.Join(state, "missing.sock"))
	payload := `{"hook_event_name":"permissionRequest","conversation_id":"session-1","request_id":"request-1"}`
	if err := os.WriteFile(filepath.Join(state, "orbit-cursor-approval-always"), []byte("1"), 0o600); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := runHookEvent("cursor", strings.NewReader(payload), &output, runtimeEnv{}); err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	if err := json.Unmarshal(output.Bytes(), &response); err != nil {
		t.Fatalf("missing response: %v; output=%q", err, output.String())
	}
	if response["decision"] != "allow" || response["requestId"] != "request-1" {
		t.Fatalf("unexpected response: %#v", response)
	}
	if err := os.Remove(filepath.Join(state, "orbit-cursor-approval-always")); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(state, "orbit-cursor-approval-never"), []byte("1"), 0o600); err != nil {
		t.Fatal(err)
	}
	output.Reset()
	if err := runHookEvent("cursor", strings.NewReader(payload), &output, runtimeEnv{}); err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(output.Bytes(), &response); err != nil || response["decision"] != "deny" {
		t.Fatalf("unexpected deny response: %#v err=%v", response, err)
	}
}

func TestCodexNormalizationAdmitsTranscriptAndCapturesExactContext(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rollout-session.jsonl")
	transcript := strings.Join([]string{
		`{"type":"thread","payload":{"title":"Fix launch","message":{"role":"user","content":"old question"}}}`,
		`{"type":"message","payload":{"role":"assistant","content":"old answer"}}`,
		`{"type":"message","payload":{"role":"user","content":"current question"}}`,
		`{"type":"message","payload":{"role":"assistant","content":"current answer"}}`,
	}, "\n") + "\n"
	if err := os.WriteFile(path, []byte(transcript), 0o600); err != nil {
		t.Fatal(err)
	}
	event := normalizeCodexPayload(map[string]any{
		"type": "session_start", "thread-id": "thread-1", "transcript_path": path,
	}, runtimeEnv{})
	if event.Session.Title != "Fix launch" {
		t.Fatalf("title=%q", event.Session.Title)
	}
	if event.Session.FirstUserMessage != "current question" || event.Session.LastAssistantMessage != "current answer" {
		t.Fatalf("context=%+v", event.Session)
	}
	context, err := readExactCodexTurnContext(path)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(context, []byte("old question")) || !bytes.Contains(context, []byte("current question")) {
		t.Fatalf("context was not exact: %s", context)
	}
}

func TestCodexTranscriptAdmissionAndRuneSafeCompaction(t *testing.T) {
	if admittedCodexTranscript("/tmp/notes.jsonl") || !admittedCodexTranscript("/tmp/rollout-1.jsonl") {
		t.Fatal("admission filter mismatch")
	}
	if got := compactCodexTurnContext("  hello   世界  ", 8); got != "hello 世界" {
		t.Fatalf("got %q", got)
	}
	if !shouldAttachCodexTitle("session.start") || shouldAttachCodexTitle("pre_tool") {
		t.Fatal("title attachment policy mismatch")
	}
}

func TestCursorNormalizationReadsTranscriptTail(t *testing.T) {
	path := filepath.Join(t.TempDir(), "cursor-session.jsonl")
	body := `{"role":"user","content":"question"}` + "\n" + `{"role":"assistant","content":"answer"}` + "\n"
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	event := normalizeCursorPayload(map[string]any{
		"hook_event_name": "sessionStart", "conversation_id": "cursor-1", "transcript_path": path,
	}, runtimeEnv{})
	if event.Session.FirstUserMessage != "question" || event.Session.LastAssistantMessage != "answer" {
		t.Fatalf("context=%+v", event.Session)
	}
}

func TestStatuslineReadsUsageLimitCache(t *testing.T) {
	state := t.TempDir()
	t.Setenv("ORBIT_STATE_DIR", state)
	if err := os.WriteFile(filepath.Join(state, "orbit-rl.json"), []byte(`{"limitReached":true,"resetAt":"2030-01-01T00:00:00Z"}`), 0o600); err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := runStatusline(strings.NewReader("{}"), &output); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "limit reached") || !strings.Contains(output.String(), "2030-01-01T00:00:00Z") {
		t.Fatalf("status=%q", output.String())
	}
}
