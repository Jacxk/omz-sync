# omz-sync bootstrap
if [[ -f "$HOME/.local/share/omz-sync/omz-sync.zsh" ]]; then
  # Allow re-running setup in the same shell after uninstall/reset.
  unset OMZ_SYNC_LOADED
  source "$HOME/.local/share/omz-sync/omz-sync.zsh"
fi
