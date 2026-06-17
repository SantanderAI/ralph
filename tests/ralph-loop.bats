#!/usr/bin/env bats
# Copyright (c) 2026 Santander Group
# SPDX-License-Identifier: Apache-2.0
#
# Smoke tests for ralph-loop.sh that exercise only the paths which exit BEFORE
# any AI CLI is launched (argument validation and the stop.md early-exit), so
# the suite runs without codex/claude/gemini/devin installed.

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../ralph-loop.sh"
  WORK="$(mktemp -d)"
  cd "$WORK"
}

teardown() {
  cd /
  rm -rf "$WORK"
}

@test "no arguments: prints usage and exits 2" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "single argument: exits 2" {
  run bash "$SCRIPT" 5
  [ "$status" -eq 2 ]
}

@test "too many arguments: exits 2" {
  run bash "$SCRIPT" 5 prompt.md extra
  [ "$status" -eq 2 ]
}

@test "non-integer MAX_ITERATIONS: rejected with exit 2" {
  echo "hello" > prompt.md
  run bash "$SCRIPT" notanumber prompt.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"positive integer"* ]]
}

@test "zero MAX_ITERATIONS: rejected with exit 2" {
  echo "hello" > prompt.md
  run bash "$SCRIPT" 0 prompt.md
  [ "$status" -eq 2 ]
}

@test "missing PROMPT_FILE: rejected with exit 2" {
  run bash "$SCRIPT" 3 does-not-exist.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"PROMPT_FILE must exist"* ]]
}

@test "stop.md present at startup: exits 0 without running an agent" {
  echo "do something" > prompt.md
  echo "stop" > stop.md
  run bash "$SCRIPT" 3 prompt.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"stop_reason=stop.md_present_at_start"* ]]
  # The stop file must NOT be deleted.
  [ -f stop.md ]
}
