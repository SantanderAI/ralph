# Copyright (c) 2026 Santander Group
# SPDX-License-Identifier: Apache-2.0

install_dir := env_var_or_default("HOME", "") / ".local/bin"
script := "ralph-loop.sh"

codex_home := env_var_or_default("CODEX_HOME", env_var("HOME") / ".codex")
skill_targets := env_var("HOME") / ".claude/skills" + " " \
    + codex_home / "skills" + " " \
    + env_var("HOME") / ".gemini/antigravity-cli/skills"

# Install ralph-loop.sh to $HOME/.local/bin
install:
    @mkdir -p {{ install_dir }}
    @cp {{ script }} {{ install_dir }}/{{ script }}
    @chmod +x {{ install_dir }}/{{ script }}
    @echo "Installed to {{ install_dir }}/{{ script }}"
    @if ! echo "$PATH" | tr ':' '\n' | grep -qx "{{ install_dir }}"; then \
        echo ""; \
        echo "WARNING: {{ install_dir }} is not in your PATH."; \
        echo "Add the following line to your shell config (~/.zshrc or ~/.bashrc):"; \
        echo ""; \
        echo "  export PATH=\"{{ install_dir }}:\$PATH\""; \
        echo ""; \
    fi

# Copy all skills/ to Claude Code, Codex CLI and Antigravity CLI (user-level)
skills-sync:
    @set -eu; \
    skills=$(for d in skills/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done); \
    if [ -z "$skills" ]; then echo "No skills found under skills/<name>/SKILL.md" >&2; exit 1; fi; \
    for target in {{ skill_targets }}; do \
        mkdir -p "$target"; \
        for name in $skills; do \
            rm -rf "$target/$name"; \
            if command -v rsync >/dev/null 2>&1; then \
                rsync -a --delete "skills/$name/" "$target/$name/"; \
            else \
                mkdir -p "$target/$name"; cp -R "skills/$name/." "$target/$name/"; \
            fi; \
            echo "  ✓ $name → $target/$name"; \
        done; \
    done; \
    echo; echo "Done. Restart Codex and Antigravity to pick up the skills."

# Alias of skills-sync
skills-install: skills-sync

# Show whether each tool has each skill installed and matching the repo
skills-status:
    @set -eu; \
    skills=$(for d in skills/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done); \
    echo "Skills in repo: $skills"; echo; \
    for target in {{ skill_targets }}; do \
        echo "[$target]"; \
        if [ ! -d "$target" ]; then echo "  (directory does not exist)"; continue; fi; \
        for name in $skills; do \
            if [ -f "$target/$name/SKILL.md" ]; then \
                if diff -rq "skills/$name" "$target/$name" >/dev/null 2>&1; then \
                    echo "  ✓ $name (up to date)"; \
                else \
                    echo "  ~ $name (differs from repo — re-run 'just skills-sync')"; \
                fi; \
            else \
                echo "  ✗ $name (not installed)"; \
            fi; \
        done; \
    done

# Remove from each tool only the skills defined in this repo
skills-uninstall:
    @set -eu; \
    skills=$(for d in skills/*/; do [ -f "$d/SKILL.md" ] && basename "$d"; done); \
    removed=0; \
    for target in {{ skill_targets }}; do \
        [ -d "$target" ] || continue; \
        for name in $skills; do \
            if [ -d "$target/$name" ]; then \
                rm -rf "$target/$name"; \
                echo "  ✓ removed $target/$name"; \
                removed=1; \
            fi; \
        done; \
    done; \
    [ "$removed" -eq 0 ] && echo "Nothing to remove."; \
    echo "Done. Restart Codex and Antigravity."
