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

Then add this to your `~/.zshrc`:

```zsh
if [[ -f "$HOME/.local/share/omz-sync/omz-sync.zsh" ]]; then
  source "$HOME/.local/share/omz-sync/omz-sync.zsh"
fi
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
