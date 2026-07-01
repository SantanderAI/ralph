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

@test "mem_limit_prefix expansions are safe under set -u (bash 3.2)" {
  # Regression for the macOS bash 3.2 crash: expanding an empty array with
  # "${arr[@]}" under set -u raises "unbound variable" on bash < 4.4. Every
  # mem_limit_prefix expansion must use the ${arr[@]:+"${arr[@]}"} idiom.
  # An unsafe expansion is a bare "${mem_limit_prefix[@]}" (quote preceded by
  # whitespace); the safe idiom has the quote preceded by ':+'.
  run grep -nE '[[:space:]]"\$\{mem_limit_prefix\[@\]\}"' "$SCRIPT"
  [ "$status" -ne 0 ]
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
