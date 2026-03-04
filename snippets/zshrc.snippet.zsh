# omz-sync bootstrap
_omz_sync_install_dir="${OMZ_SYNC_INSTALL_DIR:-$HOME/.local/share/omz-sync}"
if [[ -f "$_omz_sync_install_dir/omz-sync.zsh" ]]; then
  # Allow re-running setup in the same shell after uninstall/reset.
  unset OMZ_SYNC_LOADED
  source "$_omz_sync_install_dir/omz-sync.zsh"
fi
unset _omz_sync_install_dir
