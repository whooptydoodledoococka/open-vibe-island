package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"strings"
)

type transcriptContext struct {
	Title     string
	User      string
	Assistant string
}

func transcriptContextFromData(data []byte) transcriptContext {
	scanner := bufio.NewScanner(bytes.NewReader(data))
	scanner.Buffer(make([]byte, 64*1024), 2<<20)
	context := transcriptContext{}
	for scanner.Scan() {
		var row any
		if json.Unmarshal(scanner.Bytes(), &row) != nil {
			continue
		}
		if title := recursiveString(row, "title", "thread_title"); title != "" {
			context.Title = title
		}
		role := strings.ToLower(recursiveString(row, "role", "author"))
		content := recursiveContent(row)
		if content == "" {
			continue
		}
		switch role {
		case "user", "human":
			context.User = compactCodexTurnContext(content, 512)
			context.Assistant = ""
		case "assistant", "agent":
			if context.User != "" {
				context.Assistant = compactCodexTurnContext(content, 512)
			}
		}
	}
	return context
}

func recursiveString(value any, keys ...string) string {
	var visit func(any) string
	visit = func(current any) string {
		switch typed := current.(type) {
		case map[string]any:
			for _, key := range keys {
				if text, ok := typed[key].(string); ok && strings.TrimSpace(text) != "" {
					return text
				}
			}
			for _, nested := range typed {
				if text := visit(nested); text != "" {
					return text
				}
			}
		case []any:
			for _, nested := range typed {
				if text := visit(nested); text != "" {
					return text
				}
			}
		}
		return ""
	}
	return visit(value)
}

func recursiveContent(value any) string {
	switch typed := value.(type) {
	case map[string]any:
		for _, key := range []string{"content", "message", "text"} {
			if raw, ok := typed[key]; ok {
				if content := contentString(raw); content != "" {
					return content
				}
			}
		}
		for _, nested := range typed {
			if content := recursiveContent(nested); content != "" {
				return content
			}
		}
	case []any:
		var pieces []string
		for _, nested := range typed {
			if content := recursiveContent(nested); content != "" {
				pieces = append(pieces, content)
			}
		}
		return strings.Join(pieces, " ")
	}
	return ""
}

func contentString(value any) string {
	switch typed := value.(type) {
	case string:
		return strings.TrimSpace(typed)
	case []any:
		var pieces []string
		for _, item := range typed {
			if text := contentString(item); text != "" {
				pieces = append(pieces, text)
			}
		}
		return strings.Join(pieces, " ")
	case map[string]any:
		for _, key := range []string{"text", "content", "message"} {
			if raw, ok := typed[key]; ok {
				if text := contentString(raw); text != "" {
					return text
				}
			}
		}
	}
	return ""
}

func exactContextBytes(context transcriptContext) []byte {
	var buffer bytes.Buffer
	if context.User != "" {
		encoded, _ := json.Marshal(map[string]string{"role": "user", "content": context.User})
		buffer.Write(encoded)
		buffer.WriteByte('\n')
	}
	if context.Assistant != "" {
		encoded, _ := json.Marshal(map[string]string{"role": "assistant", "content": context.Assistant})
		buffer.Write(encoded)
		buffer.WriteByte('\n')
	}
	return buffer.Bytes()
}
