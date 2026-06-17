#!/usr/bin/env pwsh
# Copyright (c) 2026 César Gallego Rodríguez
# SPDX-License-Identifier: Apache-2.0

# Configuration
# -------------
# All configuration lives in .ralph/.env (relative to the invocation directory).
# It is the only configuration source: the shell environment is never consulted
# for RALPH_* settings. The file is created with defaults on first run if it does
# not exist (Write-DefaultEnvFile).
#
# The file is parsed before every iteration (Read-EnvFile) and the config is then
# recomputed (Resolve-Config), so editing it mid-run takes effect on the next
# iteration.
#   - The file uses the same KEY=value syntax as the Bash version. RALPH_* become
#     entries in the in-memory $script:Env table, not process environment
#     variables; the process environment is never a configuration channel.
#   - Plain "KEY=value" lines work; quote values that contain spaces.
#   - An invalid value is reported and the previous good config is kept, so a
#     typo will not abort the loop.
#
# NOTE: This script is the PowerShell counterpart of ralph-loop.sh. Any change to
# the loop's behaviour MUST be applied to BOTH files so they stay in sync.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Show-Usage {
    @'
Usage: ./ralph-loop.ps1 MAX_ITERATIONS PROMPT_FILE

Runs fresh AI CLI sessions in a loop from the directory where this script was
invoked. The invocation directory is treated as the user's workspace.

Arguments:
  MAX_ITERATIONS  Positive integer.
  PROMPT_FILE     Existing regular file. Its contents are sent to the selected
                  AI CLI as the prompt.

Configuration (.ralph/.env):
  All settings live in .ralph/.env in the invocation directory. It is the only
  configuration source; the process environment is ignored. The file is created
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

  RALPH_MEMORY_MAX       Hard RAM limit for the agent process. On Linux it is
                         enforced by the kernel via a transient systemd user
                         scope (systemd-run --user --scope -p MemoryMax=... with
                         swap disabled), exactly like the Bash version. Accepts a
                         systemd memory value (e.g. 8G, 512M, raw bytes, or a
                         percentage). Set to empty to disable the limit. If
                         systemd-run user scopes are unavailable (e.g. on
                         Windows), the agent runs without a limit and a warning
                         is printed.
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
  .ralph/.env is parsed before every iteration, so editing it while the loop
  runs takes effect on the next iteration. An invalid value is reported and the
  previous good configuration is kept.

Stop control:
  Create stop.md in the invocation directory, or any stop.md inside the plan/
  subtree, to stop before the next iteration. If a matching file exists at
  startup, the script exits without deleting it.
'@
}

function Test-PositiveInteger {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { return $false }
    if ($Value -notmatch '^[0-9]+$') { return $false }
    return ([int64]$Value -gt 0)
}

function ConvertTo-Capability {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { $Value = 'med' }
    switch ($Value) {
        'low' { return 'low' }
        'med' { return 'med' }
        'high' { return 'high' }
        default { return $null }
    }
}

function ConvertTo-Bool {
    param([string]$Value)
    if ([string]::IsNullOrEmpty($Value)) { $Value = 'false' }
    switch ($Value) {
        'true' { return 'true' }
        'false' { return 'false' }
        default { return $null }
    }
}

function ConvertTo-MemoryMax {
    # Accept an empty value (limit disabled), "infinity", an integer count of
    # bytes, an integer with a systemd unit suffix (K/M/G/T/P/E, base-1024), or
    # an integer percentage. Anything else is rejected so a typo cannot silently
    # disable the limit or be passed verbatim to systemd-run. Returns a sentinel
    # object: { Ok = $true/$false; Value = '<normalized>' }.
    param([AllowNull()][string]$Value)
    if ($null -eq $Value) { $Value = '' }

    if ($Value -eq '' -or $Value -eq 'infinity') {
        return [pscustomobject]@{ Ok = $true; Value = $Value }
    }
    if ($Value.EndsWith('%')) {
        $n = $Value.Substring(0, $Value.Length - 1)
        if ($n -ne '' -and $n -match '^[0-9]+$') { return [pscustomobject]@{ Ok = $true; Value = $Value } }
        return [pscustomobject]@{ Ok = $false; Value = $null }
    }
    if ($Value -match '[KMGTPE]$') {
        $n = $Value.Substring(0, $Value.Length - 1)
        if ($n -ne '' -and $n -match '^[0-9]+$') { return [pscustomobject]@{ Ok = $true; Value = $Value } }
        return [pscustomobject]@{ Ok = $false; Value = $null }
    }
    if ($Value -match '^[0-9]+$') { return [pscustomobject]@{ Ok = $true; Value = $Value } }
    return [pscustomobject]@{ Ok = $false; Value = $null }
}

function Remove-OldLogs {
    param([string]$LogDir, [int]$MaxLogs)
    $logs = @(Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending)
    if ($logs.Count -gt $MaxLogs) {
        $logs[$MaxLogs..($logs.Count - 1)] | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
}

function Find-StopFile {
    if (Test-Path -LiteralPath (Join-Path $script:InitialCwd 'stop.md')) {
        return (Join-Path $script:InitialCwd 'stop.md')
    }
    $planDir = Join-Path $script:InitialCwd 'plan'
    if (Test-Path -LiteralPath $planDir -PathType Container) {
        $f = Get-ChildItem -LiteralPath $planDir -Recurse -File -Filter 'stop.md' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($f) { return $f.FullName }
    }
    return $null
}

function Get-Cfg {
    param([string]$Key, [string]$Default = '')
    if ($script:Env.ContainsKey($Key) -and $null -ne $script:Env[$Key]) {
        return $script:Env[$Key]
    }
    return $Default
}

function Get-ModelForTool {
    param([string]$Tool, [string]$Capability)
    switch ("${Tool}:${Capability}") {
        'codex:low'  { return (Get-Cfg 'RALPH_CODEX_MODEL_LOW'  'gpt-5.4-mini') }
        'codex:med'  { return (Get-Cfg 'RALPH_CODEX_MODEL_MED'  'gpt-5.4') }
        'codex:high' { return (Get-Cfg 'RALPH_CODEX_MODEL_HIGH' 'gpt-5.5') }
        'claude:low'  { return (Get-Cfg 'RALPH_CLAUDE_MODEL_LOW'  'haiku') }
        'claude:med'  { return (Get-Cfg 'RALPH_CLAUDE_MODEL_MED'  'sonnet') }
        'claude:high' { return (Get-Cfg 'RALPH_CLAUDE_MODEL_HIGH' 'opus') }
        'gemini:low'  { return (Get-Cfg 'RALPH_GEMINI_MODEL_LOW'  'gemini-2.5-flash-lite') }
        'gemini:med'  { return (Get-Cfg 'RALPH_GEMINI_MODEL_MED'  'gemini-2.5-flash') }
        'gemini:high' { return (Get-Cfg 'RALPH_GEMINI_MODEL_HIGH' 'gemini-2.5-pro') }
        'devin:low'  { return (Get-Cfg 'RALPH_DEVIN_MODEL_LOW'  'claude-haiku-4.5') }
        'devin:med'  { return (Get-Cfg 'RALPH_DEVIN_MODEL_MED'  'claude-sonnet-4.6') }
        'devin:high' { return (Get-Cfg 'RALPH_DEVIN_MODEL_HIGH' 'claude-opus-4.8') }
        default { return '' }
    }
}

function Get-EffortLevel {
    param([string]$Capability, [string]$Thinking)
    # Codex exposes web_search in some environments, and the API rejects that
    # tool set with reasoning.effort=minimal. Use low as the floor.
    if ($Thinking -eq 'false') { return 'low' }
    switch ($Capability) {
        'low'  { return 'low' }
        'med'  { return 'medium' }
        'high' { return 'high' }
    }
}

function Get-GeminiThinkingBudget {
    param([string]$Model, [string]$Capability, [string]$Thinking)
    if ($Thinking -eq 'false') {
        if ($Model -like '*pro*') { return '128' }
        return '0'
    }
    switch ($Capability) {
        'low'  { return '1024' }
        'med'  { return '-1' }
        'high' { return '8192' }
    }
}

function Build-MemPrefix {
    # Set $script:MemPrefix to the argv prefix that enforces the hard RAM limit,
    # or to an empty array when no limit applies. On Linux the prefix is a
    # transient systemd user scope: the kernel OOM-kills the agent if it exceeds
    # MemoryMax, and MemorySwapMax=0 keeps the cap on RAM rather than swap. On
    # other platforms (no systemd) the limit is unsupported and a warning is
    # printed once.
    $script:MemPrefix = @()
    if ([string]::IsNullOrEmpty($script:RalphMemoryMax)) { return }

    if ($null -eq $script:MemLimitSupported) {
        $ok = $false
        if ($IsLinux -and (Get-Command systemd-run -ErrorAction SilentlyContinue)) {
            & systemd-run --user --scope -q true *> $null 2>&1
            $ok = ($LASTEXITCODE -eq 0)
        }
        $script:MemLimitSupported = $ok
    }

    if ($script:MemLimitSupported) {
        $script:MemPrefix = @(
            'systemd-run', '--user', '--scope', '-q',
            '-p', "MemoryMax=$($script:RalphMemoryMax)",
            '-p', 'MemorySwapMax=0', '--'
        )
    }
    elseif (-not $script:MemLimitWarned) {
        Write-Warning "RALPH_MEMORY_MAX is set ($($script:RalphMemoryMax)) but systemd-run --user scopes are unavailable; running the agent without a RAM limit."
        $script:MemLimitWarned = $true
    }
}

function Invoke-Argv {
    # Run an argv (already including any mem-limit prefix). The agent's prompt is
    # piped to stdin from $StdinPath when given (codex/claude/gemini); devin reads
    # the prompt from a flag instead and passes $StdinPath = $null. stdout+stderr
    # are merged and appended to $LogPath. Returns the process exit code.
    param(
        [string[]]$Argv,
        [AllowNull()][string]$StdinPath,
        [string]$LogPath
    )
    $exe = $Argv[0]
    $rest = if ($Argv.Count -gt 1) { $Argv[1..($Argv.Count - 1)] } else { @() }

    if ($StdinPath) {
        Get-Content -LiteralPath $StdinPath -Raw | & $exe @rest 2>&1 |
            ForEach-Object { "$_" } | Add-Content -LiteralPath $LogPath -Encoding utf8
    }
    else {
        & $exe @rest 2>&1 |
            ForEach-Object { "$_" } | Add-Content -LiteralPath $LogPath -Encoding utf8
    }
    return $LASTEXITCODE
}

function Set-ScopedEnv {
    # Apply a hashtable of env vars, returning the previous values so they can be
    # restored. A $null value means "remove the variable for this run".
    param([hashtable]$Vars)
    $saved = @{}
    foreach ($k in $Vars.Keys) {
        $saved[$k] = [Environment]::GetEnvironmentVariable($k)
        [Environment]::SetEnvironmentVariable($k, $Vars[$k])
    }
    return $saved
}

function Restore-ScopedEnv {
    param([hashtable]$Saved)
    foreach ($k in $Saved.Keys) {
        [Environment]::SetEnvironmentVariable($k, $Saved[$k])
    }
}

function Invoke-Tool {
    # Run the configured agent for one iteration, appending merged output to
    # $LogPath. Returns the exit code.
    param([string]$LogPath)

    Build-MemPrefix
    $mem = $script:MemPrefix

    switch ($script:RalphTool) {
        'codex' {
            $extra = @()
            if ($script:RalphThinking -eq 'false') {
                $extra = @('-c', 'model_reasoning_summary="none"', '-c', 'hide_agent_reasoning=true')
            }
            $argv = $mem + @($script:ToolCommand, 'exec') + $script:ToolFlags + @(
                '-m', $script:ToolModel,
                '-o', $script:CurrentConsoleOutput,
                '-c', "model_reasoning_effort=`"$($script:ToolReasoningEffort)`""
            ) + $extra + @('-')
            return (Invoke-Argv -Argv $argv -StdinPath $script:PromptPath -LogPath $LogPath)
        }
        'claude' {
            if ($script:RalphThinking -eq 'false') {
                $envVars = @{ CLAUDE_CODE_DISABLE_THINKING = '1'; CLAUDE_CODE_EFFORT_LEVEL = $script:ToolReasoningEffort }
            }
            else {
                $envVars = @{ CLAUDE_CODE_DISABLE_THINKING = $null; CLAUDE_CODE_EFFORT_LEVEL = $script:ToolReasoningEffort }
            }
            $saved = Set-ScopedEnv $envVars
            try {
                $argv = $mem + @($script:ToolCommand) + $script:ToolFlags + @(
                    '--model', $script:ToolModel, '--effort', $script:ToolReasoningEffort, '-p'
                )
                return (Invoke-Argv -Argv $argv -StdinPath $script:PromptPath -LogPath $LogPath)
            }
            finally { Restore-ScopedEnv $saved }
        }
        'gemini' {
            $settingsDir = Join-Path $script:RalphLocalDir ("gemini-settings." + [System.IO.Path]::GetRandomFileName())
            New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
            $settingsFile = Join-Path $settingsDir 'settings.json'
            $json = @"
{
  "modelConfigs": {
    "customAliases": {
      "ralph-selected": {
        "modelConfig": {
          "model": "$($script:ToolModel)",
          "generateContentConfig": {
            "thinkingConfig": {
              "thinkingBudget": $($script:ToolThinkingBudget)
            }
          }
        }
      }
    }
  }
}
"@
            Set-Content -LiteralPath $settingsFile -Value $json -Encoding utf8
            $saved = Set-ScopedEnv @{ GEMINI_CLI_SYSTEM_SETTINGS_PATH = $settingsFile }
            try {
                $argv = $mem + @($script:ToolCommand) + $script:ToolFlags + @('--model', 'ralph-selected')
                $code = Invoke-Argv -Argv $argv -StdinPath $script:PromptPath -LogPath $LogPath
            }
            finally {
                Restore-ScopedEnv $saved
                Remove-Item -LiteralPath $settingsDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            return $code
        }
        'devin' {
            # Devin reads the prompt from --prompt-file, not stdin (piping the
            # prompt makes it drop into REPL mode and panic). It has no
            # reasoning/thinking knob, so the capability tier only selects the
            # model. -p is print mode.
            $argv = $mem + @($script:ToolCommand) + $script:ToolFlags + @(
                '--model', $script:ToolModel, '--prompt-file', $script:PromptPath, '-p'
            )
            return (Invoke-Argv -Argv $argv -StdinPath $null -LogPath $LogPath)
        }
    }
}

function Get-NextToolInRotation {
    # Fixed rotation: codex -> claude -> gemini -> devin -> codex. The next tool
    # is always distinct from the current one. It acts both as the
    # token-exhaustion detector and as the agent we switch to.
    param([string]$Tool)
    switch ($Tool) {
        'codex'  { return 'claude' }
        'claude' { return 'gemini' }
        'gemini' { return 'devin' }
        'devin'  { return 'codex' }
    }
}

function Get-CommandForTool {
    param([string]$Tool)
    switch ($Tool) {
        'codex'  { return (Get-Cfg 'RALPH_CODEX_COMMAND'  'codex') }
        'claude' { return (Get-Cfg 'RALPH_CLAUDE_COMMAND' 'claude') }
        'gemini' { return (Get-Cfg 'RALPH_GEMINI_COMMAND' 'gemini') }
        'devin'  { return (Get-Cfg 'RALPH_DEVIN_COMMAND'  'devin') }
    }
}

function Get-FlagsForTool {
    param([string]$Tool)
    switch ($Tool) {
        'codex'  { return (Get-Cfg 'RALPH_CODEX_FLAGS'  '--dangerously-bypass-approvals-and-sandbox --skip-git-repo-check') }
        'claude' { return (Get-Cfg 'RALPH_CLAUDE_FLAGS' '--permission-mode bypassPermissions') }
        'gemini' { return (Get-Cfg 'RALPH_GEMINI_FLAGS' '--approval-mode=yolo --skip-trust') }
        'devin'  { return (Get-Cfg 'RALPH_DEVIN_FLAGS'  '--permission-mode dangerous') }
    }
}

function Build-DetectorPrompt {
    param([string]$FailedTool, [string]$Log)
    $tail = (Get-Content -LiteralPath $Log -Tail 200 -ErrorAction SilentlyContinue) -join "`n"
    return @"
You are a log analyzer. The AI coding CLI "$FailedTool" was just run and exited
with a non-zero status. Below is the tail of its log output.

Your only job: decide whether the failure was caused by "$FailedTool" running
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
$tail
--- END LOG TAIL ---
"@
}

function Invoke-Detector {
    param([string]$DetectorTool, [string]$DetectorPromptPath)
    $cmd = Get-CommandForTool $DetectorTool
    $model = Get-ModelForTool $DetectorTool 'low'
    $flags = @((Get-FlagsForTool $DetectorTool) -split '\s+' | Where-Object { $_ -ne '' })

    # The detector always runs at low capability with thinking disabled: it is a
    # cheap yes/no classification. Output (stdout+stderr) is returned to caller.
    switch ($DetectorTool) {
        'codex' {
            $out = Get-Content -LiteralPath $DetectorPromptPath -Raw | & $cmd exec @flags -m $model `
                -c 'model_reasoning_effort="low"' `
                -c 'model_reasoning_summary="none"' `
                -c hide_agent_reasoning=true `
                - 2>&1 | Out-String
            return $out
        }
        'claude' {
            $saved = Set-ScopedEnv @{ CLAUDE_CODE_DISABLE_THINKING = '1'; CLAUDE_CODE_EFFORT_LEVEL = 'low' }
            try {
                $out = Get-Content -LiteralPath $DetectorPromptPath -Raw | & $cmd @flags --model $model --effort low -p 2>&1 | Out-String
            }
            finally { Restore-ScopedEnv $saved }
            return $out
        }
        'gemini' {
            $out = Get-Content -LiteralPath $DetectorPromptPath -Raw | & $cmd @flags --model $model 2>&1 | Out-String
            return $out
        }
        'devin' {
            $out = & $cmd @flags --model $model --prompt-file $DetectorPromptPath -p 2>&1 | Out-String
            return $out
        }
    }
}

function Update-EnvTool {
    param([string]$NewTool)
    try {
        $content = Get-Content -LiteralPath $script:RalphEnvFile -Raw
        if ($content -match '(?m)^\s*RALPH_TOOL=') {
            $content = $content -replace '(?m)^\s*RALPH_TOOL=.*', "RALPH_TOOL=$NewTool"
        }
        else {
            if (-not $content.EndsWith("`n")) { $content += "`n" }
            $content += "RALPH_TOOL=$NewTool`n"
        }
        Set-Content -LiteralPath $script:RalphEnvFile -Value $content -NoNewline -Encoding utf8
        return $true
    }
    catch { return $false }
}

function Invoke-HandleTokenExhaustion {
    # On a non-zero run, ask the next tool in the rotation whether the failure was
    # token/quota exhaustion of the failed tool. If so, rewrite RALPH_TOOL in
    # .ralph/.env so the next iteration picks up the new agent on reload. The
    # current iteration is not retried.
    param([string]$FailedTool, [string]$Log)

    $detectorTool = Get-NextToolInRotation $FailedTool
    $detectorCmd = Get-CommandForTool $detectorTool

    Add-Content -LiteralPath $Log -Value @(
        '---- ralph-loop token-exhaustion check ----',
        "failed_tool: $FailedTool",
        "detector_tool: $detectorTool"
    )

    if (-not (Get-Command $detectorCmd -ErrorAction SilentlyContinue)) {
        Add-Content -LiteralPath $Log -Value "detector_unavailable: $detectorCmd not on PATH; skipping switch"
        Write-Output "Token-exhaustion check skipped: detector $detectorTool ($detectorCmd) not installed."
        return
    }

    $detectorPromptPath = Join-Path $script:RalphLocalDir ("detector-prompt." + [System.IO.Path]::GetRandomFileName())
    Set-Content -LiteralPath $detectorPromptPath -Value (Build-DetectorPrompt $FailedTool $Log) -Encoding utf8
    $detectorOutput = Invoke-Detector $detectorTool $detectorPromptPath
    Remove-Item -LiteralPath $detectorPromptPath -Force -ErrorAction SilentlyContinue

    Add-Content -LiteralPath $Log -Value @('---- detector output ----', $detectorOutput)

    if ($detectorOutput -match '(?i)TOKENS_EXHAUSTED=true') {
        if (Update-EnvTool $detectorTool) {
            Add-Content -LiteralPath $Log -Value "switch: RALPH_TOOL $FailedTool -> $detectorTool (written to .ralph/.env)"
            Write-Output "Token exhaustion detected for $FailedTool; switched RALPH_TOOL to $detectorTool for the next iteration."
        }
        else {
            Add-Content -LiteralPath $Log -Value "switch_failed: could not update $($script:RalphEnvFile)"
            Write-Output "Token exhaustion detected for $FailedTool but failed to update $($script:RalphEnvFile)."
        }
    }
    else {
        Add-Content -LiteralPath $Log -Value 'no_switch: detector did not report token exhaustion'
    }
}

function Write-DefaultEnvFile {
    $content = @'
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

# Hard RAM limit for the agent process, enforced on Linux by the kernel via a
# transient systemd user scope (the agent is OOM-killed if it exceeds this).
# Accepts a systemd memory value (8G, 512M, raw bytes, or a percentage). Leave
# empty to disable. Unsupported off Linux (a warning is printed and no limit is
# applied).
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
'@
    Set-Content -LiteralPath $script:RalphEnvFile -Value $content -Encoding utf8
}

function Read-EnvFile {
    # The file is the only configuration source. It is parsed into the in-memory
    # $script:Env table; RALPH_* never become process environment variables, so
    # the process environment is never a configuration channel. The file always
    # exists (created at startup).
    $script:Env = @{}
    foreach ($line in (Get-Content -LiteralPath $script:RalphEnvFile)) {
        $trimmed = $line.Trim()
        if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }
        $m = [regex]::Match($line, '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)$')
        if (-not $m.Success) { continue }
        $key = $m.Groups[1].Value
        $val = $m.Groups[2].Value
        # Strip a single layer of matching surrounding quotes (single or double).
        if ($val.Length -ge 2 -and (
            ($val.StartsWith('"') -and $val.EndsWith('"')) -or
            ($val.StartsWith("'") -and $val.EndsWith("'")))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $script:Env[$key] = $val
    }
    $script:RalphLocalDir = Join-Path $script:InitialCwd '.ralph'
}

function Resolve-Config {
    $capability = ConvertTo-Capability (Get-Cfg 'RALPH_MODEL_CAPABILITY' 'med')
    if ($null -eq $capability) {
        Write-Error 'RALPH_MODEL_CAPABILITY must be one of: low, med, high.' -ErrorAction Continue
        return $false
    }

    $thinking = ConvertTo-Bool (Get-Cfg 'RALPH_THINKING' 'false')
    if ($null -eq $thinking) {
        Write-Error 'RALPH_THINKING must be true or false.' -ErrorAction Continue
        return $false
    }

    $switchOnExhaustion = ConvertTo-Bool (Get-Cfg 'RALPH_SWITCH_ON_EXHAUSTION' 'true')
    if ($null -eq $switchOnExhaustion) {
        Write-Error 'RALPH_SWITCH_ON_EXHAUSTION must be true or false.' -ErrorAction Continue
        return $false
    }

    # Default only when unset, so RALPH_MEMORY_MAX= (empty) explicitly disables it.
    $rawMem = if ($script:Env.ContainsKey('RALPH_MEMORY_MAX')) { $script:Env['RALPH_MEMORY_MAX'] } else { '8G' }
    $mem = ConvertTo-MemoryMax $rawMem
    if (-not $mem.Ok) {
        Write-Error 'RALPH_MEMORY_MAX must be empty, infinity, a byte count, a value with a K/M/G/T/P/E suffix, or a percentage.' -ErrorAction Continue
        return $false
    }
    $memoryMax = $mem.Value

    $tool = Get-Cfg 'RALPH_TOOL' 'codex'
    switch ($tool) {
        'codex' {
            $cmd = Get-Cfg 'RALPH_CODEX_COMMAND' 'codex'
            $flagsString = Get-Cfg 'RALPH_CODEX_FLAGS' '--dangerously-bypass-approvals-and-sandbox --skip-git-repo-check'
            $invocation = 'codex exec FLAGS - < PROMPT_FILE'
            $outputLabel = 'codex'
        }
        'claude' {
            $cmd = Get-Cfg 'RALPH_CLAUDE_COMMAND' 'claude'
            $flagsString = Get-Cfg 'RALPH_CLAUDE_FLAGS' '--permission-mode bypassPermissions'
            $invocation = 'claude FLAGS -p < PROMPT_FILE'
            $outputLabel = 'claude'
        }
        'gemini' {
            $cmd = Get-Cfg 'RALPH_GEMINI_COMMAND' 'gemini'
            $flagsString = Get-Cfg 'RALPH_GEMINI_FLAGS' '--approval-mode=yolo --skip-trust'
            $invocation = 'gemini FLAGS < PROMPT_FILE'
            $outputLabel = 'gemini'
        }
        'devin' {
            $cmd = Get-Cfg 'RALPH_DEVIN_COMMAND' 'devin'
            $flagsString = Get-Cfg 'RALPH_DEVIN_FLAGS' '--permission-mode dangerous'
            $invocation = 'devin FLAGS --model MODEL --prompt-file PROMPT_FILE -p'
            $outputLabel = 'devin'
        }
        default {
            Write-Error "unknown RALPH_TOOL '$tool'. Allowed values: codex, claude, gemini, devin." -ErrorAction Continue
            return $false
        }
    }

    $model = Get-ModelForTool $tool $capability
    switch ($tool) {
        { $_ -in 'codex', 'claude' } {
            $reasoningEffort = Get-EffortLevel $capability $thinking
            $thinkingBudget = ''
        }
        'gemini' {
            $reasoningEffort = ''
            $thinkingBudget = Get-GeminiThinkingBudget $model $capability $thinking
        }
        'devin' {
            # Devin exposes no reasoning-effort or thinking-budget knob; the
            # capability tier only selects the model, so RALPH_THINKING is a
            # best-effort no-op.
            $reasoningEffort = ''
            $thinkingBudget = ''
        }
    }

    $maxLogsCfg = Get-Cfg 'RALPH_LOOP_MAX_LOGS' ''
    if ($maxLogsCfg -ne '') {
        if (-not (Test-PositiveInteger $maxLogsCfg)) {
            Write-Error 'RALPH_LOOP_MAX_LOGS must be a positive integer.' -ErrorAction Continue
            return $false
        }
        $logs = [int]$maxLogsCfg
    }
    elseif ($script:MaxIterations -lt 50) {
        $logs = $script:MaxIterations
    }
    else {
        $logs = 50
    }

    # Commit to script-scoped state only after every value is validated, so a bad
    # reload mid-loop leaves the previous good configuration in place.
    $script:RalphModelCapability = $capability
    $script:RalphThinking = $thinking
    $script:RalphSwitchOnExhaustion = $switchOnExhaustion
    $script:RalphMemoryMax = $memoryMax
    $script:RalphTool = $tool
    $script:ToolCommand = $cmd
    $script:ToolFlagsString = $flagsString
    $script:ToolInvocation = $invocation
    $script:ToolOutputLabel = $outputLabel
    $script:ToolFlags = @($flagsString -split '\s+' | Where-Object { $_ -ne '' })
    $script:ToolModel = $model
    $script:ToolReasoningEffort = $reasoningEffort
    $script:ToolThinkingBudget = $thinkingBudget
    $script:MaxLogs = $logs
    return $true
}

# ---- Main ----------------------------------------------------------------

if ($args.Count -ne 2) {
    [Console]::Error.WriteLine((Show-Usage))
    exit 2
}

$script:MaxIterations = 0
$maxIterationsArg = [string]$args[0]
$promptFile = [string]$args[1]
$script:InitialCwd = (Get-Location).Path

if (-not (Test-PositiveInteger $maxIterationsArg)) {
    [Console]::Error.WriteLine('Error: MAX_ITERATIONS must be a positive integer.')
    [Console]::Error.WriteLine((Show-Usage))
    exit 2
}
$script:MaxIterations = [int]$maxIterationsArg

if (-not (Test-Path -LiteralPath $promptFile -PathType Leaf)) {
    [Console]::Error.WriteLine("Error: PROMPT_FILE must exist and be a regular file: $promptFile")
    [Console]::Error.WriteLine((Show-Usage))
    exit 2
}

$script:RalphLocalDir = Join-Path $script:InitialCwd '.ralph'
$script:RalphEnvFile = Join-Path $script:RalphLocalDir '.env'

New-Item -ItemType Directory -Path $script:RalphLocalDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $script:RalphEnvFile)) { Write-DefaultEnvFile }

Read-EnvFile
if (-not (Resolve-Config)) { exit 2 }

if ([System.IO.Path]::IsPathRooted($promptFile)) {
    $script:PromptPath = $promptFile
}
else {
    $script:PromptPath = Join-Path $script:InitialCwd $promptFile
}

$stopFile = Find-StopFile
if ($stopFile) {
    Write-Output "$stopFile exists; exiting without deleting it."
    Write-Output 'Summary: iterations_executed=0 failed=0 stop_reason=stop.md_present_at_start'
    exit 0
}

$logDir = Join-Path $script:RalphLocalDir 'logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

$executed = 0
$failed = 0
$stopReason = 'max_iterations_reached'
$script:CurrentConsoleOutput = $null
$script:MemPrefix = @()
$script:MemLimitSupported = $null
$script:MemLimitWarned = $false

function Clear-CurrentConsoleOutput {
    if ($script:CurrentConsoleOutput -and (Test-Path -LiteralPath $script:CurrentConsoleOutput)) {
        Remove-Item -LiteralPath $script:CurrentConsoleOutput -Force -ErrorAction SilentlyContinue
    }
    $script:CurrentConsoleOutput = $null
}

Write-Output ("Ralph loop: {0} iteration(s), tool={1}({2}), model={3}, logs=.ralph/logs" -f `
    $script:MaxIterations, $script:RalphTool, $script:RalphModelCapability, $script:ToolModel)

try {
    for ($iteration = 1; $iteration -le $script:MaxIterations; $iteration++) {
        $stopFile = Find-StopFile
        if ($stopFile) {
            $stopReason = "stop.md_detected_before_iteration_$iteration"
            Write-Output "Detected $stopFile; stopping."
            break
        }

        Read-EnvFile
        if (-not (Resolve-Config)) {
            Write-Warning "invalid Ralph config in $($script:RalphEnvFile); keeping previous settings."
        }

        $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $iterationPadded = '{0:D6}' -f $iteration
        $logFile = Join-Path $logDir "iteration-$iterationPadded-$timestamp.log"
        $script:CurrentConsoleOutput = Join-Path $script:RalphLocalDir ("console-output-$iterationPadded." + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType File -Path $script:CurrentConsoleOutput -Force | Out-Null

        Set-Location -LiteralPath $script:InitialCwd

        $header = @(
            "ralph-loop iteration $iteration/$($script:MaxIterations)",
            "cwd: $((Get-Location).Path)",
            "started_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "tool: $($script:RalphTool)",
            "command: $($script:ToolCommand)",
            "flags: $($script:ToolFlagsString)",
            "model_capability: $($script:RalphModelCapability)",
            "model: $($script:ToolModel)",
            "thinking: $($script:RalphThinking)"
        )
        if ($script:RalphMemoryMax) { $header += "memory_max: $($script:RalphMemoryMax)" }
        if ($script:ToolReasoningEffort) { $header += "reasoning_effort: $($script:ToolReasoningEffort)" }
        if ($script:ToolThinkingBudget) { $header += "thinking_budget: $($script:ToolThinkingBudget)" }
        $header += @(
            "prompt_file: $($script:PromptPath)",
            "ralph_local_dir: $($script:RalphLocalDir)",
            "log_dir: $logDir",
            "retaining_logs: $($script:MaxLogs)",
            "invocation: $($script:ToolInvocation)",
            "---- $($script:ToolOutputLabel) output ----"
        )
        Set-Content -LiteralPath $logFile -Value $header -Encoding utf8

        $exitCode = Invoke-Tool -LogPath $logFile
        if ($exitCode -eq 0) {
            $iterationStatus = 'ok'
        }
        else {
            $failed++
            $iterationStatus = "failed exit=$exitCode"
        }

        Add-Content -LiteralPath $logFile -Value @(
            '---- ralph-loop result ----',
            "exit_code: $exitCode",
            "finished_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        )

        if ($exitCode -ne 0 -and $script:RalphSwitchOnExhaustion -eq 'true') {
            Invoke-HandleTokenExhaustion $script:RalphTool $logFile
        }

        if ((Test-Path -LiteralPath $script:CurrentConsoleOutput) -and
            (Get-Item -LiteralPath $script:CurrentConsoleOutput).Length -gt 0) {
            Get-Content -LiteralPath $script:CurrentConsoleOutput | Write-Output
        }

        if (-not [Console]::IsOutputRedirected) {
            $green = "`e[0;32m"
            $reset = "`e[0m"
        }
        else {
            $green = ''
            $reset = ''
        }
        Write-Output ("{0}=== Iteration {1}/{2} [{3}({4})] {5}; log=.ralph/logs/{6} ==={7}" -f `
            $green, $iteration, $script:MaxIterations, $script:RalphTool, $script:RalphModelCapability, `
            $iterationStatus, (Split-Path -Leaf $logFile), $reset)

        $executed++
        Remove-OldLogs $logDir $script:MaxLogs
        Clear-CurrentConsoleOutput
    }
}
finally {
    Clear-CurrentConsoleOutput
}

Write-Output "Summary: iterations_executed=$executed failed=$failed stop_reason=$stopReason"
