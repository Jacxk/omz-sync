#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SOURCE_SCRIPT="$REPO_ROOT/scripts/omz-sync.zsh"
INSTALL_DIR="${OMZ_SYNC_INSTALL_DIR:-$HOME/.local/share/omz-sync}"
INSTALLED_SCRIPT="$INSTALL_DIR/omz-sync.zsh"
SNIPPET_FILE="$INSTALL_DIR/zshrc.snippet.zsh"
ZSHRC_FILE="$HOME/.zshrc"

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

echo
echo "[omz-sync installer] Do you want to add the snippet to $ZSHRC_FILE automatically? [Y/n]"
read -r ADD_SNIPPET
ADD_SNIPPET="${ADD_SNIPPET:-y}"

if [[ "${ADD_SNIPPET:l}" == "y" || "${ADD_SNIPPET:l}" == "yes" ]]; then
  if [[ ! -f "$ZSHRC_FILE" ]]; then
    touch "$ZSHRC_FILE"
  fi

  ZSHRC_CONTENT="$(<"$ZSHRC_FILE")"
  if [[ "$ZSHRC_CONTENT" == *'source "$HOME/.local/share/omz-sync/omz-sync.zsh"'* ]]; then
    echo "[omz-sync installer] Snippet already present in $ZSHRC_FILE"
  else
    {
      echo
      cat "$SNIPPET_FILE"
    } >> "$ZSHRC_FILE"
    echo "[omz-sync installer] Snippet added to $ZSHRC_FILE"
  fi
else
  echo "[omz-sync installer] Skipped automatic snippet insertion."
fi

cat <<EOF
[omz-sync installer] Installed script to:
  $INSTALLED_SCRIPT

Add this snippet to your ~/.zshrc:

if [[ -f "\$HOME/.local/share/omz-sync/omz-sync.zsh" ]]; then
  source "\$HOME/.local/share/omz-sync/omz-sync.zsh"
fi

The snippet has also been written to:
  $SNIPPET_FILE

After install, run:
  source ~/.zshrc
EOF
