# Contributing to ralph

Thanks for your interest in contributing! `ralph` is a dependency-free Bash /
PowerShell loop wrapper that runs an AI coding CLI in a fresh session each
iteration. Contributions of all kinds are welcome: bug reports, documentation,
new agent integrations, skill improvements, and code.

By participating, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug** — open a [bug report issue](.github/ISSUE_TEMPLATE/bug_report.yml).
- **Request a feature** — open a [feature request issue](.github/ISSUE_TEMPLATE/feature_request.yml).
- **Submit a change** — follow the fork-based pull request flow below.
- **Report a vulnerability** — see [SECURITY.md](.github/SECURITY.md) (do **not** open a public issue).

## Pull Request Process

### For External Contributors

1. **Fork** the repository to your GitHub account.
2. **Create a branch** from `main` with a descriptive name:
   ```bash
   git checkout -b feature/add-new-agent
   ```
3. **Make your changes** following the [Code Style](#code-style) guidelines.
4. **Keep Bash and PowerShell in sync** — see [Bash ↔ PowerShell parity](#bash--powershell-parity).
5. **Add or update tests** for any new behaviour.
6. **Update documentation** (`README.md`) if your change affects configuration or usage.
7. **Commit** with clear messages following [Conventional Commits](https://www.conventionalcommits.org/):
   ```
   feat: add support for a new agent CLI
   fix: keep previous config when .env has an invalid value
   docs: clarify the RALPH_MEMORY_MAX behaviour
   ```
8. **Push** your branch and open a Pull Request against `main`.
9. **Sign the CLA** when prompted by the CLA Assistant bot.
10. **Wait for review** — a maintainer will review your PR within 2 weeks (SLA).

### For Internal Contributors (Santander)

1. **Create a branch** from `main` (no fork needed if you are a member of the org).
2. Follow steps 3-8 above.
3. Request review from the maintainer team in [CODEOWNERS](CODEOWNERS).

### PR Requirements

All pull requests must pass the following automated checks before merge:

- [ ] **CI lint and tests** (`ci`) — ShellCheck, PSScriptAnalyzer, and the bats test suite
- [ ] **License check** (`license-check`) — SPDX header verification
- [ ] **Pattern check** (`pattern-check`) — No internal URLs, IPs, or corporate email addresses
- [ ] **Supply-chain** (`scorecard`) — OpenSSF Scorecard analysis
- [ ] **CLA signed** (for external contributors)

Additionally:

- At least **1 maintainer approval** is required.
- All review conversations must be resolved.
- The branch must be up to date with `main`.

## Bash ↔ PowerShell parity

The loop ships as two equivalent implementations:

- `ralph-loop.sh` — Bash version (canonical reference).
- `ralph-loop.ps1` — PowerShell version (pwsh 6+), with the same capabilities.

**Mandatory rule:** any behavioural change (a new `RALPH_*` option, a change to
the tool-rotation cycle, to token-exhaustion detection, to the log format, to
`stop.md` handling, to default flags, etc.) **must be applied to BOTH files in
the same commit**, so their observable behaviour stays identical. Do not leave
one lagging behind the other.

Known and accepted difference: the RAM limit (`RALPH_MEMORY_MAX`) is enforced
only on Linux via `systemd-run --user --scope`. On other platforms both versions
print a one-time warning and run the agent without a limit.

## Code Style

### Shell (Bash / PowerShell)

- Bash targets `bash` with `set -u`; pass [ShellCheck](https://www.shellcheck.net/) with no warnings.
- PowerShell targets `pwsh` 6+ with `Set-StrictMode -Version Latest`; pass [PSScriptAnalyzer](https://learn.microsoft.com/powershell/utility-modules/psscriptanalyzer/overview).
- Prefer small, single-purpose functions; quote all expansions; avoid `eval`.

### File Headers

Every script must include the copyright header (after the shebang line):

```sh
# Copyright (c) 2026 César Gallego Rodríguez
# SPDX-License-Identifier: Apache-2.0
```

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | Use |
|:---|:---|
| `feat:` | New feature |
| `fix:` | Bug fix |
| `docs:` | Documentation only |
| `test:` | Adding or updating tests |
| `refactor:` | Code refactoring (no feature/fix) |
| `ci:` | CI/CD changes |
| `chore:` | Maintenance tasks |

## Testing

- Tests live in `tests/` and use [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System).
- Run the suite locally before submitting a PR:
  ```bash
  bats tests/
  ```
- New behaviour in `ralph-loop.sh` should come with a bats test that does not
  require any AI CLI to be installed (use the argument-validation and `stop.md`
  paths, which exit before launching an agent).

## Contributor License Agreement (CLA)

By submitting a pull request, you agree to the terms of our Contributor License
Agreement. The [CLA Assistant](https://cla-assistant.io/) bot will automatically
check your PR and ask you to sign the CLA if you have not already done so.

The CLA ensures that contributions can be distributed under the project's Apache 2.0 license.

## Release Process

This project follows [Semantic Versioning (SemVer)](https://semver.org/):

- **MAJOR** — Incompatible changes to configuration keys or CLI contract
- **MINOR** — New features (backward-compatible)
- **PATCH** — Bug fixes (backward-compatible)

Releases are managed by maintainers. If you believe a release is warranted, open an issue to discuss.

---

Thank you for contributing to **ralph**!
