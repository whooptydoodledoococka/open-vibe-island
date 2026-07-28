package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestConfigureCLIsOnlyTouchesInstalledConfigsAndPreservesExistingValues(t *testing.T) {
	home := t.TempDir()
	t.Setenv("PATH", t.TempDir())
	for _, directory := range []string{".claude", ".cursor"} {
		if err := os.MkdirAll(filepath.Join(home, directory), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	claudePath := filepath.Join(home, ".claude", "settings.json")
	if err := os.WriteFile(claudePath, []byte(`{"theme":"dark","hooks":{"user":{"command":"mine"}}}`), 0o640); err != nil {
		t.Fatal(err)
	}
	changed, err := configureCLIs(home, "/tmp/orbit-hook")
	if err != nil {
		t.Fatal(err)
	}
	if len(changed) != 2 {
		t.Fatalf("changed=%v", changed)
	}
	info, err := os.Stat(claudePath)
	if err != nil || info.Mode().Perm() != 0o640 {
		t.Fatalf("mode=%v err=%v", info.Mode().Perm(), err)
	}
	data, err := os.ReadFile(claudePath)
	if err != nil {
		t.Fatal(err)
	}
	var root map[string]any
	if err := json.Unmarshal(data, &root); err != nil {
		t.Fatal(err)
	}
	if root["theme"] != "dark" {
		t.Fatal("user value removed")
	}
	hooks := root["hooks"].(map[string]any)
	if hooks["user"] == nil || hooks["orbit"] == nil {
		t.Fatalf("hooks=%#v", hooks)
	}
	if _, err := os.Stat(filepath.Join(home, ".gemini", "settings.json")); !os.IsNotExist(err) {
		t.Fatal("uninstalled config was created")
	}
}

func TestConflictingCursorApprovalSentinelsFailClosed(t *testing.T) {
	state := t.TempDir()
	t.Setenv("ORBIT_STATE_DIR", state)
	for _, name := range []string{"orbit-cursor-approval-always", "orbit-cursor-approval-never"} {
		if err := os.WriteFile(filepath.Join(state, name), []byte("1"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	if decision := cursorApprovalDecision(); decision != "deny" {
		t.Fatalf("decision=%q", decision)
	}
}

func TestMalformedHookAndForwardInputExitSilently(t *testing.T) {
	t.Setenv("ORBIT_SOCKET_PATH", filepath.Join(t.TempDir(), "missing.sock"))
	var output bytes.Buffer
	started := time.Now()
	if err := runHookEvent("cursor", bytes.NewBufferString("not-json"), &output, runtimeEnv{}); err != nil {
		t.Fatal(err)
	}
	if err := runForward(bytes.NewBufferString("not-json"), runtimeEnv{}); err != nil {
		t.Fatal(err)
	}
	if output.Len() != 0 {
		t.Fatalf("output=%q", output.String())
	}
	if time.Since(started) > 500*time.Millisecond {
		t.Fatal("malformed input blocked")
	}
}

func TestFanOutWaitLimitBoundsDeadListeners(t *testing.T) {
	started := time.Now()
	fanOut([]byte(`{"schema":1}`), "/tmp/orbit-missing.sock", []int{1, 2, 3}, 25*time.Millisecond, 60*time.Millisecond)
	if elapsed := time.Since(started); elapsed > 200*time.Millisecond {
		t.Fatalf("fan-out blocked for %s", elapsed)
	}
}
