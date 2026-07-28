package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
)

type cliConfig struct{ directory, binary, config string }

func runSetup(args []string) error {
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	if len(args) == 2 && args[0] == "--config" {
		_, err = writeManagedConfig(args[1], executable)
		return err
	}
	_, err = configureCLIs(home, executable)
	return err
}

func configureCLIs(home, hookBinary string) ([]string, error) {
	configs := []cliConfig{
		{".claude", "claude", ".claude/settings.json"},
		{".cursor", "cursor", ".cursor/hooks.json"},
		{".gemini", "gemini", ".gemini/settings.json"},
		{".kimi", "kimi", ".kimi/settings.json"},
		{".config/opencode", "opencode", ".config/opencode/opencode.json"},
		{".codex", "codex", ".codex/hooks.json"},
	}
	var changed []string
	for _, config := range configs {
		if !dirOrBinaryExists(filepath.Join(home, config.directory), config.binary) {
			continue
		}
		path := filepath.Join(home, config.config)
		didChange, err := writeManagedConfig(path, hookBinary)
		if err != nil {
			return changed, err
		}
		if didChange {
			changed = append(changed, path)
		}
	}
	return changed, nil
}

func dirOrBinaryExists(directory, binary string) bool {
	if fileExists(directory) {
		return true
	}
	_, err := findExecutable(binary)
	return err == nil
}

var findExecutable = func(binary string) (string, error) {
	path := os.Getenv("PATH")
	for _, directory := range filepath.SplitList(path) {
		candidate := filepath.Join(directory, binary)
		if info, err := os.Stat(candidate); err == nil && info.Mode()&0o111 != 0 {
			return candidate, nil
		}
	}
	return "", errors.New("binary not found")
}

func writeManagedConfig(path, hookBinary string) (bool, error) {
	existing, err := os.ReadFile(path)
	if err != nil && !os.IsNotExist(err) {
		return false, err
	}
	merged, err := mergeManagedHookSet(existing, hookBinary)
	if err != nil {
		return false, err
	}
	if bytes.Equal(existing, merged) {
		return false, nil
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o700); err != nil {
		return false, err
	}
	mode := os.FileMode(0o600)
	if info, statErr := os.Stat(path); statErr == nil {
		mode = info.Mode().Perm()
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".orbit-config-*")
	if err != nil {
		return false, err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err = temporary.Chmod(mode); err == nil {
		_, err = temporary.Write(merged)
	}
	if closeErr := temporary.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return false, err
	}
	if err = os.Rename(temporaryPath, path); err != nil {
		return false, err
	}
	return true, nil
}

func mergeManagedHookSet(existing []byte, hookBinary string) ([]byte, error) {
	root := map[string]any{}
	cleaned := stripTrailingCommas(stripJSONComments(existing))
	if len(bytes.TrimSpace(cleaned)) > 0 {
		if err := json.Unmarshal(cleaned, &root); err != nil {
			return nil, err
		}
	}
	managed := map[string]any{
		"orbit": map[string]any{"command": hookBinary, "events": []string{"*"}, "managed": true},
	}
	root = mergeNestedHooks(root, managed)
	output, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, err
	}
	return append(output, '\n'), nil
}

func mergeNestedHooks(root map[string]any, managed map[string]any) map[string]any {
	hooks, _ := root["hooks"].(map[string]any)
	if hooks == nil {
		hooks = map[string]any{}
	}
	for key, value := range managed {
		hooks[key] = value
	}
	root["hooks"] = hooks
	return root
}

func stripJSONComments(input []byte) []byte {
	var output []byte
	inString, escaped := false, false
	for index := 0; index < len(input); index++ {
		current := input[index]
		if inString {
			output = append(output, current)
			if escaped {
				escaped = false
			} else if current == '\\' {
				escaped = true
			} else if current == '"' {
				inString = false
			}
			continue
		}
		if current == '"' {
			inString = true
			output = append(output, current)
			continue
		}
		if current == '/' && index+1 < len(input) && input[index+1] == '/' {
			index += 2
			for index < len(input) && input[index] != '\n' {
				index++
			}
			output = append(output, '\n')
			continue
		}
		if current == '/' && index+1 < len(input) && input[index+1] == '*' {
			index += 2
			for index+1 < len(input) && !(input[index] == '*' && input[index+1] == '/') {
				index++
			}
			index++
			continue
		}
		output = append(output, current)
	}
	return output
}

func stripTrailingCommas(input []byte) []byte {
	output := make([]byte, 0, len(input))
	inString, escaped := false, false
	for index := 0; index < len(input); index++ {
		current := input[index]
		if inString {
			output = append(output, current)
			if escaped {
				escaped = false
			} else if current == '\\' {
				escaped = true
			} else if current == '"' {
				inString = false
			}
			continue
		}
		if current == '"' {
			inString = true
			output = append(output, current)
			continue
		}
		if current == ',' {
			next := index + 1
			for next < len(input) && (input[next] == ' ' || input[next] == '	' || input[next] == '\r' || input[next] == '\n') {
				next++
			}
			if next < len(input) && (input[next] == '}' || input[next] == ']') {
				continue
			}
		}
		output = append(output, current)
	}
	return output
}
