#!/usr/bin/env pwsh
# Copyright (c) 2026 César Gallego Rodríguez
# SPDX-License-Identifier: Apache-2.0
#
# ralph installer / updater for PowerShell (pwsh 6+).
#
# Installs ralph-loop.ps1 to ~/.local/bin and copies the bundled skills
# (juez, maestro, ralph) into Claude Code, Codex CLI and Antigravity CLI,
# mirroring install.sh. Re-run it any time to update.
#
# Quick use:
#   powershell -c "irm https://raw.githubusercontent.com/SantanderAI/ralph/main/install.ps1 | iex"
#
# Configuration via environment variables (works with the `irm | iex` form):
#   RALPH_SKIP_SKILLS   Set to 1 to install only the script, skipping skills.
#   RALPH_REF           Git ref to install from.        (default: main)
#   RALPH_REPO          Source repository.              (default: SantanderAI/ralph)
#   RALPH_INSTALL_DIR   Where to put the script.        (default: ~/.local/bin)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo       = if ($env:RALPH_REPO) { $env:RALPH_REPO } else { 'SantanderAI/ralph' }
$ref        = if ($env:RALPH_REF)  { $env:RALPH_REF }  else { 'main' }
$installDir = if ($env:RALPH_INSTALL_DIR) { $env:RALPH_INSTALL_DIR } else { Join-Path $HOME '.local/bin' }
$skipSkills = [bool]($env:RALPH_SKIP_SKILLS) -and ($env:RALPH_SKIP_SKILLS -ne '0')
$scriptName = 'ralph-loop.ps1'

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ralph-' + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'src.zip'
    $url = "https://codeload.github.com/$repo/zip/$ref"
    Write-Host "Fetching $repo@$ref ..."
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip
    } catch {
        throw "Download failed (does ref '$ref' exist in $repo?): $url"
    }
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    Remove-Item -Path $zip -Force

    $src = Get-ChildItem -Path $tmp -Directory | Select-Object -First 1
    if (-not $src) { throw 'Unexpected archive layout: no extracted directory.' }

    # --- Install the script -------------------------------------------------
    $scriptPath = Join-Path $src.FullName $scriptName
    if (-not (Test-Path -Path $scriptPath)) {
        throw "$scriptName not found in the downloaded archive."
    }
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    $dest = Join-Path $installDir $scriptName
    Copy-Item -Path $scriptPath -Destination $dest -Force
    Write-Host "Installed $dest"

    $paths = $env:PATH -split [System.IO.Path]::PathSeparator
    if ($paths -notcontains $installDir) {
        $sep = [System.IO.Path]::PathSeparator
        Write-Host ''
        Write-Host "WARNING: $installDir is not in your PATH."
        Write-Host 'Add it to your PowerShell profile:'
        Write-Host ''
        Write-Host "  `$env:PATH = `"$installDir$sep`$env:PATH`""
        Write-Host ''
    }

    # --- Install the skills -------------------------------------------------
    if ($skipSkills) {
        Write-Host 'Skipping skills (RALPH_SKIP_SKILLS).'
        return
    }

    $skillsRoot = Join-Path $src.FullName 'skills'
    if (-not (Test-Path -Path $skillsRoot)) {
        Write-Host 'No skills/ directory in the archive; nothing else to do.'
        return
    }

    $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
    $targets = @(
        (Join-Path $HOME '.claude/skills'),
        (Join-Path $codexHome 'skills'),
        (Join-Path $HOME '.gemini/antigravity-cli/skills')
    )

    $installedAny = $false
    foreach ($skillDir in Get-ChildItem -Path $skillsRoot -Directory) {
        if (-not (Test-Path -Path (Join-Path $skillDir.FullName 'SKILL.md'))) { continue }
        $name = $skillDir.Name
        foreach ($target in $targets) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            $skillDest = Join-Path $target $name
            if (Test-Path -Path $skillDest) {
                Remove-Item -Path $skillDest -Recurse -Force
            }
            Copy-Item -Path $skillDir.FullName -Destination $skillDest -Recurse -Force
            Write-Host "  skill $name -> $skillDest"
            $installedAny = $true
        }
    }

    if ($installedAny) {
        Write-Host ''
        Write-Host 'Done. Restart Codex and Antigravity to pick up the skills.'
    } else {
        Write-Host 'No skills found under skills/<name>/SKILL.md.'
    }
}
finally {
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
