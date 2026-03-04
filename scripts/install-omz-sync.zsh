#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
SOURCE_SCRIPT="$REPO_ROOT/scripts/omz-sync.zsh"
INSTALL_DIR="${OMZ_SYNC_INSTALL_DIR:-$HOME/.local/share/omz-sync}"
INSTALLED_SCRIPT="$INSTALL_DIR/omz-sync.zsh"
SNIPPET_FILE="$INSTALL_DIR/zshrc.snippet.zsh"
ZSHRC_FILE="$HOME/.zshrc"
SNIPPET_ADDED=0
SNIPPET_ALREADY_PRESENT=0
SHOW_MANUAL_SNIPPET=0

usage() {
  cat <<'EOF'
Usage: zsh ./scripts/install-omz-sync.zsh [--help]

Installs omz-sync into your home directory and offers to add
the bootstrap snippet to ~/.zshrc.

Environment variables:
  OMZ_SYNC_INSTALL_DIR   Install location (default: ~/.local/share/omz-sync)

Examples:
  zsh ./scripts/install-omz-sync.zsh
  OMZ_SYNC_INSTALL_DIR="$HOME/.local/opt/omz-sync" zsh ./scripts/install-omz-sync.zsh
EOF
}

render_snippet() {
  cat <<EOF
# omz-sync bootstrap
_omz_sync_install_dir="\${OMZ_SYNC_INSTALL_DIR:-$INSTALL_DIR}"
if [[ -f "\$_omz_sync_install_dir/omz-sync.zsh" ]]; then
  # Allow re-running setup in the same shell after uninstall/reset.
  unset OMZ_SYNC_LOADED
  source "\$_omz_sync_install_dir/omz-sync.zsh"
fi
unset _omz_sync_install_dir
EOF
}

while (( $# > 0 )); do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[omz-sync installer] Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

prompt_yes_no() {
  local question="$1"
  local default="${2:-y}"
  local suffix="[Y/n]"
  local answer
  if [[ "$default" == "n" ]]; then
    suffix="[y/N]"
  fi
  while true; do
    echo -n "[omz-sync installer] $question $suffix "
    if ! read -r answer; then
      echo
      answer="$default"
    fi
    answer="${answer:l}"
    [[ -z "$answer" ]] && answer="$default"
    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) echo "[omz-sync installer] Please answer Y or N" ;;
    esac
  done
}

if [[ ! -f "$SOURCE_SCRIPT" ]]; then
  echo "[omz-sync installer] missing source script: $SOURCE_SCRIPT" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp -f "$SOURCE_SCRIPT" "$INSTALLED_SCRIPT"
chmod +x "$INSTALLED_SCRIPT"

render_snippet > "$SNIPPET_FILE"

echo
cat <<'EOF'
[omz-sync installer] Snippet that can be added to ~/.zshrc:
EOF
echo
render_snippet
echo
if prompt_yes_no "Do you want to add the snippet to $ZSHRC_FILE automatically?" "y"; then
  if [[ ! -f "$ZSHRC_FILE" ]]; then
    touch "$ZSHRC_FILE"
  fi

  ZSHRC_CONTENT="$(<"$ZSHRC_FILE")"
  if [[ "$ZSHRC_CONTENT" == *'# omz-sync bootstrap'* ]] \
    || [[ "$ZSHRC_CONTENT" == *'source "$HOME/.local/share/omz-sync/omz-sync.zsh"'* ]] \
    || [[ "$ZSHRC_CONTENT" == *'source "$_omz_sync_install_dir/omz-sync.zsh"'* ]]; then
    echo "[omz-sync installer] Snippet already present in $ZSHRC_FILE"
    SNIPPET_ALREADY_PRESENT=1
  else
    {
      echo
      cat "$SNIPPET_FILE"
    } >> "$ZSHRC_FILE"
    echo "[omz-sync installer] Snippet added to $ZSHRC_FILE"
    SNIPPET_ADDED=1
  fi
else
  echo "[omz-sync installer] Skipped automatic snippet insertion."
  SHOW_MANUAL_SNIPPET=1
fi

if (( SHOW_MANUAL_SNIPPET == 1 )); then
  echo "[omz-sync installer] Add the snippet shown above to ~/.zshrc"
elif (( SNIPPET_ADDED == 1 || SNIPPET_ALREADY_PRESENT == 1 )); then
  echo "[omz-sync installer] Snippet is configured in ~/.zshrc"
fi

cat <<EOF
[omz-sync installer] Installed script to:
  $INSTALLED_SCRIPT

The snippet has also been written to:
  $SNIPPET_FILE

After install, run:
  source ~/.zshrc
EOF
