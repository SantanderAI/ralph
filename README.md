# ralph

> Open source by **Santander AI Lab**. A dependency-free Bash / PowerShell
> developer tool that runs an **AI coding CLI / LLM agent** in a loop, starting
> a fresh agent session on every iteration for long unattended runs.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Shell: Bash | PowerShell](https://img.shields.io/badge/shell-bash%20%7C%20pwsh-89e051.svg)](ralph-loop.sh)
[![CI](https://github.com/SantanderAI/ralph/actions/workflows/ci.yml/badge.svg)](https://github.com/SantanderAI/ralph/actions/workflows/ci.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/SantanderAI/ralph/badge)](https://securityscorecards.dev/viewer/?uri=github.com/SantanderAI/ralph)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-%23FE5196.svg)](https://www.conventionalcommits.org)

Part of [**Santander AI Open Source**](https://github.com/SantanderAI) — open source AI projects from Banco Santander ([santander.com](https://santander.com)).

`ralph` runs an AI coding CLI in a loop, starting a **fresh session on every
iteration** and feeding it the same prompt. It is a thin, dependency-free Bash
wrapper (`ralph-loop.sh`) around the CLIs you already have installed —
[Codex](https://developers.openai.com/codex/cli/),
[Claude Code](https://docs.claude.com/en/docs/claude-code),
[Gemini CLI](https://github.com/google-gemini/gemini-cli), and
[Devin CLI](https://docs.devin.ai/) — so you can drive long, unattended "keep
working on this until it's done" runs.

The name comes from the "Ralph Wiggum" technique: run the same prompt against a
clean agent over and over, letting the work accumulate in the repository
between runs.

## How it works

Each iteration the script:

1. Checks for a stop signal (`stop.md`) and exits cleanly if found.
2. Reloads configuration (see [Live reload](#live-reload-of-configuration)).
3. Launches the selected CLI as a brand-new session with your prompt piped to
   it, running in the directory where you invoked the script.
4. Writes a timestamped log to `.ralph/logs/` and rotates old logs.

Because every iteration is a fresh session, all continuity has to live in the
workspace itself: the files the agent edits, a plan, notes, etc. The prompt
should tell the agent to read that state and make incremental progress.

## Requirements

- Bash.
- At least one of the supported CLIs on your `PATH`: `codex`, `claude`,
  `gemini`, or `devin`.
- Optionally [`just`](https://github.com/casey/just) for the install recipe.

## Installation

Install the script to `~/.local/bin`:

```sh
just install
```

Or just copy `ralph-loop.sh` somewhere on your `PATH` and make it executable.

## Usage

```sh
ralph-loop.sh MAX_ITERATIONS PROMPT_FILE
```

- `MAX_ITERATIONS` — positive integer; the maximum number of loops to run.
- `PROMPT_FILE` — a file whose contents are sent to the CLI as the prompt.

Example — run Claude with a high-capability model up to 25 times. Configuration
lives in `.ralph/.env` (created with defaults on first run), so edit it and then
launch:

```sh
# .ralph/.env
RALPH_TOOL=claude
RALPH_MODEL_CAPABILITY=high
```

```sh
ralph-loop.sh 25 prompt.md
```

The directory you invoke the script from is treated as the workspace. Run
`ralph-loop.sh` with the wrong number of arguments to print full inline help.

## Configuration

Behavior is controlled entirely through `.ralph/.env` in your workspace, created
with these defaults the first time you run the loop. It is the only
configuration source — the shell environment is ignored. Quote values that
contain spaces. The most common keys:

| Variable | Values | Default | Purpose |
| --- | --- | --- | --- |
| `RALPH_TOOL` | `codex`, `claude`, `gemini`, `devin` | `codex` | Which CLI to run. |
| `RALPH_MODEL_CAPABILITY` | `low`, `med`, `high` | `med` | Normalized model tier, mapped per tool. |
| `RALPH_THINKING` | `true`, `false` | `false` | Best-effort reasoning/thinking toggle. |
| `RALPH_SWITCH_ON_EXHAUSTION` | `true`, `false` | `true` | On a failed iteration, auto-switch agent if it ran out of tokens. |
| `RALPH_MEMORY_MAX` | systemd memory value (`8G`, `512M`, bytes, `%`) or empty | `8G` | Hard RAM limit for the agent, kernel-enforced via a systemd user scope; the agent is OOM-killed if it exceeds it. Empty disables. |
| `RALPH_LOOP_MAX_LOGS` | positive integer | `min(MAX_ITERATIONS, 50)` | Logs to retain in `.ralph/logs`. |

Each tool also has overrides for its command, flags, and the model used for
each capability tier, e.g. `RALPH_CLAUDE_COMMAND`, `RALPH_CLAUDE_FLAGS`,
`RALPH_CLAUDE_MODEL_HIGH`, and the equivalents for `CODEX`, `GEMINI`, and
`DEVIN`. The capability tier (`low`/`med`/`high`) is translated into the right
per-tool model name and reasoning effort / thinking budget automatically.

Devin is special in two ways: it has no reasoning/thinking knob (so
`RALPH_THINKING` is ignored for it and the tier only selects the model), and it
reads the prompt from `--prompt-file` rather than stdin. Its `RALPH_DEVIN_MODEL_*`
defaults point at Devin's Claude models (`claude-haiku-4.5`,
`claude-sonnet-4.6`, `claude-opus-4.8`); run `devin --model x` to print the full
list of valid identifiers. On the Devin Free tier, override all three tiers with
`swe-1.6-slow`, the only model that plan can access.

See the inline help in `ralph-loop.sh` for the complete list.

## Live reload of configuration

`.ralph/.env` is sourced **before every iteration**, so the loop can be
reconfigured while it is running — no restart needed. Edit the file mid-run and
the change takes effect on the next iteration.

```sh
# .ralph/.env
RALPH_TOOL=claude
RALPH_MODEL_CAPABILITY=high
RALPH_THINKING=true
```

Notes:

- Plain `KEY=value` lines work; quote values that contain spaces.
- An invalid value is reported and the previous good configuration is kept, so
  a typo will not abort the loop.
- The file is sourced as plain shell variables (not exported), so the shell
  environment is never a configuration channel. `RALPH_LOCAL_DIR` (the
  script-managed `.ralph` directory) is the only exported variable and cannot
  be moved by the file.

## Stopping the loop

Create a `stop.md` file to stop before the next iteration:

- `stop.md` in the invocation directory, or
- any `stop.md` anywhere inside the `plan/` subtree.

The script checks for it before each iteration and exits cleanly without
deleting the file. If a matching `stop.md` already exists at startup, the loop
exits immediately. This lets the agent itself signal "I'm done" by creating
the file as part of its work.

## Auto-switching agent on token exhaustion

When an iteration exits non-zero, the loop can detect that the current agent ran
out of tokens (usage/quota/credits or rate limit) and switch to a different
agent automatically. This is on by default (`RALPH_SWITCH_ON_EXHAUSTION=true`).

### Agent rotation

Switching follows a fixed cycle, where each agent's successor is both the
detector consulted on failure and the agent switched to:

```
codex → claude → gemini → devin → codex
```

| Failed agent | Detector / next agent |
| --- | --- |
| `codex` | `claude` |
| `claude` | `gemini` |
| `gemini` | `devin` |
| `devin` | `codex` |

The successor is always a different agent from the one that failed. Because each
exhaustion advances one step, repeated token exhaustion walks the full cycle
(e.g. `codex` exhausted → `claude`; if `claude` later exhausts → `gemini`, and
so on, wrapping back to `codex`).

### How it works

1. After a non-zero iteration, the **next agent in the rotation** is launched as
   a cheap, low-capability "detector". It reads the tail of the failed
   iteration's log.
2. The detector answers a single structured line — `TOKENS_EXHAUSTED=true` or
   `TOKENS_EXHAUSTED=false`.
3. If `true`, `RALPH_TOOL` is rewritten in `.ralph/.env` to that next agent, so
   the **next iteration** runs with it (the failed iteration is not retried). If
   `false`, nothing changes.

If the next agent's CLI is not installed, the check is skipped and no switch
happens. The whole detection (detector agent, its output, and the decision) is
appended to the iteration's log. Set `RALPH_SWITCH_ON_EXHAUSTION=false` to
disable.

## Hard RAM limit

Agents can leak or balloon in memory over long autonomous runs. `RALPH_MEMORY_MAX`
(default `8G`) caps the RAM available to the agent process. The limit is enforced
by the Linux kernel: each iteration runs the agent inside a transient systemd
user scope created with

```
systemd-run --user --scope -p MemoryMax=<RALPH_MEMORY_MAX> -p MemorySwapMax=0 -- <agent>
```

`MemorySwapMax=0` keeps the cap on real RAM rather than letting it spill to swap.
If the agent exceeds the limit it is **OOM-killed**, the iteration exits non-zero
(and is then subject to the usual exhaustion check / agent switch). The value
accepts any systemd memory format (`8G`, `512M`, raw bytes, or a percentage of
total RAM); set it empty to disable the limit.

If `systemd-run` user scopes are not available on the host, the agent runs
**without** a limit and a one-time warning is printed.

## Skills

This repo also distributes the skills that ralph itself relies on, so they
travel with the project instead of living only under `~/.claude` / `~/.codex`.
The same approach as
[`rolemaster`](https://gitlab.com/gallego.cesar/rolemaster): the source of truth
is `skills/<name>/SKILL.md`, and `just` recipes copy them into each tool's
user-level skills directory.

| Skill | What it does |
|-------|--------------|
| `juez` | Independent reviewer of `plan/task/*.md`: inserts `[juez]` checkpoints, judges reproducible evidence, unblocks stuck blocks, and (only on `/juez auditar`) audits global progress in read-only mode. |
| `maestro` | Curator of the project's local skills: after each task its `review` action reads the plan and loop logs and creates, extends, or deletes local skills (methodologies, pitfalls, decisions) under `skills/` so future planning and execution stop groping blindly. |

```sh
just skills-install     # copy all skills to Claude Code, Codex CLI, Antigravity CLI
just skills-sync        # re-propagate changes after editing a skill (alias of install)
just skills-status      # show what is installed and whether it differs
just skills-uninstall   # remove only the skills from this repo
```

Restart Codex and Antigravity after install so they pick up new skills (Claude
detects them on the next session).

## Logs

Each iteration writes a timestamped log to `.ralph/logs/` containing the
resolved configuration and the CLI's output. Old logs are rotated according to
`RALPH_LOOP_MAX_LOGS`. The `.ralph/` directory lives in your workspace and the
`logs/` subdirectory is git-ignored.

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for
the development workflow, the **Bash ↔ PowerShell parity** rule, coding style,
and the CLA process. By participating you agree to our
[Code of Conduct](CODE_OF_CONDUCT.md).

## Security

Please report security vulnerabilities responsibly — see
[SECURITY.md](.github/SECURITY.md). Do **not** open a public issue for security
reports.

## License

Licensed under the [Apache License 2.0](LICENSE). Copyright (c) 2026 César
Gallego Rodríguez — see [NOTICE](NOTICE) for attribution. `ralph` was originally
created by César Gallego Rodríguez ([original repository on
GitLab](https://gitlab.com/gallego.cesar/ralph)) and is published as open source
by Santander AI Lab with the author's consent.

## Citation

If you use `ralph` in your work, please cite it using the metadata in
[CITATION.cff](CITATION.cff).
