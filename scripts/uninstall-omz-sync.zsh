#!/usr/bin/env zsh

set -euo pipefail

INSTALL_DIR="${OMZ_SYNC_INSTALL_DIR:-$HOME/.local/share/omz-sync}"
CONFIG_DIR="${OMZ_SYNC_CONFIG_HOME:-$HOME/.config/omz-sync}"
ZSHRC_FILE="${OMZ_SYNC_ZSHRC_FILE:-$HOME/.zshrc}"
SNIPPET_LINE='source "$HOME/.local/share/omz-sync/omz-sync.zsh"'

confirm() {
  local question="$1"
  local default="${2:-y}"
  local suffix="[y/N]"
  local answer
  if [[ "$default" == "y" ]]; then
    suffix="[Y/n]"
  fi
  while true; do
    echo -n "[omz-sync uninstall] $question $suffix "
    if ! read -r answer; then
      echo
      answer="$default"
    fi
    answer="${answer:l}"
    [[ -z "$answer" ]] && answer="$default"
    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "[omz-sync uninstall] Please answer y or n" ;;
    esac
  done
}

remove_snippet_from_zshrc() {
  local src="$1"
  local tmp="${src}.omzsync.tmp"
  local changed=0

  awk '
    BEGIN {
      in_block=0
    }
    {
      if (in_block == 1) {
        if ($0 ~ /^[[:space:]]*fi[[:space:]]*$/) {
          in_block=0
          next
        }
        next
      }

      if ($0 ~ /^[[:space:]]*# omz-sync bootstrap[[:space:]]*$/) {
        in_block=1
        next
      }

      if ($0 ~ /^[[:space:]]*if[[:space:]]+\[\[[[:space:]]+-f[[:space:]]+"\$HOME\/\.local\/share\/omz-sync\/omz-sync\.zsh"[[:space:]]+\]\];[[:space:]]*then[[:space:]]*$/) {
        in_block=1
        next
      }

      if (index($0, "source \"$HOME/.local/share/omz-sync/omz-sync.zsh\"") > 0) {
        next
      }

      print $0
    }
  ' "$src" > "$tmp"

  if ! cmp -s "$src" "$tmp"; then
    mv "$tmp" "$src"
    changed=1
  else
    rm -f "$tmp"
  fi

  if (( changed == 1 )); then
    return 0
  fi
  return 1
}

echo "[omz-sync uninstall] This can remove:"
echo "  - bootstrap lines from $ZSHRC_FILE"
echo "  - installed files from $INSTALL_DIR"
echo "  - sync state from $CONFIG_DIR"
echo

if [[ -f "$ZSHRC_FILE" ]]; then
  if confirm "Remove omz-sync snippet from $ZSHRC_FILE?" "y"; then
    if remove_snippet_from_zshrc "$ZSHRC_FILE"; then
      echo "[omz-sync uninstall] Removed snippet from $ZSHRC_FILE"
    else
      echo "[omz-sync uninstall] Snippet not found in $ZSHRC_FILE"
    fi
  fi
else
  echo "[omz-sync uninstall] $ZSHRC_FILE does not exist, skipping snippet removal"
fi

if [[ -d "$INSTALL_DIR" ]]; then
  if confirm "Delete installed files in $INSTALL_DIR?" "y"; then
    rm -rf "$INSTALL_DIR"
    echo "[omz-sync uninstall] Deleted $INSTALL_DIR"
  fi
else
  echo "[omz-sync uninstall] $INSTALL_DIR does not exist, skipping"
fi

if [[ -d "$CONFIG_DIR" ]]; then
  if confirm "Delete sync state in $CONFIG_DIR (includes backups)?" "n"; then
    rm -rf "$CONFIG_DIR"
    echo "[omz-sync uninstall] Deleted $CONFIG_DIR"
  fi
else
  echo "[omz-sync uninstall] $CONFIG_DIR does not exist, skipping"
fi

echo
echo "[omz-sync uninstall] Done"
echo "[omz-sync uninstall] Run: source ~/.zshrc"
echo "[omz-sync uninstall] To start over: zsh ./scripts/install-omz-sync.zsh"
