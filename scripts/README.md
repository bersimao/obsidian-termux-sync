# Scripts

| Script | Purpose |
| --- | --- |
| `sync-vault.sh` | Sync a single vault |
| `sync-all-vaults.sh` | Sync several vaults in one run |
| `view-sync-log.sh` | Browse the stored sync logs |

Edit the vault path(s) at the top of whichever sync script you use — the block marked `EDIT THIS`.

## Install

```bash
mkdir -p ~/scripts
cp scripts/sync-all-vaults.sh ~/scripts/
cp scripts/view-sync-log.sh   ~/scripts/
chmod +x ~/scripts/*.sh
```

Then point the Termux widgets at them:

```bash
mkdir -p ~/.shortcuts
ln -s ~/scripts/sync-all-vaults.sh ~/.shortcuts/SyncAllVaults
ln -s ~/scripts/view-sync-log.sh   ~/.shortcuts/ViewSyncLog
```

Long-press the home screen → add widget → Termux Widget → tap either entry.

## What the sync scripts do

1. **Guard** — refuse to run if the repo is mid-rebase or mid-merge, rather than committing on top of a broken state
2. **Commit** — local changes first, because `pull.rebase = true` refuses to rebase on a dirty working tree
3. **Pull** — with `--autostash`, stopping if the pull fails
4. **Push** — only when ahead of the remote
5. **Log** — every run goes to `~/sync-logs/`, keeping the 10 most recent
6. **Pause** — only on failure, so a clean run closes Termux immediately but an error holds the window open

## Notes

- The shebang is Termux's bash path (`/data/data/com.termux/files/usr/bin/bash`). On a non-Termux system, change it to `#!/usr/bin/env bash`.
- Android may mount shared storage no-exec, so invoke via `bash script.sh` rather than `./script.sh` if a script lives inside the vault.
- `sync-all-vaults.sh` uses `continue` on failure so one stuck vault doesn't block the others; `sync-vault.sh` uses `exit 1` since there is nothing else to move on to.
