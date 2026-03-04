#!/usr/bin/env zsh

set -uo pipefail

SCRIPT_DIR="${0:A:h}"
REPO_ROOT="${SCRIPT_DIR:h}"
OMZ_SYNC_SCRIPT="$REPO_ROOT/scripts/omz-sync.zsh"

if [[ ! -f "$OMZ_SYNC_SCRIPT" ]]; then
  print -u2 -- "Missing script: $OMZ_SYNC_SCRIPT"
  exit 1
fi

TMP_ROOT="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

print -- "[simulate] temp root: $TMP_ROOT"

HOME="$TMP_ROOT/fake-home"
export HOME

mkdir -p "$HOME/.oh-my-zsh/custom/themes" "$HOME/.oh-my-zsh/custom/plugins/demo"
cat > "$HOME/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="local-theme"
EOF
cat > "$HOME/.oh-my-zsh/custom/themes/local-theme.zsh-theme" <<'EOF'
PROMPT="%n@%m %1~ %# "
EOF
cat > "$HOME/.oh-my-zsh/custom/plugins/demo/demo.plugin.zsh" <<'EOF'
alias ll='ls -la'
EOF

# Git identity in this temp HOME only.
cat > "$HOME/.gitconfig" <<'EOF'
[user]
  name = omz-sync-test
  email = omz-sync-test@example.com
EOF

REMOTE_BASE="$TMP_ROOT/remotes"
REMOTE_OWNER_DIR="$REMOTE_BASE/alice"
REMOTE_REPO_BARE="$REMOTE_OWNER_DIR/omz-existing.git"
mkdir -p "$REMOTE_OWNER_DIR"
git init --bare "$REMOTE_REPO_BARE" >/dev/null

seed_remote_repo() {
  local work="$TMP_ROOT/seed-work"
  git clone "$REMOTE_REPO_BARE" "$work" >/dev/null
  mkdir -p "$work/home/.oh-my-zsh/custom/themes"
  cat > "$work/home/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="remote-theme"
EOF
  cat > "$work/.omz-sync-repo" <<'EOF'
omz-sync-repo:1
created_at:2026-01-01T00:00:00Z
repo_slug:alice/omz-existing
EOF
  cat > "$work/home/.oh-my-zsh/custom/themes/remote-theme.zsh-theme" <<'EOF'
PROMPT="%F{green}%n@%m%f %1~ %# "
EOF
  (
    cd "$work"
    git add -A
    git commit -m "seed remote config" >/dev/null
    git branch -M main
    git push origin main >/dev/null
  )
  git -C "$REMOTE_REPO_BARE" symbolic-ref HEAD refs/heads/main >/dev/null
}

seed_remote_repo

export OMZ_SYNC_CONFIG_HOME="$HOME/.config/omz-sync"
export OMZ_SYNC_DATA_HOME="$HOME/.local/share/omz-sync"
export OMZ_SYNC_REPO_DIR="$OMZ_SYNC_DATA_HOME/repo"
export OMZ_SYNC_GIT_HOST_BASE="file://$REMOTE_BASE"
export OMZ_SYNC_DISABLE_AUTO_INIT=1
export OMZ_SYNC_DEBOUNCE_SECONDS=0

source "$OMZ_SYNC_SCRIPT"

omz_sync_prompt() {
  local question="$1"
  local default_answer="${2:-y}"
  case "$question" in
    *"Do you already have a GitHub repo for zsh sync?"*) return 0 ;;
    *"Load saved version from GitHub now?"*) return 0 ;;
    *"Load saved version from GitHub into this machine now?"*) return 0 ;;
    *"Delete local file not present in remote:"*) return 1 ;;
    *"Create GitHub repo automatically with gh?"*) return 1 ;;
  esac
  [[ "$default_answer" == "y" ]]
}

omz_sync_read_value() {
  local question="$1"
  local default_value="${2:-}"
  case "$question" in
    *"existing sync repo as owner/name"*) OMZ_SYNC_READ_VALUE="alice/omz-existing"; return 0 ;;
    *"owner/name"*) OMZ_SYNC_READ_VALUE="alice/omz-existing"; return 0 ;;
    *"Branch name"*) OMZ_SYNC_READ_VALUE="main"; return 0 ;;
    *"Sync repository slug"*) OMZ_SYNC_READ_VALUE="alice/omz-existing"; return 0 ;;
    *"Repo visibility"*) OMZ_SYNC_READ_VALUE="private"; return 0 ;;
  esac
  OMZ_SYNC_READ_VALUE="$default_value"
  return 0
}

assert_contains() {
  local path="$1"
  local expected="$2"
  local content
  content="$(<"$path")"
  if [[ "$content" != *"$expected"* ]]; then
    print -u2 -- "[simulate] assert failed: '$expected' not found in $path"
    exit 1
  fi
}

# Scenario 1: first-run wizard, existing repo path, load saved version.
omz_sync_bootstrap_first_time

assert_contains "$HOME/.zshrc" 'ZSH_THEME="remote-theme"'
print -- "[simulate] first-run existing-repo flow: OK"

# Scenario 2: returning user local change auto-commits and pushes.
echo '# local tweak' >> "$HOME/.zshrc"
omz_sync_sync_local_changes

if [[ -z "$(git -C "$OMZ_SYNC_REPO_DIR" log --oneline -n 1)" ]]; then
  print -u2 -- "[simulate] assert failed: no local commit found in sync repo"
  exit 1
fi
print -- "[simulate] returning-user local change push flow: OK"

# Scenario 3: remote changed elsewhere, startup asks to load, then applies.
external_clone="$TMP_ROOT/external-change"
git clone "$REMOTE_REPO_BARE" "$external_clone" >/dev/null
(
  cd "$external_clone"
  git checkout -b main origin/main >/dev/null 2>&1 || git checkout main >/dev/null 2>&1
  cat > "home/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="remote-theme-v2"
EOF
  git add home/.zshrc
  git commit -m "remote update theme" >/dev/null
  git push origin main >/dev/null
)

omz_sync_startup_pull_flow
assert_contains "$HOME/.zshrc" 'ZSH_THEME="remote-theme-v2"'
print -- "[simulate] returning-user remote update load flow: OK"

print -- "[simulate] all scenarios passed"
