#!/data/data/com.termux/files/usr/bin/bash

# Log this run to its own file, keeping the 10 most recent
LOGDIR="$HOME/sync-logs"
mkdir -p "$LOGDIR"
LOGFILE="$LOGDIR/sync-$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee "$LOGFILE") 2>&1

echo "=== Sync started: $(date '+%Y-%m-%d %H:%M:%S') ==="
echo ""

# ─── EDIT THIS ───────────────────────────────────────────
VAULT="$HOME/storage/shared/my-obsidian-vault"
# ─────────────────────────────────────────────────────────
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
