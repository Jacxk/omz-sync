# omz-sync

`omz-sync` keeps your Oh My Zsh setup synced through a GitHub repository.

## What it does

- First run wizard asks whether the GitHub repo already exists.
- Returning users are asked whether they want to load the saved version when differences are detected.
- Startup sync shows what changed (local-only, remote-only, modified).
- Local changes are committed and pushed automatically:
  - during the shell session (debounced),
  - and again at terminal close (`zshexit` hook).

## Tracked defaults

- `~/.zshrc`
- `~/.zshenv` (if present)
- `~/.p10k.zsh` (if present)
- `~/.oh-my-zsh/custom/themes/**/*`
- `~/.oh-my-zsh/custom/plugins/**/*`
- `~/.oh-my-zsh/custom/*.zsh`

You can edit tracked paths in `~/.config/omz-sync/tracked_paths`.

## Install into your home directory

From this repo:

```bash
zsh ./scripts/install-omz-sync.zsh
```

The installer asks whether it should add the snippet to `~/.zshrc` automatically.
If you choose no, add this manually:

```zsh
if [[ -f "$HOME/.local/share/omz-sync/omz-sync.zsh" ]]; then
  # Allow re-running setup in the same shell after uninstall/reset.
  unset OMZ_SYNC_LOADED
  source "$HOME/.local/share/omz-sync/omz-sync.zsh"
fi
```

After install, load it in the current shell:

```bash
source ~/.zshrc
```

## Uninstall or reset

Run:

```bash
zsh ./scripts/uninstall-omz-sync.zsh
```

The uninstaller interactively asks whether to:
- remove the bootstrap snippet from `~/.zshrc`,
- delete installed files in `~/.local/share/omz-sync`,
- delete sync state in `~/.config/omz-sync` (including backups).

All prompts accept `Y` or `N` (case-insensitive). Pressing Enter uses the default shown in the prompt.

After uninstall, run:

```bash
source ~/.zshrc
```

## First-run behavior

At first startup:

1. Ask: "Do you already have a GitHub repo for zsh sync?"
2. If yes:
   - ask `owner/repo` and branch,
   - validate access,
   - ask if you want to load saved version now.
3. If no:
   - ask repo slug, branch, visibility,
   - optionally create via `gh`,
   - initialize and push current local config.

If setup is interrupted, `omz-sync` saves progress to `~/.config/omz-sync/setup_state.zsh` and resumes from the last completed step on next startup.

To clear only this recovery state (without deleting full sync config), run:

```zsh
omz_sync_reset_setup_state
```

## Notes

- Requires `git`.
- `gh` is optional (used to auto-create repositories).
- Backups are saved under `~/.config/omz-sync/backups/` before overwriting local files.
- Optional env var: `OMZ_SYNC_GIT_HOST_BASE` (default `https://github.com`) for alternate Git hosts.

## Local simulation test

Run the isolated harness (uses a temporary fake HOME and local bare remotes):

```bash
zsh ./tests/simulate-omz-sync.zsh
```

This validates:
- first-run wizard (existing repo path),
- returning-user local change commit/push,
- returning-user remote update load flow.
