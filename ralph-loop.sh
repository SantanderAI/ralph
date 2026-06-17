#!/usr/bin/env bash
# Copyright (c) 2026 César Gallego Rodríguez
# SPDX-License-Identifier: Apache-2.0

# Configuration
# -------------
# All configuration lives in .ralph/.env (relative to the invocation directory).
# It is the only configuration source: the shell environment is never consulted
# for RALPH_* settings. The file is created with defaults on first run if it does
# not exist (write_default_env_file).
#
# The file is sourced before every iteration (load_env_file) and the config is
# then recomputed (resolve_config), so editing it mid-run takes effect on the
# next iteration.
#   - It is sourced without "set -a", so RALPH_* become plain shell variables,
#     not exported environment variables. RALPH_LOCAL_DIR is the only exported
#     variable (the script-managed .ralph directory).
#   - Plain "KEY=value" lines work; quote values that contain spaces.
#   - An invalid value is reported and the previous good config is kept, so a
#     typo will not abort the loop.

set -u

usage() {
  cat <<'EOF'
Usage: ./ralph-loop.sh MAX_ITERATIONS PROMPT_FILE

Runs fresh AI CLI sessions in a loop from the directory where this script was
invoked. The invocation directory is treated as the user's workspace.

Arguments:
  MAX_ITERATIONS  Positive integer.
  PROMPT_FILE     Existing regular file. Its contents are sent to the selected
                  AI CLI as the prompt.

Configuration (.ralph/.env):
  All settings live in .ralph/.env in the invocation directory. It is the only
  configuration source; the shell environment is ignored. The file is created
  with these defaults on first run. Quote values that contain spaces.

  RALPH_TOOL             AI CLI to run. Allowed values: codex, claude, gemini,
                         devin. Default: codex
  RALPH_MODEL_CAPABILITY Normalized model capability: low, med, or high.
                         Default: med
  RALPH_THINKING         Best-effort thinking/reasoning toggle: true or false.
                         Ignored by devin, which has no such knob. Default: false
  RALPH_SWITCH_ON_EXHAUSTION
                         On a non-zero iteration, ask the next tool in the
                         rotation (codex -> claude -> gemini -> devin -> codex)
                         whether the failure was token/quota exhaustion of the
                         failed tool; if so, rewrite RALPH_TOOL in .ralph/.env so
                         the next iteration switches agent. true or false.
                         Default: true

  RALPH_MEMORY_MAX       Hard RAM limit for the agent process, enforced by the
                         Linux kernel via a transient systemd user scope
                         (systemd-run --user --scope -p MemoryMax=... with swap
                         disabled). When the agent exceeds the limit it is
                         OOM-killed and the iteration exits non-zero. Accepts a
                         systemd memory value (e.g. 8G, 512M, raw bytes, or a
                         percentage). Set to empty to disable the limit. If
                         systemd-run user scopes are unavailable, the agent runs
                         without a limit and a warning is printed.
                         Default: 8G

  RALPH_CODEX_COMMAND    Command name/path for Codex.
                         Default: codex
  RALPH_CODEX_FLAGS      Whitespace-separated flags for "codex exec".
                         Default: --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check
  RALPH_CODEX_MODEL_LOW  Codex low-capability model.
                         Default: gpt-5.4-mini
  RALPH_CODEX_MODEL_MED  Codex medium-capability model.
                         Default: gpt-5.4
  RALPH_CODEX_MODEL_HIGH Codex high-capability model.
                         Default: gpt-5.5

  RALPH_CLAUDE_COMMAND   Command name/path for Claude.
                         Default: claude
  RALPH_CLAUDE_FLAGS     Whitespace-separated flags for "claude -p".
                         Default: --permission-mode bypassPermissions
  RALPH_CLAUDE_MODEL_LOW Claude low-capability model.
                         Default: haiku
  RALPH_CLAUDE_MODEL_MED Claude medium-capability model.
                         Default: sonnet
  RALPH_CLAUDE_MODEL_HIGH Claude high-capability model.
                         Default: opus

  RALPH_GEMINI_COMMAND   Command name/path for Gemini.
                         Default: gemini
  RALPH_GEMINI_FLAGS     Whitespace-separated flags for "gemini".
                         Default: --approval-mode=yolo --skip-trust
  RALPH_GEMINI_MODEL_LOW Gemini low-capability model.
                         Default: gemini-2.5-flash-lite
  RALPH_GEMINI_MODEL_MED Gemini medium-capability model.
                         Default: gemini-2.5-flash
  RALPH_GEMINI_MODEL_HIGH Gemini high-capability model.
                         Default: gemini-2.5-pro

  RALPH_DEVIN_COMMAND    Command name/path for Devin.
                         Default: devin
  RALPH_DEVIN_FLAGS      Whitespace-separated flags for "devin ... -p". The
                         prompt is passed via --prompt-file (devin panics if the
                         prompt is piped on stdin).
                         Default: --permission-mode dangerous
  RALPH_DEVIN_MODEL_LOW  Devin low-capability model.
                         Default: claude-haiku-4.5
  RALPH_DEVIN_MODEL_MED  Devin medium-capability model.
                         Default: claude-sonnet-4.6
  RALPH_DEVIN_MODEL_HIGH Devin high-capability model.
                         Default: claude-opus-4.8

  RALPH_LOOP_MAX_LOGS    Positive integer max logs to retain in .ralph/logs.
                         Default: min(MAX_ITERATIONS, 50)

Live reload:
  .ralph/.env is sourced before every iteration, so editing it while the loop
  runs takes effect on the next iteration. An invalid value is reported and the
  previous good configuration is kept.

Stop control:
  Create stop.md in the invocation directory, or any stop.md inside the plan/
  subtree, to stop before the next iteration. If a matching file exists at
  startup, the script exits without deleting it.
EOF
}

is_positive_integer() {
  case "${1:-}" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  [ "$1" -gt 0 ] 2>/dev/null
}

normalize_capability() {
  case "${1:-med}" in
    low|med|high)
      printf '%s\n' "$1"
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_bool() {
  case "${1:-false}" in
    true|false)
      printf '%s\n' "$1"
      ;;
    *)
      return 1
      ;;
  esac
}

normalize_memory_max() {
  # Accept an empty value (limit disabled), "infinity", an integer count of
  # bytes, an integer with a systemd unit suffix (K/M/G/T/P/E, base-1024), or an
  # integer percentage. Anything else is rejected so a typo cannot silently
  # disable the limit or be passed verbatim to systemd-run.
  local value=${1:-}

  case "$value" in
    ''|infinity)
      printf '%s\n' "$value"
      ;;
    *%)
      case "${value%\%}" in ''|*[!0-9]*) return 1 ;; esac
      printf '%s\n' "$value"
      ;;
    *[KMGTPE])
      case "${value%?}" in ''|*[!0-9]*) return 1 ;; esac
      printf '%s\n' "$value"
      ;;
    *)
      case "$value" in *[!0-9]*) return 1 ;; esac
      printf '%s\n' "$value"
      ;;
  esac
}

rotate_logs() {
  local log_dir=$1
  local max_logs=$2

  ls -t "$log_dir"/*.log 2>/dev/null | tail -n +"$((max_logs + 1))" | xargs -r rm -f --
}

find_stop_file() {
  local file

  if [ -e "$initial_cwd/stop.md" ]; then
    printf '%s\n' "$initial_cwd/stop.md"
    return 0
  fi

  if [ -d "$initial_cwd/plan" ]; then
    file=$(find "$initial_cwd/plan" -type f -name 'stop.md' -print -quit 2>/dev/null)
    if [ -n "$file" ]; then
      printf '%s\n' "$file"
      return 0
    fi
  fi

  return 1
}

model_for_tool() {
  case "$1:$2" in
    codex:low) printf '%s\n' "${RALPH_CODEX_MODEL_LOW:-gpt-5.4-mini}" ;;
    codex:med) printf '%s\n' "${RALPH_CODEX_MODEL_MED:-gpt-5.4}" ;;
    codex:high) printf '%s\n' "${RALPH_CODEX_MODEL_HIGH:-gpt-5.5}" ;;
    claude:low) printf '%s\n' "${RALPH_CLAUDE_MODEL_LOW:-haiku}" ;;
    claude:med) printf '%s\n' "${RALPH_CLAUDE_MODEL_MED:-sonnet}" ;;
    claude:high) printf '%s\n' "${RALPH_CLAUDE_MODEL_HIGH:-opus}" ;;
    gemini:low) printf '%s\n' "${RALPH_GEMINI_MODEL_LOW:-gemini-2.5-flash-lite}" ;;
    gemini:med) printf '%s\n' "${RALPH_GEMINI_MODEL_MED:-gemini-2.5-flash}" ;;
    gemini:high) printf '%s\n' "${RALPH_GEMINI_MODEL_HIGH:-gemini-2.5-pro}" ;;
    devin:low) printf '%s\n' "${RALPH_DEVIN_MODEL_LOW:-claude-haiku-4.5}" ;;
    devin:med) printf '%s\n' "${RALPH_DEVIN_MODEL_MED:-claude-sonnet-4.6}" ;;
    devin:high) printf '%s\n' "${RALPH_DEVIN_MODEL_HIGH:-claude-opus-4.8}" ;;
  esac
}

effort_level() {
  local capability=$1
  local thinking=$2

  # Codex exposes web_search in some environments, and the API rejects that
  # tool set with reasoning.effort=minimal. Use low as the floor.
  if [ "$thinking" = false ]; then
    printf '%s\n' low
    return 0
  fi

  case "$capability" in
    low) printf '%s\n' low ;;
    med) printf '%s\n' medium ;;
    high) printf '%s\n' high ;;
  esac
}

gemini_thinking_budget() {
  local model=$1
  local capability=$2
  local thinking=$3

  if [ "$thinking" = false ]; then
    case "$model" in
      *pro*) printf '%s\n' 128 ;;
      *) printf '%s\n' 0 ;;
    esac
    return 0
  fi

  case "$capability" in
    low) printf '%s\n' 1024 ;;
    med) printf '%s\n' -1 ;;
    high) printf '%s\n' 8192 ;;
  esac
}

build_mem_limit_prefix() {
  # Set the global array mem_limit_prefix to the command wrapper that enforces
  # the hard RAM limit, or to an empty array when no limit applies. The wrapper
  # is a transient systemd user scope: the kernel OOM-kills the agent if it
  # exceeds MemoryMax, and MemorySwapMax=0 keeps the cap on RAM rather than swap.
  mem_limit_prefix=()

  [ -z "$ralph_memory_max" ] && return 0

  # Probe systemd-run --user scopes once and cache the result across iterations.
  if [ -z "${mem_limit_supported:-}" ]; then
    if command -v systemd-run >/dev/null 2>&1 \
      && systemd-run --user --scope -q true >/dev/null 2>&1; then
      mem_limit_supported=yes
    else
      mem_limit_supported=no
    fi
  fi

  if [ "$mem_limit_supported" = yes ]; then
    mem_limit_prefix=(systemd-run --user --scope -q \
      -p MemoryMax="$ralph_memory_max" -p MemorySwapMax=0 --)
  elif [ -z "${mem_limit_warned:-}" ]; then
    echo "Warning: RALPH_MEMORY_MAX is set ($ralph_memory_max) but systemd-run --user scopes are unavailable; running the agent without a RAM limit." >&2
    mem_limit_warned=yes
  fi
}

run_tool() {
  local gemini_settings_dir
  local gemini_settings_file
  local run_exit_code

  local extra_flags=()

  build_mem_limit_prefix

  case "$ralph_tool" in
    codex)
      if [ "$ralph_thinking" = false ]; then
        extra_flags=(-c 'model_reasoning_summary="none"' -c hide_agent_reasoning=true)
      fi
      "${mem_limit_prefix[@]}" "$tool_command" exec "${tool_flags[@]}" \
        -m "$tool_model" \
        -o "$current_console_output" \
        -c "model_reasoning_effort=\"$tool_reasoning_effort\"" \
        "${extra_flags[@]}" \
        - <"$prompt_path"
      ;;
    claude)
      local -a env_prefix
      if [ "$ralph_thinking" = false ]; then
        env_prefix=(env CLAUDE_CODE_DISABLE_THINKING=1 "CLAUDE_CODE_EFFORT_LEVEL=$tool_reasoning_effort")
      else
        env_prefix=(env -u CLAUDE_CODE_DISABLE_THINKING "CLAUDE_CODE_EFFORT_LEVEL=$tool_reasoning_effort")
      fi
      "${mem_limit_prefix[@]}" "${env_prefix[@]}" "$tool_command" "${tool_flags[@]}" --model "$tool_model" --effort "$tool_reasoning_effort" -p <"$prompt_path"
      ;;
    gemini)
      gemini_settings_dir=$(mktemp -d "$RALPH_LOCAL_DIR/gemini-settings.XXXXXX") || return 1
      gemini_settings_file="$gemini_settings_dir/settings.json"
      {
        printf '{\n'
        printf '  "modelConfigs": {\n'
        printf '    "customAliases": {\n'
        printf '      "ralph-selected": {\n'
        printf '        "modelConfig": {\n'
        printf '          "model": "%s",\n' "$tool_model"
        printf '          "generateContentConfig": {\n'
        printf '            "thinkingConfig": {\n'
        printf '              "thinkingBudget": %s\n' "$tool_thinking_budget"
        printf '            }\n'
        printf '          }\n'
        printf '        }\n'
        printf '      }\n'
        printf '    }\n'
        printf '  }\n'
        printf '}\n'
      } >"$gemini_settings_file"

      "${mem_limit_prefix[@]}" \
        env GEMINI_CLI_SYSTEM_SETTINGS_PATH="$gemini_settings_file" \
        "$tool_command" "${tool_flags[@]}" --model ralph-selected <"$prompt_path"
      run_exit_code=$?
      rm -rf -- "$gemini_settings_dir"
      return "$run_exit_code"
      ;;
    devin)
      # Devin reads the prompt from --prompt-file, not stdin (piping the prompt
      # makes it drop into REPL mode and panic). It has no reasoning/thinking
      # knob, so the capability tier only selects the model. -p is print mode.
      "${mem_limit_prefix[@]}" "$tool_command" "${tool_flags[@]}" \
        --model "$tool_model" --prompt-file "$prompt_path" -p
      ;;
  esac
}

next_tool_in_rotation() {
  # Fixed rotation: codex -> claude -> gemini -> devin -> codex. The next tool is
  # always distinct from the current one. It acts both as the token-exhaustion
  # detector and as the agent we switch to.
  case "$1" in
    codex) printf '%s\n' claude ;;
    claude) printf '%s\n' gemini ;;
    gemini) printf '%s\n' devin ;;
    devin) printf '%s\n' codex ;;
  esac
}

command_for_tool() {
  case "$1" in
    codex) printf '%s\n' "${RALPH_CODEX_COMMAND:-codex}" ;;
    claude) printf '%s\n' "${RALPH_CLAUDE_COMMAND:-claude}" ;;
    gemini) printf '%s\n' "${RALPH_GEMINI_COMMAND:-gemini}" ;;
    devin) printf '%s\n' "${RALPH_DEVIN_COMMAND:-devin}" ;;
  esac
}

flags_for_tool() {
  case "$1" in
    codex) printf '%s\n' "${RALPH_CODEX_FLAGS:---dangerously-bypass-approvals-and-sandbox --skip-git-repo-check}" ;;
    claude) printf '%s\n' "${RALPH_CLAUDE_FLAGS:---permission-mode bypassPermissions}" ;;
    gemini) printf '%s\n' "${RALPH_GEMINI_FLAGS:---approval-mode=yolo --skip-trust}" ;;
    devin) printf '%s\n' "${RALPH_DEVIN_FLAGS:---permission-mode dangerous}" ;;
  esac
}

build_detector_prompt() {
  local failed_tool=$1
  local log=$2

  cat <<EOF
You are a log analyzer. The AI coding CLI "$failed_tool" was just run and exited
with a non-zero status. Below is the tail of its log output.

Your only job: decide whether the failure was caused by "$failed_tool" running
out of tokens, usage credits, or quota for its account/provider, or by being
rate-limited or usage-limited (e.g. "usage limit reached", "out of credits",
"quota exceeded", "rate limit exceeded", "insufficient credits", "you have hit
your usage limit"). Transient network errors, code bugs, crashes, or normal
non-zero exits are NOT token exhaustion.

Respond with EXACTLY one line and nothing else:
TOKENS_EXHAUSTED=true
or
TOKENS_EXHAUSTED=false

--- BEGIN LOG TAIL ---
$(tail -n 200 "$log")
--- END LOG TAIL ---
EOF
}

run_detector() {
  local detector_tool=$1
  local detector_prompt_path=$2
  local cmd model
  local -a flags

  cmd=$(command_for_tool "$detector_tool")
  model=$(model_for_tool "$detector_tool" low)
  # shellcheck disable=SC2207
  flags=($(flags_for_tool "$detector_tool"))

  # The detector always runs at low capability with thinking disabled: it is a
  # cheap yes/no classification. Output (stdout+stderr) is returned to caller.
  case "$detector_tool" in
    codex)
      "$cmd" exec "${flags[@]}" -m "$model" \
        -c 'model_reasoning_effort="low"' \
        -c 'model_reasoning_summary="none"' \
        -c hide_agent_reasoning=true \
        - <"$detector_prompt_path" 2>&1
      ;;
    claude)
      env CLAUDE_CODE_DISABLE_THINKING=1 CLAUDE_CODE_EFFORT_LEVEL=low \
        "$cmd" "${flags[@]}" --model "$model" --effort low -p <"$detector_prompt_path" 2>&1
      ;;
    gemini)
      "$cmd" "${flags[@]}" --model "$model" <"$detector_prompt_path" 2>&1
      ;;
    devin)
      "$cmd" "${flags[@]}" --model "$model" --prompt-file "$detector_prompt_path" -p 2>&1
      ;;
  esac
}

update_env_tool() {
  local new_tool=$1
  local tmp

  tmp=$(mktemp "$RALPH_LOCAL_DIR/env.XXXXXX") || return 1
  if grep -q '^[[:space:]]*RALPH_TOOL=' "$ralph_env_file"; then
    sed 's/^[[:space:]]*RALPH_TOOL=.*/RALPH_TOOL='"$new_tool"'/' "$ralph_env_file" >"$tmp"
  else
    cat "$ralph_env_file" >"$tmp"
    printf 'RALPH_TOOL=%s\n' "$new_tool" >>"$tmp"
  fi
  mv "$tmp" "$ralph_env_file"
}

handle_token_exhaustion() {
  # On a non-zero run, ask the next tool in the rotation whether the failure was
  # token/quota exhaustion of the failed tool. If so, rewrite RALPH_TOOL in
  # .ralph/.env so the next iteration picks up the new agent on reload. The
  # current iteration is not retried.
  local failed_tool=$1
  local log=$2
  local detector_tool detector_cmd detector_prompt_path detector_output

  detector_tool=$(next_tool_in_rotation "$failed_tool")
  detector_cmd=$(command_for_tool "$detector_tool")

  {
    echo "---- ralph-loop token-exhaustion check ----"
    echo "failed_tool: $failed_tool"
    echo "detector_tool: $detector_tool"
  } >>"$log"

  if ! command -v "$detector_cmd" >/dev/null 2>&1; then
    echo "detector_unavailable: $detector_cmd not on PATH; skipping switch" >>"$log"
    printf 'Token-exhaustion check skipped: detector %s (%s) not installed.\n' "$detector_tool" "$detector_cmd"
    return 0
  fi

  detector_prompt_path=$(mktemp "$RALPH_LOCAL_DIR/detector-prompt.XXXXXX") || return 0
  build_detector_prompt "$failed_tool" "$log" >"$detector_prompt_path"
  detector_output=$(run_detector "$detector_tool" "$detector_prompt_path")
  rm -f -- "$detector_prompt_path"

  {
    echo "---- detector output ----"
    printf '%s\n' "$detector_output"
  } >>"$log"

  if printf '%s' "$detector_output" | grep -qi 'TOKENS_EXHAUSTED=true'; then
    if update_env_tool "$detector_tool"; then
      echo "switch: RALPH_TOOL $failed_tool -> $detector_tool (written to .ralph/.env)" >>"$log"
      printf 'Token exhaustion detected for %s; switched RALPH_TOOL to %s for the next iteration.\n' "$failed_tool" "$detector_tool"
    else
      echo "switch_failed: could not update $ralph_env_file" >>"$log"
      printf 'Token exhaustion detected for %s but failed to update %s.\n' "$failed_tool" "$ralph_env_file"
    fi
  else
    echo "no_switch: detector did not report token exhaustion" >>"$log"
  fi
}

write_default_env_file() {
  cat >"$ralph_env_file" <<'EOF'
# Ralph configuration. Edit this file to reconfigure the loop; changes are
# picked up before each iteration. This is the only configuration source.

RALPH_TOOL=codex
RALPH_MODEL_CAPABILITY=med
RALPH_THINKING=false

# When an iteration exits non-zero, ask the next tool in the rotation
# (codex -> claude -> gemini -> devin -> codex) whether the failure was
# token/quota exhaustion. If so, RALPH_TOOL is rewritten here so the next
# iteration switches.
RALPH_SWITCH_ON_EXHAUSTION=true

# Hard RAM limit for the agent process, enforced by the kernel via a transient
# systemd user scope (the agent is OOM-killed if it exceeds this). Accepts a
# systemd memory value (8G, 512M, raw bytes, or a percentage). Leave empty to
# disable.
RALPH_MEMORY_MAX=8G

RALPH_CODEX_COMMAND=codex
RALPH_CODEX_FLAGS="--dangerously-bypass-approvals-and-sandbox --skip-git-repo-check"
RALPH_CODEX_MODEL_LOW=gpt-5.4-mini
RALPH_CODEX_MODEL_MED=gpt-5.4
RALPH_CODEX_MODEL_HIGH=gpt-5.5

RALPH_CLAUDE_COMMAND=claude
RALPH_CLAUDE_FLAGS="--permission-mode bypassPermissions"
RALPH_CLAUDE_MODEL_LOW=haiku
RALPH_CLAUDE_MODEL_MED=sonnet
RALPH_CLAUDE_MODEL_HIGH=opus

RALPH_GEMINI_COMMAND=gemini
RALPH_GEMINI_FLAGS="--approval-mode=yolo --skip-trust"
RALPH_GEMINI_MODEL_LOW=gemini-2.5-flash-lite
RALPH_GEMINI_MODEL_MED=gemini-2.5-flash
RALPH_GEMINI_MODEL_HIGH=gemini-2.5-pro

# Devin has no reasoning/thinking knob, so RALPH_THINKING is ignored for it and
# the capability tier only selects the model. Model names are Devin's identifiers
# (run `devin --model x` to see the valid list). On the Devin Free tier override
# all three with swe-1.6-slow, the only model that plan can access.
RALPH_DEVIN_COMMAND=devin
RALPH_DEVIN_FLAGS="--permission-mode dangerous"
RALPH_DEVIN_MODEL_LOW=claude-haiku-4.5
RALPH_DEVIN_MODEL_MED=claude-sonnet-4.6
RALPH_DEVIN_MODEL_HIGH=claude-opus-4.8

# Logs to retain in .ralph/logs. Default: min(MAX_ITERATIONS, 50).
# RALPH_LOOP_MAX_LOGS=50
EOF
}

load_env_file() {
  # The file is the only configuration source. It is sourced without "set -a",
  # so RALPH_* become plain shell variables, not exported environment variables;
  # the shell environment is never a configuration channel. The file always
  # exists (created at startup), so no existence check is needed here.
  # shellcheck disable=SC1090
  . "$ralph_env_file"

  # The only exported variable: the script-managed local dir.
  export RALPH_LOCAL_DIR="$initial_cwd/.ralph"
}

resolve_config() {
  local capability thinking switch_on_exhaustion tool cmd flags_string invocation output_label
  local model reasoning_effort thinking_budget logs memory_max

  if ! capability=$(normalize_capability "${RALPH_MODEL_CAPABILITY:-med}"); then
    echo "Error: RALPH_MODEL_CAPABILITY must be one of: low, med, high." >&2
    return 1
  fi

  if ! thinking=$(normalize_bool "${RALPH_THINKING:-false}"); then
    echo "Error: RALPH_THINKING must be true or false." >&2
    return 1
  fi

  if ! switch_on_exhaustion=$(normalize_bool "${RALPH_SWITCH_ON_EXHAUSTION:-true}"); then
    echo "Error: RALPH_SWITCH_ON_EXHAUSTION must be true or false." >&2
    return 1
  fi

  # Default only when unset, so RALPH_MEMORY_MAX= (empty) explicitly disables it.
  if ! memory_max=$(normalize_memory_max "${RALPH_MEMORY_MAX-8G}"); then
    echo "Error: RALPH_MEMORY_MAX must be empty, infinity, a byte count, a value with a K/M/G/T/P/E suffix, or a percentage." >&2
    return 1
  fi

  tool=${RALPH_TOOL:-codex}
  case "$tool" in
    codex)
      cmd=${RALPH_CODEX_COMMAND:-codex}
      flags_string=${RALPH_CODEX_FLAGS:---dangerously-bypass-approvals-and-sandbox --skip-git-repo-check}
      invocation='codex exec FLAGS - < PROMPT_FILE'
      output_label='codex'
      ;;
    claude)
      cmd=${RALPH_CLAUDE_COMMAND:-claude}
      flags_string=${RALPH_CLAUDE_FLAGS:---permission-mode bypassPermissions}
      invocation='claude FLAGS -p < PROMPT_FILE'
      output_label='claude'
      ;;
    gemini)
      cmd=${RALPH_GEMINI_COMMAND:-gemini}
      flags_string=${RALPH_GEMINI_FLAGS:---approval-mode=yolo --skip-trust}
      invocation='gemini FLAGS < PROMPT_FILE'
      output_label='gemini'
      ;;
    devin)
      cmd=${RALPH_DEVIN_COMMAND:-devin}
      flags_string=${RALPH_DEVIN_FLAGS:---permission-mode dangerous}
      invocation='devin FLAGS --model MODEL --prompt-file PROMPT_FILE -p'
      output_label='devin'
      ;;
    *)
      echo "Error: unknown RALPH_TOOL '$tool'. Allowed values: codex, claude, gemini, devin." >&2
      return 1
      ;;
  esac

  model=$(model_for_tool "$tool" "$capability")
  case "$tool" in
    codex|claude)
      reasoning_effort=$(effort_level "$capability" "$thinking")
      thinking_budget=
      ;;
    gemini)
      reasoning_effort=
      thinking_budget=$(gemini_thinking_budget "$model" "$capability" "$thinking")
      ;;
    devin)
      # Devin exposes no reasoning-effort or thinking-budget knob; the capability
      # tier only selects the model, so RALPH_THINKING is a best-effort no-op.
      reasoning_effort=
      thinking_budget=
      ;;
  esac

  if [ -n "${RALPH_LOOP_MAX_LOGS:-}" ]; then
    if ! is_positive_integer "$RALPH_LOOP_MAX_LOGS"; then
      echo "Error: RALPH_LOOP_MAX_LOGS must be a positive integer." >&2
      return 1
    fi
    logs=$RALPH_LOOP_MAX_LOGS
  elif [ "$max_iterations" -lt 50 ]; then
    logs=$max_iterations
  else
    logs=50
  fi

  # Commit to globals only after every value is validated, so a bad reload
  # mid-loop leaves the previous good configuration in place.
  ralph_model_capability=$capability
  ralph_thinking=$thinking
  ralph_switch_on_exhaustion=$switch_on_exhaustion
  ralph_memory_max=$memory_max
  ralph_tool=$tool
  tool_command=$cmd
  tool_flags_string=$flags_string
  tool_invocation=$invocation
  tool_output_label=$output_label
  # shellcheck disable=SC2206
  tool_flags=($flags_string)
  tool_model=$model
  tool_reasoning_effort=$reasoning_effort
  tool_thinking_budget=$thinking_budget
  max_logs=$logs
}

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 2
fi

max_iterations=$1
prompt_file=$2
initial_cwd=$(pwd)

export RALPH_LOCAL_DIR="$initial_cwd/.ralph"

if ! is_positive_integer "$max_iterations"; then
  echo "Error: MAX_ITERATIONS must be a positive integer." >&2
  usage >&2
  exit 2
fi

if [ ! -f "$prompt_file" ]; then
  echo "Error: PROMPT_FILE must exist and be a regular file: $prompt_file" >&2
  usage >&2
  exit 2
fi

ralph_env_file="$RALPH_LOCAL_DIR/.env"

mkdir -p "$RALPH_LOCAL_DIR"
[ -f "$ralph_env_file" ] || write_default_env_file

load_env_file
if ! resolve_config; then
  exit 2
fi

case "$prompt_file" in
  /*)
    prompt_path=$prompt_file
    ;;
  *)
    prompt_path="$initial_cwd/$prompt_file"
    ;;
esac

if stop_file=$(find_stop_file); then
  echo "$stop_file exists; exiting without deleting it."
  echo "Summary: iterations_executed=0 failed=0 stop_reason=stop.md_present_at_start"
  exit 0
fi

log_dir="$RALPH_LOCAL_DIR/logs"
mkdir -p "$log_dir"

executed=0
failed=0
stop_reason="max_iterations_reached"
current_console_output=
mem_limit_prefix=()

cleanup_current_console_output() {
  if [ -n "${current_console_output:-}" ]; then
    rm -f -- "$current_console_output"
    current_console_output=
  fi
}

print_file_with_trailing_newline() {
  local file=$1

  cat "$file"
  if [ "$(tail -c 1 "$file" | wc -l | tr -d ' ')" -eq 0 ]; then
    printf '\n'
  fi
}

trap cleanup_current_console_output EXIT HUP INT TERM

printf 'Ralph loop: %s iteration(s), tool=%s(%s), model=%s, logs=.ralph/logs\n' "$max_iterations" "$ralph_tool" "$ralph_model_capability" "$tool_model"

for ((iteration = 1; iteration <= max_iterations; iteration++)); do
  if stop_file=$(find_stop_file); then
    stop_reason="stop.md_detected_before_iteration_$iteration"
    echo "Detected $stop_file; stopping."
    break
  fi

  load_env_file
  if ! resolve_config; then
    echo "Warning: invalid Ralph config in $ralph_env_file; keeping previous settings." >&2
  fi

  timestamp=$(date '+%Y%m%d-%H%M%S')
  printf -v iteration_padded '%06d' "$iteration"
  log_file="$log_dir/iteration-${iteration_padded}-${timestamp}.log"
  current_console_output=$(mktemp "$RALPH_LOCAL_DIR/console-output-${iteration_padded}.XXXXXX") || {
    echo "Error: failed to create temporary console output file in $RALPH_LOCAL_DIR" >&2
    stop_reason="failed_to_create_temporary_console_output"
    break
  }

  cd "$initial_cwd" || {
    echo "Error: failed to cd to invocation directory: $initial_cwd" >&2
    stop_reason="failed_to_cd_to_initial_cwd"
    break
  }

  {
    echo "ralph-loop iteration $iteration/$max_iterations"
    echo "cwd: $(pwd)"
    echo "started_at: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "tool: $ralph_tool"
    echo "command: $tool_command"
    echo "flags: $tool_flags_string"
    echo "model_capability: $ralph_model_capability"
    echo "model: $tool_model"
    echo "thinking: $ralph_thinking"
    if [ -n "$ralph_memory_max" ]; then
      echo "memory_max: $ralph_memory_max"
    fi
    if [ -n "$tool_reasoning_effort" ]; then
      echo "reasoning_effort: $tool_reasoning_effort"
    fi
    if [ -n "$tool_thinking_budget" ]; then
      echo "thinking_budget: $tool_thinking_budget"
    fi
    echo "prompt_file: $prompt_path"
    echo "ralph_local_dir: $RALPH_LOCAL_DIR"
    echo "log_dir: $log_dir"
    echo "retaining_logs: $max_logs"
    echo "invocation: $tool_invocation"
    echo "---- $tool_output_label output ----"
  } >"$log_file"

  if run_tool >>"$log_file" 2>&1; then
    exit_code=0
    iteration_status=ok
  else
    exit_code=$?
    failed=$((failed + 1))
    iteration_status="failed exit=$exit_code"
  fi

  {
    echo "---- ralph-loop result ----"
    echo "exit_code: $exit_code"
    echo "finished_at: $(date '+%Y-%m-%d %H:%M:%S')"
  } >>"$log_file"

  if [ "$exit_code" -ne 0 ] && [ "$ralph_switch_on_exhaustion" = true ]; then
    handle_token_exhaustion "$ralph_tool" "$log_file"
  fi

  if [ -s "$current_console_output" ]; then
    print_file_with_trailing_newline "$current_console_output"
  fi
  if [ -t 1 ]; then
    green=$'\033[0;32m'
    reset=$'\033[0m'
  else
    green=''
    reset=''
  fi
  printf '%s=== Iteration %s/%s [%s(%s)] %s; log=.ralph/logs/%s ===%s\n' "$green" "$iteration" "$max_iterations" "$ralph_tool" "$ralph_model_capability" "$iteration_status" "$(basename "$log_file")" "$reset"

  executed=$((executed + 1))
  rotate_logs "$log_dir" "$max_logs"
  cleanup_current_console_output
done

echo "Summary: iterations_executed=$executed failed=$failed stop_reason=$stop_reason"
