#!/usr/bin/env zsh

# omz-sync
# Sync Oh My Zsh related files with a GitHub repository.
# This file is designed to be sourced from ~/.zshrc.

if [[ -n "${OMZ_SYNC_LOADED:-}" ]]; then
  return 0
fi
typeset -g OMZ_SYNC_LOADED=1

setopt localoptions no_nomatch

typeset -g OMZ_SYNC_CONFIG_HOME="${OMZ_SYNC_CONFIG_HOME:-$HOME/.config/omz-sync}"
typeset -g OMZ_SYNC_DATA_HOME="${OMZ_SYNC_DATA_HOME:-$HOME/.local/share/omz-sync}"
typeset -g OMZ_SYNC_REPO_DIR="${OMZ_SYNC_REPO_DIR:-$OMZ_SYNC_DATA_HOME/repo}"
typeset -g OMZ_SYNC_GIT_HOST_BASE="${OMZ_SYNC_GIT_HOST_BASE:-https://github.com}"
typeset -g OMZ_SYNC_REPO_MARKER_FILE="${OMZ_SYNC_REPO_MARKER_FILE:-.omz-sync-repo}"
typeset -g OMZ_SYNC_CONFIG_FILE="$OMZ_SYNC_CONFIG_HOME/config.zsh"
typeset -g OMZ_SYNC_TRACKED_FILE="$OMZ_SYNC_CONFIG_HOME/tracked_paths"
typeset -g OMZ_SYNC_LAST_HEAD_FILE="$OMZ_SYNC_CONFIG_HOME/last_remote_head"
typeset -g OMZ_SYNC_LOCK_DIR="$OMZ_SYNC_CONFIG_HOME/.lock"
typeset -g OMZ_SYNC_SETUP_STATE_FILE="$OMZ_SYNC_CONFIG_HOME/setup_state.zsh"
typeset -g OMZ_SYNC_LAST_COMMIT_EPOCH=0
typeset -g OMZ_SYNC_DEBOUNCE_SECONDS="${OMZ_SYNC_DEBOUNCE_SECONDS:-30}"
typeset -g OMZ_SYNC_HOOKS_REGISTERED="${OMZ_SYNC_HOOKS_REGISTERED:-0}"
typeset -g OMZ_SYNC_READ_VALUE=""
typeset -g OMZ_SYNC_PUBLISH_ENABLED="${OMZ_SYNC_PUBLISH_ENABLED:-1}"

omz_sync_log() {
  print -r -- "[omz-sync] $*"
}

omz_sync_warn() {
  print -r -- "[omz-sync] warning: $*" >&2
}

omz_sync_prompt() {
  local question="$1"
  local default="${2:-y}"
  local answer
  local suffix="[y/N]"
  if [[ "$default" == "y" ]]; then
    suffix="[Y/n]"
  fi
  while true; do
    print -n -- "[omz-sync] $question $suffix "
    if ! read -r answer; then
      print
      omz_sync_warn "Input unavailable; using default '$default'."
      answer="$default"
    fi
    answer="${answer:l}"
    if [[ -z "$answer" ]]; then
      answer="$default"
    fi
    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
      *) omz_sync_log "Please answer y or n." ;;
    esac
  done
}

omz_sync_read_value() {
  local question="$1"
  local default_value="${2:-}"
  local answer
  if [[ -n "$default_value" ]]; then
    print -n -- "[omz-sync] $question [$default_value] "
  else
    print -n -- "[omz-sync] $question "
  fi
  if ! read -r answer; then
    print
    omz_sync_warn "Input unavailable for prompt: $question"
    return 1
  fi
  if [[ -z "$answer" ]]; then
    answer="$default_value"
  fi
  OMZ_SYNC_READ_VALUE="$answer"
  return 0
}

omz_sync_require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    omz_sync_warn "Required command not found: $cmd"
    return 1
  fi
  return 0
}

omz_sync_repo_path_for_local() {
  local local_path="$1"
  local rel="${local_path#$HOME/}"
  if [[ "$local_path" == "$HOME" ]]; then
    rel="."
  fi
  print -r -- "$OMZ_SYNC_REPO_DIR/home/$rel"
}

omz_sync_mkdir_parent() {
  local p="$1"
  mkdir -p "${p:h}" 2>/dev/null
}

omz_sync_is_glob_pattern() {
  local s="$1"
  [[ "$s" == *"*"* || "$s" == *"?"* || "$s" == *"["* || "$s" == *"]"* ]]
}

omz_sync_write_default_tracked() {
  mkdir -p "$OMZ_SYNC_CONFIG_HOME" || return 1
  cat > "$OMZ_SYNC_TRACKED_FILE" <<'EOF'
# One path per line. Use absolute paths.
# Supports globs (for example: ~/.oh-my-zsh/custom/themes/**/*.zsh-theme)
~/.zshrc
~/.zshenv
~/.p10k.zsh
~/.oh-my-zsh/custom/themes/**/*
~/.oh-my-zsh/custom/plugins/**/*
~/.oh-my-zsh/custom/*.zsh
EOF
}

omz_sync_expand_tracked_paths() {
  local line expanded
  local -a results
  if [[ ! -f "$OMZ_SYNC_TRACKED_FILE" ]]; then
    omz_sync_write_default_tracked || return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    if [[ "$line" == "~"* ]]; then
      expanded="${line/#\~/$HOME}"
    else
      expanded="$line"
    fi
    if omz_sync_is_glob_pattern "$expanded"; then
      local -a globbed
      globbed=(${~expanded}(N))
      if (( ${#globbed[@]} > 0 )); then
        results+=("${globbed[@]}")
      fi
    else
      results+=("$expanded")
    fi
  done < "$OMZ_SYNC_TRACKED_FILE"

  # Deduplicate while preserving order.
  local -A seen
  local p
  for p in "${results[@]}"; do
    if [[ -z "${seen[$p]:-}" ]]; then
      seen[$p]=1
      print -r -- "$p"
    fi
  done
}

omz_sync_copy_local_to_repo() {
  local local_path repo_path
  while IFS= read -r local_path || [[ -n "$local_path" ]]; do
    [[ -z "$local_path" ]] && continue
    repo_path="$(omz_sync_repo_path_for_local "$local_path")"
    if [[ -e "$local_path" ]]; then
      if [[ -d "$local_path" ]]; then
        mkdir -p "$repo_path"
      else
        omz_sync_mkdir_parent "$repo_path"
        cp -f "$local_path" "$repo_path"
      fi
    else
      rm -f "$repo_path" 2>/dev/null
      rmdir -p "${repo_path:h}" 2>/dev/null || true
    fi
  done
}

omz_sync_backup_local_path() {
  local local_path="$1"
  local backup_root="$OMZ_SYNC_CONFIG_HOME/backups/$(date +%Y%m%d-%H%M%S)"
  local backup_path="$backup_root/${local_path#$HOME/}"
  if [[ -e "$local_path" ]]; then
    mkdir -p "${backup_path:h}" || return 1
    cp -f "$local_path" "$backup_path" || return 1
    omz_sync_log "Backup saved: $backup_path"
  fi
  return 0
}

omz_sync_show_changes_vs_repo() {
  local local_path repo_path
  local changed=0
  while IFS= read -r local_path || [[ -n "$local_path" ]]; do
    [[ -z "$local_path" ]] && continue
    repo_path="$(omz_sync_repo_path_for_local "$local_path")"
    if [[ -e "$local_path" && ! -e "$repo_path" ]]; then
      print -r -- "  + local only    ${local_path#$HOME/}"
      changed=1
    elif [[ ! -e "$local_path" && -e "$repo_path" ]]; then
      print -r -- "  + remote only   ${local_path#$HOME/}"
      changed=1
    elif [[ -f "$local_path" && -f "$repo_path" ]]; then
      if ! cmp -s "$local_path" "$repo_path"; then
        print -r -- "  ~ modified      ${local_path#$HOME/}"
        changed=1
      fi
    fi
  done
  return $changed
}

omz_sync_apply_repo_to_local() {
  local local_path repo_path
  while IFS= read -r local_path || [[ -n "$local_path" ]]; do
    [[ -z "$local_path" ]] && continue
    repo_path="$(omz_sync_repo_path_for_local "$local_path")"
    if [[ -f "$repo_path" ]]; then
      omz_sync_backup_local_path "$local_path" || return 1
      omz_sync_mkdir_parent "$local_path"
      cp -f "$repo_path" "$local_path" || return 1
    elif [[ ! -e "$repo_path" && -e "$local_path" ]]; then
      if omz_sync_prompt "Delete local file not present in remote: ${local_path#$HOME/}?" "n"; then
        omz_sync_backup_local_path "$local_path" || return 1
        rm -f "$local_path" || return 1
      fi
    fi
  done
}

omz_sync_fetch_remote() {
  if [[ "${OMZ_SYNC_PUBLISH_ENABLED:-1}" != "1" ]]; then
    return 0
  fi
  (
    cd "$OMZ_SYNC_REPO_DIR" || return 1
    git fetch origin --prune >/dev/null 2>&1 || return 1
  )
}

omz_sync_remote_head() {
  if [[ "${OMZ_SYNC_PUBLISH_ENABLED:-1}" != "1" ]]; then
    return 0
  fi
  (
    cd "$OMZ_SYNC_REPO_DIR" || return 1
    git rev-parse "origin/$OMZ_SYNC_BRANCH" 2>/dev/null
  )
}

omz_sync_local_head() {
  (
    cd "$OMZ_SYNC_REPO_DIR" || return 1
    git rev-parse HEAD 2>/dev/null
  )
}

omz_sync_checkout_remote_branch() {
  if [[ "${OMZ_SYNC_PUBLISH_ENABLED:-1}" != "1" ]]; then
    return 0
  fi
  (
    cd "$OMZ_SYNC_REPO_DIR" || return 1
    if git show-ref --verify --quiet "refs/remotes/origin/$OMZ_SYNC_BRANCH"; then
      if git show-ref --verify --quiet "refs/heads/$OMZ_SYNC_BRANCH"; then
        git checkout -q "$OMZ_SYNC_BRANCH" >/dev/null 2>&1 || return 1
      else
        git checkout -q -b "$OMZ_SYNC_BRANCH" "origin/$OMZ_SYNC_BRANCH" >/dev/null 2>&1 || return 1
      fi
      git branch --set-upstream-to="origin/$OMZ_SYNC_BRANCH" "$OMZ_SYNC_BRANCH" >/dev/null 2>&1 || true
      git reset --hard "origin/$OMZ_SYNC_BRANCH" >/dev/null 2>&1 || return 1
    else
      git checkout -q "$OMZ_SYNC_BRANCH" >/dev/null 2>&1 || git checkout -q -b "$OMZ_SYNC_BRANCH" >/dev/null 2>&1 || return 1
    fi
  )
}

omz_sync_acquire_lock() {
  if mkdir "$OMZ_SYNC_LOCK_DIR" 2>/dev/null; then
    print -r -- "$$" > "$OMZ_SYNC_LOCK_DIR/pid"
    return 0
  fi
  return 1
}

omz_sync_release_lock() {
  rm -rf "$OMZ_SYNC_LOCK_DIR" 2>/dev/null || true
}

omz_sync_commit_and_push() {
  local reason="${1:-sync}"
  (
    cd "$OMZ_SYNC_REPO_DIR" || return 1
    git add -A -- home >/dev/null 2>&1 || true
    if [[ -f "$OMZ_SYNC_REPO_MARKER_FILE" ]]; then
      git add -- "$OMZ_SYNC_REPO_MARKER_FILE" >/dev/null 2>&1 || true
    fi
    local scope_status
    scope_status="$(git status --porcelain -- home "$OMZ_SYNC_REPO_MARKER_FILE" 2>/dev/null)"
    if [[ -z "$scope_status" ]]; then
      return 0
    fi
    local changed_files
    changed_files="$(print -r -- "$scope_status" | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')"
    local msg="omz-sync: $reason ($(date '+%Y-%m-%d %H:%M:%S'))"
    if [[ -n "$changed_files" ]]; then
      msg="$msg files: $changed_files"
    fi
    git commit -m "$msg" >/dev/null 2>&1 || return 1
    if [[ "${OMZ_SYNC_PUBLISH_ENABLED:-1}" == "1" ]]; then
      git push origin "$OMZ_SYNC_BRANCH" >/dev/null 2>&1 || return 1
    fi
  )
}

omz_sync_sync_local_changes() {
  local now
  now="$(date +%s)"
  if (( now - OMZ_SYNC_LAST_COMMIT_EPOCH < OMZ_SYNC_DEBOUNCE_SECONDS )); then
    return 0
  fi
  if ! omz_sync_acquire_lock; then
    return 0
  fi

  local tracked_list
  tracked_list="$(omz_sync_expand_tracked_paths)" || {
    omz_sync_release_lock
    return 1
  }

  print -r -- "$tracked_list" | omz_sync_copy_local_to_repo
  if omz_sync_commit_and_push "local change"; then
    OMZ_SYNC_LAST_COMMIT_EPOCH="$now"
  fi
  omz_sync_release_lock
}

omz_sync_startup_pull_flow() {
  local auto_apply="${1:-0}"
  if ! omz_sync_acquire_lock; then
    return 0
  fi

  omz_sync_fetch_remote || {
    omz_sync_warn "Could not fetch remote repository."
    omz_sync_release_lock
    return 1
  }

  local remote_head local_head last_seen
  remote_head="$(omz_sync_remote_head)"
  local_head="$(omz_sync_local_head)"
  last_seen=""
  if [[ -f "$OMZ_SYNC_LAST_HEAD_FILE" ]]; then
    last_seen="$(<"$OMZ_SYNC_LAST_HEAD_FILE")"
  fi

  if [[ -n "$remote_head" && "$remote_head" != "$local_head" ]]; then
    omz_sync_checkout_remote_branch || omz_sync_warn "Remote checkout/pull failed."
  fi

  local tracked_list
  tracked_list="$(omz_sync_expand_tracked_paths)" || {
    omz_sync_release_lock
    return 1
  }

  local changes
  changes="$(print -r -- "$tracked_list" | omz_sync_show_changes_vs_repo)"
  if [[ -n "$changes" ]]; then
    omz_sync_log "Detected differences between local files and saved GitHub version:"
    print -r -- "$changes"
    if [[ "$auto_apply" == "1" ]] || omz_sync_prompt "Load saved version from GitHub into this machine now?" "n"; then
      print -r -- "$tracked_list" | omz_sync_apply_repo_to_local || {
        omz_sync_warn "Failed while applying remote files."
      }
    fi
  elif [[ -n "$remote_head" && "$remote_head" != "$last_seen" ]]; then
    omz_sync_log "Remote updated to $remote_head and local files are already in sync."
  fi

  if [[ -n "$remote_head" ]]; then
    print -r -- "$remote_head" > "$OMZ_SYNC_LAST_HEAD_FILE"
  fi
  omz_sync_release_lock
}

omz_sync_write_config() {
  mkdir -p "$OMZ_SYNC_CONFIG_HOME" "$OMZ_SYNC_DATA_HOME" || return 1
  cat > "$OMZ_SYNC_CONFIG_FILE" <<EOF
# Generated by omz-sync setup
export OMZ_SYNC_REPO_SLUG="${OMZ_SYNC_REPO_SLUG}"
export OMZ_SYNC_BRANCH="${OMZ_SYNC_BRANCH}"
export OMZ_SYNC_REMOTE_URL="${OMZ_SYNC_REMOTE_URL}"
export OMZ_SYNC_PUBLISH_ENABLED="${OMZ_SYNC_PUBLISH_ENABLED}"
EOF
}

omz_sync_setup_state_reset_runtime() {
  OMZ_SYNC_SETUP_STAGE=""
  OMZ_SYNC_SETUP_HAS_REPO=""
  OMZ_SYNC_SETUP_REPO_SLUG=""
  OMZ_SYNC_SETUP_BRANCH=""
  OMZ_SYNC_SETUP_VISIBILITY=""
  OMZ_SYNC_SETUP_PUBLISH=""
}

omz_sync_setup_state_load() {
  omz_sync_setup_state_reset_runtime
  if [[ -f "$OMZ_SYNC_SETUP_STATE_FILE" ]]; then
    source "$OMZ_SYNC_SETUP_STATE_FILE" || return 1
  fi
  return 0
}

omz_sync_setup_state_save() {
  mkdir -p "$OMZ_SYNC_CONFIG_HOME" || return 1
  cat > "$OMZ_SYNC_SETUP_STATE_FILE" <<EOF
# Generated by omz-sync interrupted setup recovery
export OMZ_SYNC_SETUP_STAGE="${OMZ_SYNC_SETUP_STAGE}"
export OMZ_SYNC_SETUP_HAS_REPO="${OMZ_SYNC_SETUP_HAS_REPO}"
export OMZ_SYNC_SETUP_REPO_SLUG="${OMZ_SYNC_SETUP_REPO_SLUG}"
export OMZ_SYNC_SETUP_BRANCH="${OMZ_SYNC_SETUP_BRANCH}"
export OMZ_SYNC_SETUP_VISIBILITY="${OMZ_SYNC_SETUP_VISIBILITY}"
export OMZ_SYNC_SETUP_PUBLISH="${OMZ_SYNC_SETUP_PUBLISH}"
EOF
}

omz_sync_setup_state_clear() {
  rm -f "$OMZ_SYNC_SETUP_STATE_FILE" 2>/dev/null || true
  omz_sync_setup_state_reset_runtime
}

# Public helper: clear only interrupted setup recovery state.
omz_sync_reset_setup_state() {
  omz_sync_setup_state_clear
  omz_sync_log "Setup recovery state cleared."
}

omz_sync_repo_is_marked() {
  [[ -f "$OMZ_SYNC_REPO_DIR/$OMZ_SYNC_REPO_MARKER_FILE" ]]
}

omz_sync_write_repo_marker() {
  mkdir -p "$OMZ_SYNC_REPO_DIR" || return 1
  cat > "$OMZ_SYNC_REPO_DIR/$OMZ_SYNC_REPO_MARKER_FILE" <<EOF
omz-sync-repo:1
created_at:$(date -u '+%Y-%m-%dT%H:%M:%SZ')
repo_slug:${OMZ_SYNC_REPO_SLUG:-unknown}
EOF
}

omz_sync_ensure_repo_identity() {
  local mode="${1:-runtime}"
  omz_sync_repo_is_marked && return 0

  local has_history=0
  (
    cd "$OMZ_SYNC_REPO_DIR" || return 1
    git rev-parse --verify HEAD >/dev/null 2>&1
  ) && has_history=1

  if (( has_history == 1 )); then
    omz_sync_warn "Repository is not marked as an omz-sync repository."
    if ! omz_sync_prompt "This repo may be unrelated. Convert it for omz-sync (adds $OMZ_SYNC_REPO_MARKER_FILE)?" "n"; then
      omz_sync_warn "Refusing to use unverified repository to avoid overriding unrelated data."
      return 1
    fi
  else
    if [[ "$mode" == "existing_setup" ]]; then
      if ! omz_sync_prompt "Repository is empty and unmarked. Initialize it as an omz-sync repository?" "y"; then
        omz_sync_warn "Setup cancelled because repository was not initialized for omz-sync."
        return 1
      fi
    fi
  fi

  omz_sync_write_repo_marker || return 1
  return 0
}

omz_sync_init_repo_if_needed() {
  mkdir -p "$OMZ_SYNC_DATA_HOME" || return 1
  if [[ -d "$OMZ_SYNC_REPO_DIR/.git" ]]; then
    return 0
  fi
  if [[ "${OMZ_SYNC_PUBLISH_ENABLED:-1}" == "1" && -n "${OMZ_SYNC_REMOTE_URL:-}" ]]; then
    git clone "$OMZ_SYNC_REMOTE_URL" "$OMZ_SYNC_REPO_DIR" >/dev/null 2>&1 && return 0
  fi
  {
    mkdir -p "$OMZ_SYNC_REPO_DIR" || return 1
    (
      cd "$OMZ_SYNC_REPO_DIR" || return 1
      git init -b "$OMZ_SYNC_BRANCH" >/dev/null 2>&1 || return 1
      if [[ -n "${OMZ_SYNC_REMOTE_URL:-}" ]]; then
        git remote add origin "$OMZ_SYNC_REMOTE_URL" >/dev/null 2>&1 || true
      fi
    )
  }
}

omz_sync_build_remote_url() {
  local repo_slug="$1"
  local base="$OMZ_SYNC_GIT_HOST_BASE"
  base="${base%/}"
  print -r -- "$base/$repo_slug.git"
}

omz_sync_validate_repo_slug() {
  local repo_slug="$1"
  [[ "$repo_slug" == */* && "$repo_slug" != */ && "$repo_slug" != /* ]]
}

omz_sync_bootstrap_first_time() {
  omz_sync_log "First-time setup"
  local has_repo repo_slug branch visibility create_ok publish_now
  local default_branch="main"
  has_repo=0
  omz_sync_setup_state_load || omz_sync_warn "Could not load setup recovery state."

  # If full config exists, clear any stale recovery state.
  if [[ -f "$OMZ_SYNC_CONFIG_FILE" ]]; then
    omz_sync_setup_state_clear
  fi

  if [[ -n "$OMZ_SYNC_SETUP_STAGE" ]]; then
    omz_sync_log "Resuming setup from saved state."
  fi

  if [[ -n "$OMZ_SYNC_SETUP_HAS_REPO" ]]; then
    has_repo="$OMZ_SYNC_SETUP_HAS_REPO"
  else
    if omz_sync_prompt "Do you already have a GitHub repo for zsh sync?" "n"; then
      has_repo=1
    fi
    OMZ_SYNC_SETUP_HAS_REPO="$has_repo"
    OMZ_SYNC_SETUP_STAGE="has_repo_selected"
    omz_sync_setup_state_save || omz_sync_warn "Could not save setup recovery state."
  fi

  if (( has_repo == 1 )); then
    OMZ_SYNC_PUBLISH_ENABLED=1
    OMZ_SYNC_SETUP_PUBLISH="1"
    if [[ -n "$OMZ_SYNC_SETUP_REPO_SLUG" ]]; then
      repo_slug="$OMZ_SYNC_SETUP_REPO_SLUG"
    fi
    while true; do
      if [[ -n "$repo_slug" ]]; then
        OMZ_SYNC_REMOTE_URL="$(omz_sync_build_remote_url "$repo_slug")"
        if git ls-remote "$OMZ_SYNC_REMOTE_URL" >/dev/null 2>&1; then
          break
        fi
        omz_sync_warn "Saved repo $repo_slug is not accessible anymore; please enter it again."
        repo_slug=""
      fi
      if ! omz_sync_read_value "Enter existing sync repo as owner/name (for example: yanluis/omz-sync)"; then
        return 1
      fi
      repo_slug="$OMZ_SYNC_READ_VALUE"
      if [[ -z "$repo_slug" ]]; then
        omz_sync_warn "Repository cannot be empty. Example: yanluis/omz-sync"
        continue
      fi
      if ! omz_sync_validate_repo_slug "$repo_slug"; then
        omz_sync_warn "Invalid repo format. Use owner/name (for example: yanluis/omz-sync)."
        continue
      fi
      OMZ_SYNC_REMOTE_URL="$(omz_sync_build_remote_url "$repo_slug")"
      if git ls-remote "$OMZ_SYNC_REMOTE_URL" >/dev/null 2>&1; then
        OMZ_SYNC_SETUP_REPO_SLUG="$repo_slug"
        OMZ_SYNC_SETUP_STAGE="existing_repo_selected"
        omz_sync_setup_state_save || omz_sync_warn "Could not save setup recovery state."
        break
      fi
      omz_sync_warn "Could not access $OMZ_SYNC_REMOTE_URL. Check name/access and try again."
    done
    if [[ -n "$OMZ_SYNC_SETUP_BRANCH" ]]; then
      branch="$OMZ_SYNC_SETUP_BRANCH"
    else
      omz_sync_read_value "Branch name" "$default_branch" || return 1
      branch="$OMZ_SYNC_READ_VALUE"
      OMZ_SYNC_SETUP_BRANCH="$branch"
      OMZ_SYNC_SETUP_STAGE="existing_repo_branch_selected"
      omz_sync_setup_state_save || omz_sync_warn "Could not save setup recovery state."
    fi
    OMZ_SYNC_REPO_SLUG="$repo_slug"
    OMZ_SYNC_BRANCH="$branch"
    omz_sync_write_config || return 1
    omz_sync_write_default_tracked || return 1
    omz_sync_init_repo_if_needed || return 1
    omz_sync_ensure_repo_identity "existing_setup" || return 1
    if omz_sync_prompt "Load saved version from GitHub now?" "y"; then
      omz_sync_startup_pull_flow 1
    fi
    omz_sync_setup_state_clear
    return 0
  fi

  local guessed_owner
  guessed_owner="$(git config --global github.user 2>/dev/null)"
  omz_sync_log "No existing repo selected. Enter the repository where omz-sync data will live."
  if [[ -n "$OMZ_SYNC_SETUP_REPO_SLUG" ]]; then
    repo_slug="$OMZ_SYNC_SETUP_REPO_SLUG"
  fi
  while true; do
    if [[ -n "$repo_slug" ]]; then
      if [[ "$repo_slug" == "your-user/omz-sync" || "$repo_slug" == your-user/* ]]; then
        omz_sync_warn "Saved placeholder repo is invalid; please enter your real GitHub username."
        repo_slug=""
      elif omz_sync_validate_repo_slug "$repo_slug"; then
        break
      else
        omz_sync_warn "Saved repo format is invalid; please enter owner/name."
        repo_slug=""
      fi
    fi
    omz_sync_read_value "Sync repository slug (owner/name, for example: yanluis/omz-sync)" "${guessed_owner}/omz-sync" || return 1
    repo_slug="$OMZ_SYNC_READ_VALUE"
    if [[ -z "$repo_slug" ]]; then
      omz_sync_warn "Repository cannot be empty. Use owner/name."
      continue
    fi
    if [[ "$repo_slug" == "your-user/omz-sync" || "$repo_slug" == your-user/* ]]; then
      omz_sync_warn "Replace placeholder 'your-user' with your real GitHub username."
      continue
    fi
    if ! omz_sync_validate_repo_slug "$repo_slug"; then
      omz_sync_warn "Invalid repo format. Use owner/name (for example: yanluis/omz-sync)."
      continue
    fi
    OMZ_SYNC_SETUP_REPO_SLUG="$repo_slug"
    OMZ_SYNC_SETUP_STAGE="new_repo_selected"
    omz_sync_setup_state_save || omz_sync_warn "Could not save setup recovery state."
    break
  done
  if [[ -n "$OMZ_SYNC_SETUP_BRANCH" ]]; then
    branch="$OMZ_SYNC_SETUP_BRANCH"
  else
    omz_sync_read_value "Branch name" "$default_branch" || return 1
    branch="$OMZ_SYNC_READ_VALUE"
    OMZ_SYNC_SETUP_BRANCH="$branch"
    OMZ_SYNC_SETUP_STAGE="new_repo_branch_selected"
    omz_sync_setup_state_save || omz_sync_warn "Could not save setup recovery state."
  fi
  if [[ -n "$OMZ_SYNC_SETUP_VISIBILITY" ]]; then
    visibility="$OMZ_SYNC_SETUP_VISIBILITY"
  else
    omz_sync_read_value "Repo visibility (private/public)" "private" || return 1
    visibility="$OMZ_SYNC_READ_VALUE"
    OMZ_SYNC_SETUP_VISIBILITY="$visibility"
    OMZ_SYNC_SETUP_STAGE="new_repo_visibility_selected"
    omz_sync_setup_state_save || omz_sync_warn "Could not save setup recovery state."
  fi
  if [[ -n "$OMZ_SYNC_SETUP_PUBLISH" ]]; then
    OMZ_SYNC_PUBLISH_ENABLED="$OMZ_SYNC_SETUP_PUBLISH"
  else
    if omz_sync_prompt "Publish this sync repository to GitHub now?" "y"; then
      publish_now=1
    else
      publish_now=0
    fi
    OMZ_SYNC_PUBLISH_ENABLED="$publish_now"
    OMZ_SYNC_SETUP_PUBLISH="$publish_now"
    OMZ_SYNC_SETUP_STAGE="new_repo_publish_selected"
    omz_sync_setup_state_save || omz_sync_warn "Could not save setup recovery state."
  fi
  OMZ_SYNC_REPO_SLUG="$repo_slug"
  OMZ_SYNC_BRANCH="$branch"
  OMZ_SYNC_REMOTE_URL="$(omz_sync_build_remote_url "$repo_slug")"
  omz_sync_write_config || return 1
  omz_sync_write_default_tracked || return 1

  if [[ "${OMZ_SYNC_PUBLISH_ENABLED:-1}" == "1" ]] && command -v gh >/dev/null 2>&1; then
    if omz_sync_prompt "Create GitHub repo automatically with gh?" "y"; then
      if gh repo create "$repo_slug" "--$visibility" >/dev/null 2>&1; then
        create_ok=1
      else
        create_ok=0
      fi
      if (( create_ok == 0 )); then
        omz_sync_warn "Automatic creation failed. You can create it manually and rerun."
      fi
    fi
  fi

  omz_sync_init_repo_if_needed || return 1
  omz_sync_ensure_repo_identity "new_setup" || return 1
  local tracked_list
  tracked_list="$(omz_sync_expand_tracked_paths)" || return 1
  print -r -- "$tracked_list" | omz_sync_copy_local_to_repo
  omz_sync_commit_and_push "initial sync" || {
    omz_sync_warn "Initial push failed. Ensure repo exists and auth is configured."
  }
  if [[ "${OMZ_SYNC_PUBLISH_ENABLED:-1}" != "1" ]]; then
    omz_sync_log "Publish skipped. Local sync repo initialized; enable publishing later to share across machines."
  fi
  omz_sync_setup_state_clear
}

omz_sync_load_config() {
  if [[ ! -f "$OMZ_SYNC_CONFIG_FILE" ]]; then
    return 1
  fi
  source "$OMZ_SYNC_CONFIG_FILE"
  if [[ -z "${OMZ_SYNC_BRANCH:-}" ]]; then
    return 1
  fi
  OMZ_SYNC_PUBLISH_ENABLED="${OMZ_SYNC_PUBLISH_ENABLED:-1}"
  return 0
}

omz_sync_precmd_hook() {
  omz_sync_sync_local_changes
}

omz_sync_exit_hook() {
  omz_sync_sync_local_changes
}

omz_sync_init() {
  omz_sync_require_cmd git || return 0

  if ! omz_sync_load_config; then
    omz_sync_bootstrap_first_time || {
      omz_sync_warn "Setup did not complete."
      return 0
    }
  fi

  omz_sync_init_repo_if_needed || {
    omz_sync_warn "Could not initialize local sync repo."
    return 0
  }
  omz_sync_ensure_repo_identity "runtime" || return 0

  omz_sync_startup_pull_flow

  if autoload -Uz add-zsh-hook 2>/dev/null; then
    if (( OMZ_SYNC_HOOKS_REGISTERED == 0 )); then
      add-zsh-hook precmd omz_sync_precmd_hook
      add-zsh-hook zshexit omz_sync_exit_hook
      OMZ_SYNC_HOOKS_REGISTERED=1
    fi
  else
    omz_sync_warn "add-zsh-hook unavailable; automatic periodic/exit sync disabled."
  fi
}

if [[ "${OMZ_SYNC_DISABLE_AUTO_INIT:-0}" != "1" ]]; then
  omz_sync_init
fi
