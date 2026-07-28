package main

import (
	"bytes"
	"io"
	"os"
	"path/filepath"
)

func normalizeCursorPayload(raw map[string]any, runtime runtimeEnv) eventEnvelope {
	event := mapEvent(firstString(raw, "hook_event_name", "event"))
	sessionID := firstString(raw, "conversation_id", "session_id")
	session := sessionEnvelope{
		ID:    sessionID,
		CWD:   firstString(raw, "workspace_roots", "cwd"),
		TTY:   runtime.TTY,
		Title: firstString(raw, "title", "conversation_title"),
	}
	transcriptPath := firstString(raw, "transcript_path", "transcriptPath")
	if transcriptPath == "" {
		if root := firstString(raw, "transcript_root"); root != "" && sessionID != "" {
			transcriptPath = buildCursorTranscriptPath(root, sessionID)
		}
	}
	if transcriptPath != "" {
		if tail, err := readCompleteTail(transcriptPath, 1<<20); err == nil {
			context := transcriptContextFromData(tail)
			if context.Title != "" {
				session.Title = context.Title
			}
			session.FirstUserMessage = context.User
			session.LastAssistantMessage = context.Assistant
		}
	}
	return eventEnvelope{
		Schema: 1, HookConfigID: "cursor", Event: event, Session: session,
		Tool: toolEnvelope{Name: firstString(raw, "tool_name", "tool"), Verb: toolVerb(event), Detail: firstString(raw, "command", "detail")},
		Approval: approvalEnvelope{
			RequestID: firstString(raw, "requestId", "request_id", "request-id"),
			Kind:      firstString(raw, "kind", "permission_kind"),
			Preview:   firstString(raw, "preview", "diff_preview"),
			IsNewFile: firstBool(raw, "isNewFile", "is_new_file"),
		},
		Usage: usageFromRaw(raw),
		Env:   envEnvelope{runtime.Docker, runtime.SSH, runtime.Tmux}, SentAt: nowRFC3339(),
	}
}

func toolVerb(event string) string {
	if event == "pre_tool" {
		return "running"
	}
	if event == "post_tool" {
		return "completed"
	}
	return ""
}

func buildCursorTranscriptPath(root, conversationID string) string {
	return filepath.Join(root, filepath.Base(conversationID)+".jsonl")
}

func readCursorTranscript(path string) ([]byte, error) { return os.ReadFile(path) }

func readCompleteTail(path string, limit int64) ([]byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil {
		return nil, err
	}
	if limit <= 0 {
		return []byte{}, nil
	}
	start := info.Size() - limit
	if start < 0 {
		start = 0
	}
	if _, err = file.Seek(start, io.SeekStart); err != nil {
		return nil, err
	}
	data, err := io.ReadAll(io.LimitReader(file, limit))
	if err != nil {
		return nil, err
	}
	if start > 0 {
		if index := bytes.IndexByte(data, '\n'); index >= 0 {
			data = data[index+1:]
		} else {
			return []byte{}, nil
		}
	}
	return data, nil
}
