# Obsidian Git Sync on Android with Termux and LFS

Sync an Obsidian vault across Android, desktop and any number of devices using Git and Git LFS — no subscription, no flaky mobile plugin, and no extra APK for the sync button.

**What's in here**

- A full step-by-step setup guide (below)
- [`scripts/`](scripts/) — ready-to-use sync and log-viewer scripts
- [`templates/`](templates/) — `.gitattributes` and `.gitignore` tuned for Obsidian vaults

**Why another guide?** This started as a walkthrough of [Askar Zhakenov's article](https://medium.com/@askar.zhakenov/obsidian-git-sync-on-android-with-termux-and-lfs-c5bb05e0f1cc), which covers the key insight — keeping `.git` off Android's FUSE filesystem. Working through it on a real device surfaced a handful of things worth fixing:

| Issue in the original | What this guide does |
| --- | --- |
| `git lfs install --hooks-only` | Flag doesn't exist in Termux's git-lfs — uses `--local` |
| Pull before commit | Fails with `cannot pull with rebase` — commits first |
| Empty sync commits | Only commits when there are actual changes |
| Scheduler / Termux:Widget APK | Manual widget tap via symlink, no extra APK |
| Missing `mkdir` steps | Every directory creation is explicit |
| Silent failures | Pauses on error, logs every run |

Original approach and the FUSE insight: credit to Askar Zhakenov. Fixes, scripts and troubleshooting here are tested against Termux from Google Play on Android.

---

## Why Git + LFS on Android?

The official Obsidian Sync costs $4/month. Plugin-based Git solutions like `obsidian-git` are flaky on mobile. This guide gives you full version history, free hosting on GitHub/GitLab, and binary file support via LFS — across any number of devices.

The core problem on Android: **Android's FUSE filesystem on `/storage/emulated/0/` corrupts Git objects**. When Git writes pack files or loose objects to shared storage, the FUSE layer sometimes creates empty (zero-byte) files. This silently breaks your repository.

The fix: keep the `.git` directory on Termux's native filesystem, while the working tree (your vault) stays on shared storage where Obsidian can see it.

---

## Step 1 — Install Packages in Termux

Open Termux and run:

```bash
pkg update && pkg upgrade
pkg install git git-lfs openssh gh jq curl
```

| Package | Purpose |
| --- | --- |
| git | Version control |
| git-lfs | Large File Storage for binaries |
| openssh | SSH keys for authentication |
| gh | GitHub CLI — simplest way to authenticate |
| jq | JSON processing |
| curl | HTTP requests |

---

## Step 2 — Grant Storage Access

```bash
termux-setup-storage
```

Accept the permission prompt. This creates `~/storage/shared/` which maps to `/storage/emulated/0/` — your phone's internal storage.

---

## Step 3 — Authenticate with GitHub

```bash
gh auth login
```

Follow the interactive prompts: choose HTTPS, authenticate via browser. This configures the Git credential helper automatically — no SSH keys or tokens to manage.

---

## Step 4 — Clone with Separate Git Directory

This is the critical step. Use `--separate-git-dir` to keep the Git database on Termux's native filesystem, away from FUSE.

First, create the parent directory for the separate git dir (Git won't create it for you):

```bash
mkdir -p ~/obsidian-git
```

Then clone (replace `YOUR_USER` / `YOUR_VAULT`):

```bash
git clone \
  --separate-git-dir="$HOME/obsidian-git/.git" \
  https://github.com/YOUR_USER/YOUR_VAULT.git \
  ~/storage/shared/my-obsidian-vault
```

This does three things:

- Creates `~/storage/shared/my-obsidian-vault` automatically — no need to create the working tree directory beforehand
- Creates the actual `.git/` database at `~/obsidian-git/.git` (safe ext4 filesystem)
- Places a `.git` pointer file in the vault pointing to the database

> **⚠️ If clone fails partway through**
> If you hit an error and the clone is incomplete, clean up both directories before retrying — otherwise Git will refuse with "repository path already exists and is not an empty directory":
> ```bash
> rm -rf ~/obsidian-git
> rm -rf ~/storage/shared/my-obsidian-vault
> mkdir -p ~/obsidian-git
> # then re-run the clone command
> ```

> **ℹ️ Already have a local vault?**
> If the vault already exists on your phone but isn't a Git repo yet, initialize it instead. In this case you must already be inside the directory — no clone needed:
> ```bash
> # If the vault directory doesn't exist yet, create it first:
> mkdir -p ~/storage/shared/my-obsidian-vault
>
> cd ~/storage/shared/my-obsidian-vault
> git init --separate-git-dir="$HOME/obsidian-git/.git"
> git remote add origin https://github.com/YOUR_USER/YOUR_VAULT.git
> ```

---

## Step 5 — Configure Git

### Global config

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global pull.rebase true
git config --global core.quotepath false
git config --global --add safe.directory /storage/emulated/0/my-obsidian-vault
```

| Setting | Problem it solves |
| --- | --- |
| `pull.rebase = true` | Avoids noisy merge commits on every pull — replays local commits on top of remote |
| `core.quotepath = false` | Shows real filenames instead of escaped sequences for non-ASCII (Cyrillic, CJK, emoji) |
| `safe.directory` | Vault lives on a different owner than Termux — without this Git refuses to run |

### Local config (per-repository)

```bash
cd ~/storage/shared/my-obsidian-vault

git config --local core.worktree ~/storage/shared/my-obsidian-vault
git config --local core.filemode false
git config --local core.symlinks false
git config --local core.ignorecase true
```

| Setting | Problem it solves |
| --- | --- |
| `core.worktree` | Required for separate-git-dir — tells Git where the working tree is |
| `core.filemode = false` | Android reports all files as 0777 — disabling prevents phantom diffs |
| `core.symlinks = false` | Android FUSE doesn't support symlinks — prevents silent failures |
| `core.ignorecase = true` | Prevents issues when renaming files that differ only in case |

---

## Step 6 — Set Up Git LFS

### Initialize LFS

Run from inside the vault:

```bash
cd ~/storage/shared/my-obsidian-vault

# Set up global LFS filters
git lfs install

# Create a shared hooks directory
mkdir -p ~/.githooks

# Point this repo to it
git config --local core.hooksPath ~/.githooks

# Install LFS hooks (--hooks-only not supported in older versions, --local is enough)
git lfs install --local
```

> **ℹ️ Note on `--hooks-only`**
> The original article uses `git lfs install --hooks-only --local` but that flag does not exist in the version of git-lfs shipped with Termux. Use `git lfs install --local` instead — it sets up filters and hooks in one step. Since `core.hooksPath` is already configured, the hooks will be installed into `~/.githooks/` automatically.

### Configure tracked file types (.gitattributes)

```bash
cat > ~/storage/shared/my-obsidian-vault/.gitattributes << 'EOF'
# Text files: normalize to LF
*.md    text eol=lf
*.txt   text eol=lf
*.json  text eol=lf
*.html  text eol=lf
*.sh    text eol=lf
*.py    text eol=lf

# Images
*.png   filter=lfs diff=lfs merge=lfs -text
*.jpg   filter=lfs diff=lfs merge=lfs -text
*.jpeg  filter=lfs diff=lfs merge=lfs -text
*.gif   filter=lfs diff=lfs merge=lfs -text
*.webp  filter=lfs diff=lfs merge=lfs -text
*.svg   filter=lfs diff=lfs merge=lfs -text

# Documents
*.pdf   filter=lfs diff=lfs merge=lfs -text
*.pptx  filter=lfs diff=lfs merge=lfs -text
*.docx  filter=lfs diff=lfs merge=lfs -text
*.xlsx  filter=lfs diff=lfs merge=lfs -text

# Media
*.mp4   filter=lfs diff=lfs merge=lfs -text
*.mp3   filter=lfs diff=lfs merge=lfs -text
*.m4a   filter=lfs diff=lfs merge=lfs -text
*.wav   filter=lfs diff=lfs merge=lfs -text
*.ogg   filter=lfs diff=lfs merge=lfs -text
*.webm  filter=lfs diff=lfs merge=lfs -text

# Fonts
*.ttf   filter=lfs diff=lfs merge=lfs -text
*.woff  filter=lfs diff=lfs merge=lfs -text

# Archives
*.zip   filter=lfs diff=lfs merge=lfs -text

# Obsidian canvas (JSON but can grow large)
*.canvas filter=lfs diff=lfs merge=lfs -text

# Obsidian plugin bundles
.obsidian/plugins/**/*.js filter=lfs diff=lfs merge=lfs -text
EOF
```

> **💡 Tip**
> The `text eol=lf` rules are important — they prevent line-ending conflicts when syncing between Android, Windows, macOS, and Linux.

### Migrate existing files to LFS (if needed)

> **⚠️ Warning:** Only run this if your repo already has binary files committed the regular way. This rewrites history — coordinate with anyone else using the repo.

```bash
git lfs migrate import --include="*.png,*.jpg,*.pdf" --everything
git push --force-with-lease
```

---

## Step 7 — Configure .gitignore

Run from inside the vault (this overwrites any existing `.gitignore`):

```bash
cat > ~/storage/shared/my-obsidian-vault/.gitignore << 'EOF'
# Secrets
.env

# Obsidian per-device state — causes merge conflicts, useless in history
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/graph.json
.trash/

# Plugin caches (rebuilt automatically)
.obsidian/copilot-index-*.json
.obsidian/plugins/make-md/data.json
.makemd/
*.mdb

# Sync artifacts
.sync.log
.sync.lock

# OS junk
.DS_Store
Thumbs.db
EOF
```

> **🔑 Key insight**
> Always ignore `workspace.json` and `workspace-mobile.json`. These track which tabs are open and change on every Obsidian session — they cause constant merge conflicts with zero value in version control.

---

## Step 8 — The Sync Script

Create the directory structure and the script:

```bash
mkdir -p ~/storage/shared/my-obsidian-vault/System/sync
```

```bash
cat > ~/storage/shared/my-obsidian-vault/System/sync/sync.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Log this run to its own file, keeping the 10 most recent
LOGDIR="$HOME/sync-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/sync-$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee "$LOGFILE") 2>&1

echo "=== Sync started: $(date '+%Y-%m-%d %H:%M:%S') ==="
echo ""

VAULT="$HOME/storage/shared/my-obsidian-vault"
FAILED=0

cd "$VAULT" || { echo "✗ Cannot access $VAULT"; FAILED=1; }

if [ "$FAILED" -eq 0 ]; then
  # Guard: refuse to sync if a rebase is unfinished
  if [ -d "$(git rev-parse --git-path rebase-merge)" ] \
     || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
    echo "✗ Rebase in progress — resolve manually before syncing"
    FAILED=1

  # Guard: refuse to sync if a merge is unresolved
  elif [ -f "$(git rev-parse --git-path MERGE_HEAD)" ]; then
    echo "✗ Unresolved merge — resolve manually before syncing"
    FAILED=1

  else
    # Commit local changes FIRST — rebase refuses to run on a dirty tree
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
      git add .
      git commit -m "sync: $(date '+%Y-%m-%d %H:%M')"
      echo "• Local changes committed"
    fi

    # Now pull — stop if the pull itself fails
    if ! git pull --autostash; then
      echo "✗ Pull failed — resolve manually, skipping push"
      FAILED=1

    # Push only if we are ahead of the remote
    elif [ -n "$(git log @{u}.. 2>/dev/null)" ]; then
      if git push; then
        echo "✓ Synced successfully"
      else
        echo "✗ Push failed"
        FAILED=1
      fi
    else
      echo "✓ Already up to date"
    fi
  fi
fi

echo ""
echo "=== Sync finished: $(date '+%Y-%m-%d %H:%M:%S') ==="

# Keep only the 10 most recent logs
ls -1t "$LOGDIR"/sync-*.log 2>/dev/null | tail -n +11 | while read -r old; do
  rm -f "$old"
done

# Keep Termux open only when something went wrong
if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "────────────────────────────────"
  echo "⚠ Sync had problems."
  echo "Press Enter to close…"
  read -r
fi
EOF
```

Make it executable:

```bash
chmod +x ~/storage/shared/my-obsidian-vault/System/sync/sync.sh
```

### Why this script instead of the article's version

- **Commits before pulling** — with `pull.rebase = true`, Git refuses to rebase on a dirty working tree, so pulling first would fail on any vault that actually has changes
- Skips the commit entirely if there are no changes — the article's script always commits, creating empty commits over time
- Refuses to run if the repo is mid-rebase or mid-merge, instead of committing on top of a broken state
- Stops if `git pull` fails (conflict, no network, auth issue) rather than pushing blindly
- Pushes only when ahead of the remote, so a pull-only run doesn't produce a pointless push
- **Pauses only on failure** — a clean run closes Termux immediately; a failed one waits for Enter so you can read the error
- **Logs every run** to `~/sync-logs/`, keeping the 10 most recent
- No scheduler, no automatic runs — you control when to sync
- No external dependencies (no Gemini API key needed for basic use)

> **⚠️ Why the pause and the logs matter**
> Termux Widget closes the session the moment the script exits. Without the pause, a conflict during `git pull` scrolls past and vanishes — you only find out days later when the next run reports "Rebase in progress", with no clue which file conflicted. The `FAILED` flag holds the window open at the moment it happens, and the log file keeps the output even if the widget kills the session anyway.

> **⚠️ Order matters: commit, then pull**
> Pulling before committing produces this error on any vault with local edits:
> ```
> error: cannot pull with rebase: You have unstaged changes.
> error: Please commit or stash them.
> ```
> Committing first lets rebase replay your local commit cleanly on top of the remote. The `--autostash` flag on `git pull` is a safety net for anything still unstaged — for example a file Obsidian writes while the script is running.

> **⚠️ Why the guards matter**
> With `pull.rebase = true`, every pull rebases. If a pull hits a conflict or an empty commit mid-rebase, the script exits and leaves the repo stuck in rebase mode. Since the widget runs silently, you would never see the error — the guards make it fail loudly instead. See Step 12 for how to recover from a stuck rebase.

---

## Step 9 — Termux Widget Shortcut

Termux (from Google Play) already includes the widget. Create a symlink so the widget points to your script without duplicating it:

```bash
mkdir -p ~/.shortcuts
ln -s ~/storage/shared/my-obsidian-vault/System/sync/sync.sh ~/.shortcuts/ObsidianSync
```

Using a symlink means the script lives inside your vault (tracked by Git) but the widget can still find it.

Then: long-press your home screen → add widget → Termux Widget → tap **ObsidianSync**.

> **💡 Tip**
> If you ever need to run it manually from Termux instead, just run:
> `bash ~/storage/shared/my-obsidian-vault/System/sync/sync.sh`

> **ℹ️ Why bash explicitly?**
> Android may restrict execution on shared storage (no-exec mount flag). Always invoke via `bash script.sh` rather than `./script.sh` to bypass this.

### Second widget: read the sync logs

The sync script writes each run to `~/sync-logs/`. This companion script lists the stored runs and opens whichever you pick, so you can review a sync that closed too fast to read:

```bash
cat > ~/scripts/view-sync-log.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

LOGDIR="$HOME/sync-logs"

if [ ! -d "$LOGDIR" ] || [ -z "$(ls -A "$LOGDIR" 2>/dev/null)" ]; then
  echo "No logs found — run the sync at least once."
  echo ""
  echo "Press Enter to close…"
  read -r
  exit 0
fi

mapfile -t LOGS < <(ls -1t "$LOGDIR"/sync-*.log)

echo "Available sync logs:"
echo ""
for i in "${!LOGS[@]}"; do
  printf "  %2d) %s\n" "$((i+1))" "$(basename "${LOGS[$i]}")"
done

echo ""
read -rp "Pick a number (Enter = most recent): " choice

if [ -z "$choice" ]; then
  choice=1
fi

INDEX=$((choice-1))

if [ -z "${LOGS[$INDEX]}" ]; then
  echo "Invalid choice."
else
  echo ""
  echo "────────────────────────────────"
  cat "${LOGS[$INDEX]}"
fi

echo ""
echo "────────────────────────────────"
echo "Press Enter to close…"
read -r
EOF

chmod +x ~/scripts/view-sync-log.sh
```

Add its widget shortcut:

```bash
ln -s ~/scripts/view-sync-log.sh ~/.shortcuts/ViewSyncLog
```

Then add a second Termux Widget on your home screen pointing to **ViewSyncLog**. Tapping it and pressing Enter shows the most recent run; typing a number opens an older one.

You end up with two widgets: **ObsidianSync** (or **SyncAllVaults**) to sync, and **ViewSyncLog** to review what happened.

---

## Step 10 — Adding More Vaults (optional)

Each vault is independent. To add another (e.g. a work vault), repeat steps 4–7 with different paths, then use a master script that syncs all vaults with one tap.

### Clone the additional vault

Use a **different** separate-git-dir path per vault — never reuse:

```bash
mkdir -p ~/obsidian-work-git

git clone \
  --separate-git-dir="$HOME/obsidian-work-git/.git" \
  https://github.com/YOUR_USER/work-vault.git \
  ~/storage/shared/work-vault

git config --global --add safe.directory /storage/emulated/0/work-vault
```

### Configure local settings and LFS

```bash
cd ~/storage/shared/work-vault

git config --local core.worktree ~/storage/shared/work-vault
git config --local core.filemode false
git config --local core.symlinks false
git config --local core.ignorecase true
git config --local core.hooksPath ~/.githooks
git lfs install --local
```

Then create `.gitattributes` and `.gitignore` the same way as steps 6 and 7, adjusting the paths.

### Create a master sync script

Outside any vault, create a script that loops through all of them:

```bash
mkdir -p ~/scripts
cat > ~/scripts/sync-all-vaults.sh << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash

# Log this run to its own file, keeping the 10 most recent
LOGDIR="$HOME/sync-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/sync-$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee "$LOGFILE") 2>&1

echo "=== Sync started: $(date '+%Y-%m-%d %H:%M:%S') ==="
echo ""

VAULTS=(
  "$HOME/storage/shared/my-obsidian-vault"
  "$HOME/storage/shared/work-vault"
)

FAILED=0

for VAULT in "${VAULTS[@]}"; do
  echo "▶ Syncing $(basename "$VAULT")"
  cd "$VAULT" || { echo "  ✗ Cannot access $VAULT"; FAILED=1; echo ""; continue; }

  # Guard: refuse to sync if a rebase is unfinished
  if [ -d "$(git rev-parse --git-path rebase-merge)" ] \
     || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
    echo "  ✗ Rebase in progress — resolve manually, skipping"
    FAILED=1
    echo ""
    continue
  fi

  # Guard: refuse to sync if a merge is unresolved
  if [ -f "$(git rev-parse --git-path MERGE_HEAD)" ]; then
    echo "  ✗ Unresolved merge — resolve manually, skipping"
    FAILED=1
    echo ""
    continue
  fi

  # Commit local changes FIRST — rebase refuses to run on a dirty tree
  if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    git add .
    git commit -m "sync: $(date '+%Y-%m-%d %H:%M')"
    echo "  • Local changes committed"
  fi

  # Now pull — rebase replays the local commit on top of the remote
  if ! git pull --autostash; then
    echo "  ✗ Pull failed — resolve manually, skipping push"
    FAILED=1
    echo ""
    continue
  fi

  # Push only if we are ahead of the remote
  if [ -n "$(git log @{u}.. 2>/dev/null)" ]; then
    if git push; then
      echo "  ✓ Synced"
    else
      echo "  ✗ Push failed"
      FAILED=1
    fi
  else
    echo "  ✓ Already up to date"
  fi
  echo ""
done

echo "=== Sync finished: $(date '+%Y-%m-%d %H:%M:%S') ==="

# Keep only the 10 most recent logs
ls -1t "$LOGDIR"/sync-*.log 2>/dev/null | tail -n +11 | while read -r old; do
  rm -f "$old"
done

# Keep Termux open only when something went wrong
if [ "$FAILED" -ne 0 ]; then
  echo ""
  echo "────────────────────────────────"
  echo "⚠ One or more vaults had problems."
  echo "Press Enter to close…"
  read -r
fi
EOF

chmod +x ~/scripts/sync-all-vaults.sh
```

> **ℹ️ Note on `continue` vs `exit`**
> The master script uses `continue` instead of `exit` in its guards, so one stuck vault doesn't block the others from syncing. The single-vault script in Step 8 uses `exit 1` since there is nothing else to move on to.

### Update the widget shortcut

Replace the single-vault symlink with one that points to the master script:

```bash
rm ~/.shortcuts/ObsidianSync
ln -s ~/scripts/sync-all-vaults.sh ~/.shortcuts/SyncAllVaults
```

Then re-add the widget on your home screen pointing to **SyncAllVaults**. To add more vaults later, just append paths to the `VAULTS` array.

> **⚠️ Gotchas with multiple vaults**
> - Separate git dirs must be unique per vault — never reuse `~/obsidian-git/`
> - Each vault needs its own GitHub repo (different remotes)
> - Add a `safe.directory` global entry per vault — or use `git config --global --add safe.directory '*'` if you trust all your repos
> - Each `.git` lives in Termux internal storage — keep an eye on space if vaults are large

---

## Step 11 — Architecture Summary

```
# Phone Storage (/storage/emulated/0/)
my-obsidian-vault/              ← Obsidian reads this
├── .git  (file)                ← Pointer to ~/obsidian-git/.git
├── .gitattributes              ← LFS rules + line ending normalization
├── .gitignore                  ← Excludes workspace, caches, secrets
├── Inbox/
├── Projects/
└── System/sync/
    └── sync.sh                 ← Sync script (tracked in Git)

# Termux Internal (/data/data/com.termux/files/home/)
obsidian-git/.git/              ← Real git database (safe from FUSE)
├── objects/
├── refs/
└── lfs/objects/

.githooks/                      ← LFS hooks (core.hooksPath)
├── post-checkout
├── post-commit
├── post-merge
└── pre-push

scripts/                        ← Scripts that live outside any vault
├── sync-all-vaults.sh          ← Multi-vault sync (Step 10)
└── view-sync-log.sh            ← Log viewer (Step 9)

sync-logs/                      ← One file per run, 10 most recent kept
├── sync-20261014-231500.log
└── sync-20261013-084212.log

.shortcuts/                     ← What the Termux widgets point to
├── ObsidianSync                ← Symlink → System/sync/sync.sh
└── ViewSyncLog                 ← Symlink → scripts/view-sync-log.sh
```

---

## Step 12 — Troubleshooting

### "error: object file is empty"

FUSE created an empty object. Fix:

```bash
cd ~/storage/shared/my-obsidian-vault
find "$(git rev-parse --git-dir)/objects" -type f -empty -delete
git fetch --all
```

### "fatal: not in a git directory"

Git can't find the `.git` pointer. Check it exists:

```bash
cat ~/storage/shared/my-obsidian-vault/.git
# Should show: gitdir: /data/data/com.termux/files/home/obsidian-git/.git
```

### "Invalid path ... No such file or directory" during clone

The parent directory for `--separate-git-dir` doesn't exist yet. Create it first:

```bash
mkdir -p ~/obsidian-git
```

### "repository path already exists and is not an empty directory"

A previous failed clone left files behind. Clean both sides and retry:

```bash
rm -rf ~/obsidian-git
rm -rf ~/storage/shared/my-obsidian-vault
mkdir -p ~/obsidian-git
# then re-run the clone
```

### "cannot pull with rebase: You have unstaged changes"

The script pulled before committing. With `pull.rebase = true`, Git refuses to rebase on a dirty working tree.

Unblock the affected vault manually:

```bash
cd ~/storage/shared/work-vault
git add .
git commit -m "sync: $(date '+%Y-%m-%d %H:%M')"
git pull
git push
```

Then make sure your sync script commits **before** pulling — see Step 8. This is a script-ordering bug, not a repo problem.

### "interactive rebase in progress" — repo stuck mid-rebase

With `pull.rebase = true`, a pull that hits a conflict or an empty commit leaves the repo in rebase mode. **Your remote is safe** — a rebase only rewrites local commits, and a normal `git push` can never delete remote history.

Recover from the working tree (not the separate git dir — rebase needs the files):

```bash
cd ~/storage/shared/my-obsidian-vault

# Optional safety net: snapshot the current local state
git branch backup-before-rebase-fix

# Finish the rebase
git rebase --continue
```

If it reports the commit is empty (common with scheduled sync commits that duplicate remote content):

```bash
git rebase --skip
```

Then verify and compare against the remote before pushing:

```bash
git log --oneline -10
git status                      # should show "On branch main", no rebase message

git fetch origin
git log --oneline origin/main -5
git push
```

> **⚠️** If the push is rejected, do **not** use `--force`. Run `git pull` and resolve normally — forcing is what actually risks remote data.

To abandon the rebase entirely and return to where you were before it started:

```bash
git rebase --abort
```

### LFS files show as pointer text

You pulled without LFS downloading the actual files:

```bash
git lfs pull
```

### Merge conflicts on .obsidian/ files

Make sure `workspace.json` and `workspace-mobile.json` are in `.gitignore`. They are the main offenders.

### Widget tap does nothing

Verify the symlink target exists and the script is executable:

```bash
ls -la ~/.shortcuts/ObsidianSync
bash ~/.shortcuts/ObsidianSync
```

### Termux closed before I could read the error

That is the widget's normal behaviour — it ends the session when the script exits. Two things cover it:

- The script pauses on failure (`FAILED=1` → waits for Enter), so an error holds the window open
- Every run is logged to `~/sync-logs/`; tap the **ViewSyncLog** widget, or read it directly:

```bash
ls -1t ~/sync-logs/
cat "$(ls -1t ~/sync-logs/sync-*.log | head -1)"
```

If the pause still doesn't hold the window open on your device, replace `read -r` at the end of the script with a timed hold:

```bash
echo "Closing in 30s…"
sleep 30
```
