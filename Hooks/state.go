package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

func sourceFromPayload(requested string, raw map[string]any) string {
	source := strings.ToLower(strings.TrimSpace(requested))
	if source == "" || source == "event" || source == "hook-event" {
		source = strings.ToLower(firstString(raw, "hookConfigId", "hook_config_id", "source", "agent"))
	}
	switch source {
	case "claude", "codex", "cursor", "gemini", "kimi", "opencode":
		return source
	}
	if firstString(raw, "conversation_id") != "" {
		return "cursor"
	}
	return "codex"
}

func stateDirectory() string {
	if value := strings.TrimSpace(os.Getenv("ORBIT_STATE_DIR")); value != "" {
		return value
	}
	return "/tmp"
}

func statePath(name string) string { return filepath.Join(stateDirectory(), name) }

func recordRunState() {
	directory := stateDirectory()
	if os.MkdirAll(directory, 0o700) != nil {
		return
	}
	_ = os.WriteFile(filepath.Join(directory, "orbit.pid"), []byte(strconv.Itoa(os.Getpid())+"\n"), 0o600)
	_ = os.WriteFile(filepath.Join(directory, "orbit.lastrun"), []byte(nowRFC3339()+"\n"), 0o600)
	usagePath := filepath.Join(directory, "orbit-rl.json")
	if _, err := os.Stat(usagePath); os.IsNotExist(err) {
		data, _ := json.Marshal(usageEnvelope{})
		_ = os.WriteFile(usagePath, append(data, '\n'), 0o600)
	}
}

func persistUsageCache(usage usageEnvelope) {
	if !usage.Present {
		return
	}
	data, err := json.Marshal(usage)
	if err != nil {
		return
	}
	_ = os.WriteFile(statePath("orbit-rl.json"), append(data, '\n'), 0o600)
}

func readUsageCache() usageEnvelope {
	data, err := readCompleteTail(statePath("orbit-rl.json"), 64<<10)
	if err != nil {
		return usageEnvelope{}
	}
	var usage usageEnvelope
	_ = json.Unmarshal(data, &usage)
	return usage
}

func cursorApprovalDecision() string {
	always := fileExists(statePath("orbit-cursor-approval-always"))
	never := fileExists(statePath("orbit-cursor-approval-never"))
	if never || (always && never) {
		return "deny"
	}
	if always {
		return "allow"
	}
	return ""
}

func cliResponse(source string, event eventEnvelope) any {
	if source != "cursor" || event.Event != "permission.request" {
		return nil
	}
	decision := cursorApprovalDecision()
	if decision == "" {
		return nil
	}
	return map[string]any{
		"decision":  decision,
		"requestId": event.Approval.RequestID,
	}
}

func usageStatusline(usage usageEnvelope) string {
	if !usage.LimitReached {
		return "Orbit connected"
	}
	if usage.ResetAt != nil && *usage.ResetAt != "" {
		return "Orbit • limit reached • resets " + *usage.ResetAt
	}
	return "Orbit • limit reached"
}

func usageFromRaw(raw map[string]any) usageEnvelope {
	usage := usageEnvelope{}
	if value, ok := raw["limitReached"].(bool); ok {
		usage.LimitReached, usage.Present = value, true
	}
	if value, ok := raw["limit_reached"].(bool); ok {
		usage.LimitReached, usage.Present = value, true
	}
	if reset := firstString(raw, "resetAt", "reset_at"); reset != "" {
		usage.ResetAt, usage.Present = &reset, true
	}
	if nested, ok := raw["usage"].(map[string]any); ok {
		nestedUsage := usageFromRaw(nested)
		if nestedUsage.Present {
			usage = nestedUsage
		}
	}
	return usage
}
