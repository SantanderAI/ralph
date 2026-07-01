# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Open-source readiness scaffolding:
  - `CONTRIBUTING.md` (CLA, Bash/PowerShell parity rule), `CODE_OF_CONDUCT.md`,
    `.github/SECURITY.md`, `CODEOWNERS`, `CITATION.cff`
  - Issue templates (bug, feature) and PR template
  - SPDX headers on the loop scripts (`ralph-loop.sh`, `ralph-loop.ps1`) and the `justfile`
  - bats smoke tests for `ralph-loop.sh` (argument validation and `stop.md` early-exit; no AI CLI required)
  - GitHub Actions workflows (third-party actions pinned to SHA digests):
    - `ci.yml` — ShellCheck + PSScriptAnalyzer + bats
    - `license-check.yml` — SPDX header verification for shell sources
    - `pattern-check.yml` — internal-pattern scan with allowlist
    - `scorecard.yml` — OpenSSF Scorecard supply-chain analysis
    - `cla.yml` — CLA Assistant Lite
    - `stale.yml` — stale issues/PRs automation
    - `release.yml` — versioned source archive attached to GitHub Releases
  - `.github/dependabot.yml` — monthly GitHub Actions updates
  - README badges, attribution line, and Contributing/Security/License/Citation sections

### Fixed
- `ralph-loop.sh` no longer crashes on macOS (bash 3.2) with
  `mem_limit_prefix[@]: unbound variable`. Empty-array expansions now use the
  `${arr[@]:+"${arr[@]}"}` idiom, which is safe under `set -u` on bash < 4.4
  (macOS default) and expands identically to `"${arr[@]}"` when the RAM-limit
  prefix is populated on Linux.

### Changed
- `NOTICE`, source headers and `CITATION.cff` declare **César Gallego Rodríguez**
  as the original author and copyright holder, with a link to the original
  GitLab repository; Santander AI Lab is named as distributor/maintainer of the
  public release (published with the author's consent).

## [0.1.0] - 2026-06-17

### Added
- `ralph-loop.sh` — Bash loop that runs an AI coding CLI (`codex`, `claude`,
  `gemini`, `devin`) in a fresh session each iteration, feeding it the same prompt
- `ralph-loop.ps1` — PowerShell counterpart with behavioural parity
- Live reload of `.ralph/.env` configuration before each iteration
- Auto-switch of agent on token exhaustion (fixed rotation cycle)
- Hard RAM limit per iteration on Linux via transient `systemd-run --user --scope`
- `stop.md` clean-stop signal (invocation directory or anywhere under `plan/`)
- Timestamped per-iteration logs in `.ralph/logs/` with rotation
- `justfile` install recipe and bundled `juez` / `maestro` / `ralph` skills

[Unreleased]: https://github.com/SantanderAI/ralph/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/SantanderAI/ralph/releases/tag/v0.1.0
