package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"time"
)

type runtimeEnv struct {
	TTY    string
	Docker bool
	SSH    bool
	Tmux   bool
}

type eventEnvelope struct {
	Schema       int              `json:"schema"`
	HookConfigID string           `json:"hookConfigId"`
	Event        string           `json:"event"`
	Session      sessionEnvelope  `json:"session"`
	Tool         toolEnvelope     `json:"tool,omitempty"`
	Approval     approvalEnvelope `json:"approval,omitempty"`
	Usage        usageEnvelope    `json:"usage,omitempty"`
	Env          envEnvelope      `json:"env"`
	SentAt       string           `json:"sentAt"`
}

type sessionEnvelope struct {
	ID                   string `json:"id"`
	CWD                  string `json:"cwd,omitempty"`
	TTY                  string `json:"tty,omitempty"`
	Title                string `json:"title,omitempty"`
	FirstUserMessage     string `json:"firstUserMessage,omitempty"`
	LastAssistantMessage string `json:"lastAssistantMessage,omitempty"`
}

type toolEnvelope struct {
	Name   string `json:"name,omitempty"`
	Verb   string `json:"verb,omitempty"`
	Detail string `json:"detail,omitempty"`
}

type approvalEnvelope struct {
	RequestID string `json:"requestId,omitempty"`
	Kind      string `json:"kind,omitempty"`
	Preview   string `json:"preview,omitempty"`
	IsNewFile bool   `json:"isNewFile,omitempty"`
}

type usageEnvelope struct {
	LimitReached bool    `json:"limitReached"`
	ResetAt      *string `json:"resetAt"`
	Present      bool    `json:"-"`
}

type envEnvelope struct {
	Docker bool `json:"docker"`
	SSH    bool `json:"ssh"`
	Tmux   bool `json:"tmux"`
}

func main() {
	args := os.Args[1:]
	command := "event"
	if len(args) > 0 {
		command = args[0]
	}
	var err error
	switch command {
	case "setup":
		err = runSetup(args[1:])
	case "forward":
		err = runForward(os.Stdin, collectEnv())
	case "statusline":
		err = runStatusline(os.Stdin, os.Stdout)
	default:
		err = runHookEvent(command, os.Stdin, os.Stdout, collectEnv())
	}
	if err != nil && command == "setup" {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func collectEnv() runtimeEnv {
	tty := ttyFromFd(os.Stdin.Fd())
	if tty == "" {
		tty = ttyFromProc()
	}
	return runtimeEnv{
		TTY:    tty,
		Docker: os.Getenv("container") != "" || fileExists("/.dockerenv"),
		SSH:    os.Getenv("SSH_CONNECTION") != "" || os.Getenv("SSH_CLIENT") != "",
		Tmux:   os.Getenv("TMUX") != "",
	}
}

func detectDockerHost() string {
	if value := strings.TrimSpace(os.Getenv("ORBIT_DOCKER_HOST")); value != "" {
		return value
	}
	if !collectEnv().Docker {
		return "127.0.0.1"
	}
	if gateway := getDefaultGateway(); gateway != "" {
		return gateway
	}
	return "host.docker.internal"
}

func runHookEvent(source string, input io.Reader, output io.Writer, env runtimeEnv) error {
	payload, err := io.ReadAll(io.LimitReader(input, 8<<20))
	if err != nil || len(payload) == 0 {
		return nil
	}
	var raw map[string]any
	if json.Unmarshal(payload, &raw) != nil {
		return nil
	}
	source = sourceFromPayload(source, raw)
	var event eventEnvelope
	if source == "cursor" {
		event = normalizeCursorPayload(raw, env)
	} else {
		event = normalizeCodexPayload(raw, env)
		event.HookConfigID = source
	}
	encoded, err := json.Marshal(event)
	if err != nil {
		return nil
	}
	recordRunState()
	persistUsageCache(event.Usage)
	fanOut(encoded, socketPath(), parsePorts(os.Getenv("ORBIT_HOOK_PORTS")), dialTimeout, fanOutWaitLimit)
	if response := cliResponse(source, event); shouldPrintCLIResponse(source, event.Event) && response != nil {
		printCLIResponse(output, response)
	}
	return nil
}

func runStatusline(input io.Reader, output io.Writer) error {
	_, _ = io.Copy(io.Discard, io.LimitReader(input, 1<<20))
	_, err := fmt.Fprintln(output, usageStatusline(readUsageCache()))
	return err
}

func shouldPrintCLIResponse(source, event string) bool {
	if event != "permission.request" {
		return false
	}
	switch strings.ToLower(source) {
	case "claude", "codex", "cursor", "kimi", "opencode":
		return true
	default:
		return false
	}
}

func printCLIResponse(output io.Writer, response any) {
	if response == nil {
		return
	}
	encoded, err := json.Marshal(response)
	if err == nil {
		_, _ = output.Write(append(encoded, '\n'))
	}
}

func fileExists(path string) bool { _, err := os.Stat(path); return err == nil }
func socketPath() string {
	if value := strings.TrimSpace(os.Getenv("ORBIT_SOCKET_PATH")); value != "" {
		return value
	}
	return "/tmp/orbit.sock"
}
func nowRFC3339() string { return time.Now().UTC().Format(time.RFC3339Nano) }
