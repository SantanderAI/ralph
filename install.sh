#!/bin/sh
# ralph installer / updater — no dependencies beyond curl + tar.
#
# Installs ralph-loop.sh to ~/.local/bin and copies the bundled skills
# (juez, maestro, ralph) into Claude Code, Codex CLI and Antigravity CLI,
# exactly like `just install` + `just skills-install`, but without `just`.
#
# Quick use:
#   curl -fsSL https://raw.githubusercontent.com/SantanderAI/ralph/main/install.sh | sh
#
# Options (flags or env vars):
#   --no-skills            Install only the script, skip skills.
#                          (env: RALPH_SKIP_SKILLS=1)
#   --ref <branch|tag>     Git ref to install from.      (env: RALPH_REF, default: main)
#   --repo <owner/name>    Source repository.            (env: RALPH_REPO, default: SantanderAI/ralph)
#   --install-dir <dir>    Where to put the script.      (env: RALPH_INSTALL_DIR, default: ~/.local/bin)
#
# Examples:
#   curl -fsSL .../install.sh | sh -s -- --no-skills
#   RALPH_REF=dev curl -fsSL .../install.sh | sh

set -eu

REPO="${RALPH_REPO:-SantanderAI/ralph}"
REF="${RALPH_REF:-main}"
INSTALL_DIR="${RALPH_INSTALL_DIR:-$HOME/.local/bin}"
SKIP_SKILLS="${RALPH_SKIP_SKILLS:-0}"
SCRIPT="ralph-loop.sh"

while [ $# -gt 0 ]; do
    case "$1" in
        --no-skills) SKIP_SKILLS=1 ;;
        --ref) REF="${2:?--ref needs a value}"; shift ;;
        --repo) REPO="${2:?--repo needs a value}"; shift ;;
        --install-dir) INSTALL_DIR="${2:?--install-dir needs a value}"; shift ;;
        -h|--help) sed -n '2,25p' "$0" 2>/dev/null || echo "See header of install.sh"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

for dep in curl tar; do
    command -v "$dep" >/dev/null 2>&1 || { echo "Error: '$dep' is required." >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "Fetching $REPO@$REF ..."
url="https://codeload.github.com/$REPO/tar.gz/$REF"
if ! curl -fsSL "$url" -o "$tmp/src.tar.gz"; then
    echo "Error: download failed (does ref '$REF' exist in $REPO?): $url" >&2
    exit 1
fi
if ! tar xzf "$tmp/src.tar.gz" -C "$tmp"; then
    echo "Error: could not extract the downloaded archive." >&2
    exit 1
fi
rm -f "$tmp/src.tar.gz"

src="$tmp/$(ls -1 "$tmp" | head -n1)"
if [ ! -f "$src/$SCRIPT" ]; then
    echo "Error: $SCRIPT not found in the downloaded archive." >&2
    exit 1
fi

# --- Install the script -----------------------------------------------------
mkdir -p "$INSTALL_DIR"
cp "$src/$SCRIPT" "$INSTALL_DIR/$SCRIPT"
chmod +x "$INSTALL_DIR/$SCRIPT"
echo "Installed $INSTALL_DIR/$SCRIPT"

case ":$PATH:" in
    *":$INSTALL_DIR:"*) ;;
    *)
        echo ""
        echo "WARNING: $INSTALL_DIR is not in your PATH."
        echo "Add this to your shell config (~/.zshrc or ~/.bashrc):"
        echo ""
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        echo ""
        ;;
esac

# --- Install the skills -----------------------------------------------------
if [ "$SKIP_SKILLS" = "1" ]; then
    echo "Skipping skills (--no-skills)."
    exit 0
fi

if [ ! -d "$src/skills" ]; then
    echo "No skills/ directory in the archive; nothing else to do."
    exit 0
fi

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SKILL_TARGETS="$HOME/.claude/skills $CODEX_HOME/skills $HOME/.gemini/antigravity-cli/skills"

installed_any=0
for dir in "$src"/skills/*/; do
    [ -f "$dir/SKILL.md" ] || continue
    name="$(basename "$dir")"
    for target in $SKILL_TARGETS; do
        mkdir -p "$target"
        rm -rf "$target/$name"
        if command -v rsync >/dev/null 2>&1; then
            rsync -a "$dir" "$target/$name/"
        else
            mkdir -p "$target/$name"
            cp -R "$dir." "$target/$name/"
        fi
        echo "  skill $name -> $target/$name"
        installed_any=1
    done
done

if [ "$installed_any" -eq 0 ]; then
    echo "No skills found under skills/<name>/SKILL.md."
else
    echo ""
    echo "Done. Restart Codex and Antigravity to pick up the skills."
fi
