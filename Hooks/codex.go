package main

import (
	"path/filepath"
	"strings"
	"unicode/utf8"
)

func normalizeCodexPayload(raw map[string]any, runtime runtimeEnv) eventEnvelope {
	eventName := firstString(raw, "type", "hook_event_name", "event")
	event := mapEvent(eventName)
	session := sessionEnvelope{
		ID:                   firstString(raw, "thread-id", "thread_id", "session_id"),
		CWD:                  firstString(raw, "cwd", "working_directory"),
		TTY:                  runtime.TTY,
		Title:                firstString(raw, "title", "thread_title"),
		FirstUserMessage:     compactCodexTurnContext(firstString(raw, "prompt", "user_message"), 512),
		LastAssistantMessage: compactCodexTurnContext(firstString(raw, "last-assistant-message", "assistant_message"), 512),
	}
	transcriptPath := firstString(raw, "transcript_path", "transcriptPath")
	if admittedCodexTranscript(transcriptPath) {
		if tail, err := readCompleteTail(transcriptPath, 1<<20); err == nil {
			context := transcriptContextFromData(tail)
			if shouldAttachCodexTitle(event) && context.Title != "" {
				session.Title = context.Title
			}
			if context.User != "" {
				session.FirstUserMessage = context.User
			}
			if context.Assistant != "" {
				session.LastAssistantMessage = context.Assistant
			}
		}
	}
	approval := approvalEnvelope{
		RequestID: firstString(raw, "requestId", "request_id", "request-id"),
		Kind:      firstString(raw, "kind", "permission_kind"),
		Preview:   firstString(raw, "preview", "diff_preview"),
		IsNewFile: firstBool(raw, "isNewFile", "is_new_file"),
	}
	return eventEnvelope{
		Schema: 1, HookConfigID: "codex", Event: event, Session: session,
		Tool:     toolEnvelope{Name: firstString(raw, "tool_name", "tool"), Verb: toolVerb(event), Detail: firstString(raw, "command", "detail")},
		Approval: approval, Usage: usageFromRaw(raw),
		Env: envEnvelope{runtime.Docker, runtime.SSH, runtime.Tmux}, SentAt: nowRFC3339(),
	}
}

func admittedCodexTranscript(path string) bool {
	base := filepath.Base(path)
	return path != "" && strings.HasPrefix(base, "rollout-") && filepath.Ext(base) == ".jsonl"
}

func codexSessionRoots(home string) []string {
	return []string{filepath.Join(home, ".codex", "sessions")}
}

func codexSessionIndexPaths(home string) []string {
	return []string{
		filepath.Join(home, ".codex", "session_index.jsonl"),
		filepath.Join(home, ".codex", "sessions", "session_index.jsonl"),
	}
}

func readCodexThreadTitleAtPath(path string) string {
	tail, err := readCompleteTail(path, 1<<20)
	if err != nil {
		return ""
	}
	return codexThreadTitleFromTail(tail)
}

func readCodexThreadTitle(path string) string { return readCodexThreadTitleAtPath(path) }

func codexThreadTitleFromTail(data []byte) string {
	return transcriptContextFromData(data).Title
}

func readExactCodexTurnContext(path string) ([]byte, error) {
	tail, err := readCompleteTail(path, 1<<20)
	if err != nil {
		return nil, err
	}
	return exactContextBytes(transcriptContextFromData(tail)), nil
}

func compactCodexTurnContext(value string, limit int) string {
	value = strings.Join(strings.Fields(value), " ")
	if limit < 1 || utf8.RuneCountInString(value) <= limit {
		return value
	}
	runes := []rune(value)
	return string(runes[:limit])
}

func shouldAttachCodexTitle(event string) bool {
	return event == "session.start" || event == "notification"
}

func mapEvent(value string) string {
	normalized := strings.ToLower(strings.ReplaceAll(value, "-", "_"))
	switch normalized {
	case "session_start", "sessionstart":
		return "session.start"
	case "pre_tool", "pretooluse", "before_tool":
		return "pre_tool"
	case "post_tool", "posttooluse", "after_tool":
		return "post_tool"
	case "permission_request", "permissionrequest":
		return "permission.request"
	case "agent_turn_complete", "stop", "session_end":
		return "stop"
	case "notification":
		return "notification"
	default:
		return "notification"
	}
}

func firstString(values map[string]any, keys ...string) string {
	for _, key := range keys {
		switch value := values[key].(type) {
		case string:
			if value != "" {
				return value
			}
		case []string:
			if len(value) > 0 {
				return value[0]
			}
		case []any:
			for _, item := range value {
				if text, ok := item.(string); ok && text != "" {
					return text
				}
			}
		}
	}
	return ""
}

func firstBool(values map[string]any, keys ...string) bool {
	for _, key := range keys {
		if value, ok := values[key].(bool); ok {
			return value
		}
	}
	return false
}
