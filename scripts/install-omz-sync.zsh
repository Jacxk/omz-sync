#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SOURCE_SCRIPT="$REPO_ROOT/scripts/omz-sync.zsh"
INSTALL_DIR="${OMZ_SYNC_INSTALL_DIR:-$HOME/.local/share/omz-sync}"
INSTALLED_SCRIPT="$INSTALL_DIR/omz-sync.zsh"
SNIPPET_FILE="$INSTALL_DIR/zshrc.snippet.zsh"

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
  echo "[omz-sync installer] missing source script: $SOURCE_SCRIPT" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp -f "$SOURCE_SCRIPT" "$INSTALLED_SCRIPT"
chmod +x "$INSTALLED_SCRIPT"

cat > "$SNIPPET_FILE" <<'EOF'
# omz-sync bootstrap
if [[ -f "$HOME/.local/share/omz-sync/omz-sync.zsh" ]]; then
  source "$HOME/.local/share/omz-sync/omz-sync.zsh"
fi
EOF

cat <<EOF
[omz-sync installer] Installed script to:
  $INSTALLED_SCRIPT

Add this snippet to your ~/.zshrc:

if [[ -f "\$HOME/.local/share/omz-sync/omz-sync.zsh" ]]; then
  source "\$HOME/.local/share/omz-sync/omz-sync.zsh"
fi

The snippet has also been written to:
  $SNIPPET_FILE
EOF
