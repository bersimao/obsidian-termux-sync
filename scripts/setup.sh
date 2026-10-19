#!/data/data/com.termux/files/usr/bin/bash
#
# setup.sh — guided setup for Obsidian Git sync on Android with Termux + LFS
#
# Walks through the whole guide, doing the work for you where it safely can
# and explaining what it is about to do where it can't. Safe to re-run: every
# step checks whether it is already done and skips if so. Nothing is deleted
# without an explicit confirmation.
#
# Usage:  bash setup.sh
#
# https://github.com/bersimao/obsidian-termux-sync

set -u

# ── Appearance ────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[0m'
  GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[36m'
else
  B=""; DIM=""; R=""; GREEN=""; YELLOW=""; RED=""; BLUE=""
fi

STEP_NUM=0
SKIPPED=0
DONE_COUNT=0

step()  { STEP_NUM=$((STEP_NUM+1)); printf '\n%s━━ Step %d — %s %s\n' "$B$BLUE" "$STEP_NUM" "$1" "$R"; }
info()  { printf '   %s\n' "$1"; }
note()  { printf '   %s%s%s\n' "$DIM" "$1" "$R"; }
ok()    { DONE_COUNT=$((DONE_COUNT+1)); printf '   %s✓%s %s\n' "$GREEN" "$R" "$1"; }
skip()  { SKIPPED=$((SKIPPED+1));     printf '   %s•%s %s %s(already done)%s\n' "$DIM" "$R" "$1" "$DIM" "$R"; }
warn()  { printf '   %s!%s %s\n' "$YELLOW" "$R" "$1"; }
fail()  { printf '   %s✗%s %s\n' "$RED" "$R" "$1"; }
die()   { printf '\n%s✗ %s%s\n\n' "$RED$B" "$1" "$R"; exit 1; }

# ── Prompts ───────────────────────────────────────────────────────────────
#
# Read from a dedicated descriptor so the script still works when its own
# stdin is something else (piped input, `curl … | bash`). Falls back to
# stdin when there is no controlling terminal.

if [ -t 0 ]; then
  exec 3<&0
elif [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then
  exec 3</dev/tty
else
  exec 3<&0
fi

# ask VARNAME "Question" "default"
ask() {
  local __var="$1" __q="$2" __def="${3:-}"
  local __reply=""
  while :; do
    if ! read -r -u 3 -p "   ${__q}${__def:+ [$__def]}: " __reply; then
      # EOF — no more input will ever arrive.
      if [ -n "$__def" ]; then
        __reply="$__def"; printf '\n'
      else
        die "No input available for: ${__q}"
      fi
    fi
    __reply="${__reply:-$__def}"
    [ -n "$__reply" ] && break
    info "A value is required."
  done
  printf -v "$__var" '%s' "$__reply"
}

# confirm "Question" [default:y|n]
confirm() {
  local __q="$1" __def="${2:-y}" __hint __reply=""
  case "$__def" in y) __hint="Y/n" ;; *) __hint="y/N" ;; esac
  read -r -u 3 -p "   ${__q} [${__hint}]: " __reply || printf '\n'
  __reply="${__reply:-$__def}"
  case "$__reply" in [yY]*) return 0 ;; *) return 1 ;; esac
}

pause() {
  local __x
  printf '\n'
  read -r -u 3 -p "   ${DIM}Press Enter to continue…${R}" __x || printf '\n'
}

# ── Preflight ─────────────────────────────────────────────────────────────

printf '%s\n' "$B"
cat <<'BANNER'
   ┌──────────────────────────────────────────────┐
   │  Obsidian Git Sync — Termux + LFS setup      │
   └──────────────────────────────────────────────┘
BANNER
printf '%s\n' "$R"

if [ ! -d /data/data/com.termux ]; then
  warn "This does not look like Termux."
  info "The script targets Termux on Android and will configure Android-specific"
  info "Git settings that make no sense elsewhere."
  confirm "Continue anyway?" n || die "Stopped."
fi

note "Safe to re-run — finished steps are detected and skipped."
note "Nothing is deleted without asking you first."

# ── Gather settings ───────────────────────────────────────────────────────

printf '\n%s━━ Settings %s\n' "$B$BLUE" "$R"

info "Two things are needed before anything happens."
printf '\n'

ask VAULT_NAME "Vault folder name (under internal storage)" "my-obsidian-vault"
VAULT="$HOME/storage/shared/$VAULT_NAME"
GITDIR="$HOME/${VAULT_NAME}-git"
SHARED_PATH="/storage/emulated/0/$VAULT_NAME"

printf '\n'
info "Git repository URL for this vault."
note "e.g. https://github.com/USER/REPO.git — leave blank if the vault already"
note "exists locally and you will add the remote yourself."
ask REPO_URL "Repository URL" "none"
[ "$REPO_URL" = "none" ] && REPO_URL=""

printf '\n'
info "Vault working tree : ${B}${VAULT}${R}"
info "Git database       : ${B}${GITDIR}/.git${R}  ${DIM}(off FUSE — safe)${R}"
[ -n "$REPO_URL" ] && info "Remote             : ${B}${REPO_URL}${R}"

printf '\n'
confirm "Look right?" y || die "Stopped — run again with different answers."

# ── 1. Packages ───────────────────────────────────────────────────────────

step "Install packages"

PKGS="git git-lfs openssh gh jq curl"
MISSING=""
for p in git git-lfs gh jq curl ssh; do
  command -v "$p" >/dev/null 2>&1 || MISSING="$MISSING $p"
done

if [ -z "$MISSING" ]; then
  skip "git, git-lfs, gh, jq, curl, openssh present"
else
  info "Missing:$MISSING"
  if confirm "Run pkg update && pkg install $PKGS?" y; then
    pkg update -y && pkg upgrade -y && pkg install -y $PKGS \
      && ok "Packages installed" \
      || die "Package installation failed. Fix the errors above and re-run."
  else
    die "Packages are required. Install them and re-run."
  fi
fi

# ── 2. Storage access ─────────────────────────────────────────────────────

step "Storage access"

if [ -d "$HOME/storage/shared" ]; then
  skip "~/storage/shared already available"
else
  command -v termux-setup-storage >/dev/null 2>&1 \
    || die "termux-setup-storage not found — this step needs Termux on Android."
  info "Termux needs permission to read your phone's internal storage,"
  info "which is where Obsidian keeps the vault."
  warn "A system permission dialog will appear — tap Allow."
  pause
  termux-setup-storage
  sleep 2
  if [ -d "$HOME/storage/shared" ]; then
    ok "Storage access granted"
  else
    die "~/storage/shared still missing. Grant the permission and re-run."
  fi
fi

# ── 3. GitHub authentication ──────────────────────────────────────────────

step "GitHub authentication"

if gh auth status >/dev/null 2>&1; then
  GH_USER="$(gh api user --jq .login 2>/dev/null || echo '?')"
  skip "signed in to GitHub as ${B}${GH_USER}${R}"
else
  info "Sign in so Git can push without you pasting tokens."
  note "Choose HTTPS, then authenticate in the browser."
  if confirm "Run gh auth login now?" y; then
    gh auth login && ok "Authenticated" || warn "Sign-in did not complete — you can re-run this later."
  else
    warn "Skipped — pushes will fail until you run: gh auth login"
  fi
fi

# ── 4. Clone or initialize ────────────────────────────────────────────────

step "Vault repository"

if [ -e "$VAULT/.git" ]; then
  skip "$VAULT is already a Git repository"

elif [ -d "$VAULT" ] && [ -n "$(ls -A "$VAULT" 2>/dev/null)" ]; then
  info "Vault folder exists and has files, but is not a Git repo."
  info "It will be initialized in place — your notes are not touched."
  if confirm "Initialize it?" y; then
    mkdir -p "$GITDIR" || die "Could not create $GITDIR"
    git init --separate-git-dir="$GITDIR/.git" "$VAULT" >/dev/null \
      || die "git init failed"
    if [ -n "$REPO_URL" ]; then
      git -C "$VAULT" remote add origin "$REPO_URL" 2>/dev/null \
        && ok "Remote 'origin' added"
    fi
    ok "Initialized in place"
  else
    die "Stopped."
  fi

else
  [ -n "$REPO_URL" ] || die "Vault does not exist and no repository URL was given."

  # A previous failed clone leaves dirs behind that make git refuse.
  LEFTOVER=""
  [ -d "$GITDIR" ] && [ -n "$(ls -A "$GITDIR" 2>/dev/null)" ] && LEFTOVER="$GITDIR"
  [ -d "$VAULT" ]  && [ -n "$(ls -A "$VAULT"  2>/dev/null)" ] && LEFTOVER="$LEFTOVER $VAULT"

  if [ -n "$LEFTOVER" ]; then
    warn "Leftovers from an interrupted clone:"
    for d in $LEFTOVER; do info "  $d"; done
    info "Git refuses to clone into these. They must be removed first."
    if confirm "Delete them?" n; then
      for d in $LEFTOVER; do rm -rf "$d"; done
      ok "Removed"
    else
      die "Stopped — remove them yourself, then re-run."
    fi
  fi

  mkdir -p "$GITDIR" || die "Could not create $GITDIR"
  info "Cloning…"
  if git clone --separate-git-dir="$GITDIR/.git" "$REPO_URL" "$VAULT"; then
    ok "Cloned to $VAULT"
    # An empty checkout means the remote's default branch is unset or odd —
    # everything downstream would silently operate on nothing.
    if ! git -C "$VAULT" rev-parse HEAD >/dev/null 2>&1; then
      warn "The clone produced no commits on the current branch."
      note "If the repository is brand new and empty, that is expected."
      note "Otherwise check its default branch: git -C \"$VAULT\" branch -a"
    fi
  else
    rm -rf "$GITDIR" "$VAULT"
    die "Clone failed — leftovers cleaned up so you can re-run."
  fi
fi

cd "$VAULT" || die "Cannot enter $VAULT"

# ── 5. Git configuration ──────────────────────────────────────────────────

step "Git configuration"

# Global identity
if [ -z "$(git config --global user.name || true)" ]; then
  ask GIT_NAME "Your name for commits" "$(gh api user --jq .login 2>/dev/null || echo '')"
  git config --global user.name "$GIT_NAME"
  ok "user.name set"
else
  skip "user.name = $(git config --global user.name)"
fi

if [ -z "$(git config --global user.email || true)" ]; then
  GH_ID="$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"' 2>/dev/null || echo '')"
  if [ -n "$GH_ID" ]; then
    info "GitHub blocks pushes that expose a private email address."
    info "Using your noreply address avoids that entirely."
    ask GIT_EMAIL "Email for commits" "$GH_ID"
  else
    ask GIT_EMAIL "Email for commits"
  fi
  git config --global user.email "$GIT_EMAIL"
  ok "user.email set"
else
  skip "user.email = $(git config --global user.email)"
fi

# Global behaviour
set_global() {
  if [ "$(git config --global --get "$1" || true)" = "$2" ]; then
    skip "$1 = $2"
  else
    git config --global "$1" "$2" && ok "$1 = $2  ${DIM}($3)${R}"
  fi
}
set_global pull.rebase     true  "linear history, no merge-commit noise"
set_global core.quotepath  false "show accented and non-Latin filenames properly"

if git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$SHARED_PATH"; then
  skip "safe.directory includes the vault"
else
  git config --global --add safe.directory "$SHARED_PATH"
  ok "safe.directory += $SHARED_PATH  ${DIM}(shared storage has a different owner)${R}"
fi

# Local, Android-specific
set_local() {
  if [ "$(git config --local --get "$1" || true)" = "$2" ]; then
    skip "$1 = $2"
  else
    git config --local "$1" "$2" && ok "$1 = $2  ${DIM}($3)${R}"
  fi
}
set_local core.worktree   "$VAULT" "required when .git lives elsewhere"
set_local core.filemode   false    "Android reports every file as 0777"
set_local core.symlinks   false    "FUSE cannot do symlinks"
set_local core.ignorecase true     "Android filesystem is case-insensitive"

# ── 6. Git LFS ────────────────────────────────────────────────────────────

step "Git LFS"

git lfs install >/dev/null 2>&1 && ok "Global LFS filters installed"

mkdir -p "$HOME/.githooks"
set_local core.hooksPath "$HOME/.githooks" "hooks are not found in the default place with a separate git dir"

# --hooks-only does not exist in the git-lfs shipped with Termux.
git lfs install --local >/dev/null 2>&1 \
  && ok "LFS hooks installed into ~/.githooks" \
  || warn "git lfs install --local reported a problem — check 'git lfs env'"

# .gitattributes
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../templates" 2>/dev/null && pwd || true)"

write_from_template_or_heredoc() {
  local target="$1" template="$2"
  if [ -n "$TEMPLATE_DIR" ] && [ -f "$TEMPLATE_DIR/$template" ]; then
    cp "$TEMPLATE_DIR/$template" "$target"
    return 0
  fi
  return 1
}

if [ -f "$VAULT/.gitattributes" ]; then
  skip ".gitattributes exists  ${DIM}(leaving your version alone)${R}"
else
  if ! write_from_template_or_heredoc "$VAULT/.gitattributes" gitattributes; then
    cat > "$VAULT/.gitattributes" <<'EOF'
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
  fi
  ok ".gitattributes written"
fi

# ── 7. .gitignore ─────────────────────────────────────────────────────────

step "Ignore rules"

GITIGNORE_BODY=''
if [ -f "$VAULT/.gitignore" ]; then
  skip ".gitignore exists"
  if ! grep -q "workspace-mobile.json" "$VAULT/.gitignore" 2>/dev/null; then
    warn "It does not ignore workspace-mobile.json — the single worst source of"
    warn "merge conflicts in a multi-device vault."
    if confirm "Append the recommended rules?" y; then
      cat >> "$VAULT/.gitignore" <<'EOF'

# ── Added by setup.sh ──
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/graph.json
.obsidian/plugins/
.obsidian/community-plugins.json
.trash/
.sync.log
.sync.lock
EOF
      ok "Rules appended"
    fi
  fi
else
  if ! write_from_template_or_heredoc "$VAULT/.gitignore" gitignore; then
    cat > "$VAULT/.gitignore" <<'EOF'
# Secrets
.env

# Obsidian per-device state — causes merge conflicts, useless in history
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/graph.json
.trash/

# Community plugins — managed per device
.obsidian/plugins/
.obsidian/community-plugins.json

# Plugin caches (rebuilt automatically)
.obsidian/copilot-index-*.json
.makemd/
*.mdb

# Sync artifacts
.sync.log
.sync.lock

# OS junk
.DS_Store
Thumbs.db
EOF
  fi
  ok ".gitignore written"
fi

# Plugins already tracked? gitignore alone will not stop them syncing.
if git -C "$VAULT" ls-files --error-unmatch .obsidian/plugins >/dev/null 2>&1 \
   || [ -n "$(git -C "$VAULT" ls-files '.obsidian/plugins/*' 2>/dev/null | head -1)" ]; then
  printf '\n'
  warn "Community plugins are already tracked by Git."
  info "Ignoring them only affects future commits — they keep syncing until"
  info "they are removed from the index. Files on disk are NOT deleted here,"
  info "but other devices will lose them on their next pull and must restore"
  info "from a backup."
  if confirm "Untrack .obsidian/plugins now?" n; then
    git -C "$VAULT" rm -r --cached .obsidian/plugins/ >/dev/null 2>&1
    git -C "$VAULT" rm --cached .obsidian/community-plugins.json >/dev/null 2>&1
    ok "Untracked — commit on the next sync"
  else
    note "Skipped. To do it later:"
    note "  git rm -r --cached .obsidian/plugins/"
  fi
fi

# ── 8. Sync script ────────────────────────────────────────────────────────

step "Sync script"

mkdir -p "$HOME/scripts"
SYNC="$HOME/scripts/sync-vault.sh"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"

install_script() {
  local name="$1"
  local dest="$HOME/scripts/$name"
  if [ -n "$SRC_DIR" ] && [ -f "$SRC_DIR/$name" ] && [ "$SRC_DIR/$name" != "$dest" ]; then
    cp "$SRC_DIR/$name" "$dest" && chmod +x "$dest" && return 0
  fi
  return 1
}

if [ -f "$SYNC" ]; then
  skip "$SYNC exists  ${DIM}(leaving it alone)${R}"
else
  if install_script sync-vault.sh; then
    # Point the copied script at this vault.
    sed -i "s|^VAULT=.*|VAULT=\"\$HOME/storage/shared/$VAULT_NAME\"|" "$SYNC"
    ok "Installed from repo and pointed at $VAULT_NAME"
  else
    cat > "$SYNC" <<EOF
#!/data/data/com.termux/files/usr/bin/bash

# Log this run to its own file, keeping the 10 most recent
LOGDIR="\$HOME/sync-logs"
mkdir -p "\$LOGDIR"
LOGFILE="\$LOGDIR/sync-\$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee "\$LOGFILE") 2>&1

echo "=== Sync started: \$(date '+%Y-%m-%d %H:%M:%S') ==="
echo ""

VAULT="\$HOME/storage/shared/$VAULT_NAME"
FAILED=0

cd "\$VAULT" || { echo "✗ Cannot access \$VAULT"; FAILED=1; }

if [ "\$FAILED" -eq 0 ]; then
  # Guard: refuse to sync if a rebase is unfinished
  if [ -d "\$(git rev-parse --git-path rebase-merge)" ] \\
     || [ -d "\$(git rev-parse --git-path rebase-apply)" ]; then
    echo "✗ Rebase in progress — resolve manually before syncing"
    FAILED=1

  # Guard: refuse to sync if a merge is unresolved
  elif [ -f "\$(git rev-parse --git-path MERGE_HEAD)" ]; then
    echo "✗ Unresolved merge — resolve manually before syncing"
    FAILED=1

  else
    # Commit local changes FIRST — rebase refuses to run on a dirty tree
    if ! git diff --quiet || ! git diff --cached --quiet || [ -n "\$(git ls-files --others --exclude-standard)" ]; then
      git add .
      git commit -m "sync: \$(date '+%Y-%m-%d %H:%M')"
      echo "• Local changes committed"
    fi

    # Now pull — stop if the pull itself fails
    if ! git pull --autostash; then
      echo "✗ Pull failed — resolve manually, skipping push"
      FAILED=1

    # Push only if we are ahead of the remote
    elif [ -n "\$(git log @{u}.. 2>/dev/null)" ]; then
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
echo "=== Sync finished: \$(date '+%Y-%m-%d %H:%M:%S') ==="

# Keep only the 10 most recent logs
ls -1t "\$LOGDIR"/sync-*.log 2>/dev/null | tail -n +11 | while read -r old; do
  rm -f "\$old"
done

# Keep Termux open only when something went wrong
if [ "\$FAILED" -ne 0 ]; then
  echo ""
  echo "────────────────────────────────"
  echo "⚠ Sync had problems."
  echo "Press Enter to close…"
  read -r
fi
EOF
    chmod +x "$SYNC"
    ok "Written to $SYNC"
  fi
fi

VIEWER="$HOME/scripts/view-sync-log.sh"
if [ -f "$VIEWER" ]; then
  skip "$VIEWER exists"
else
  if install_script view-sync-log.sh; then
    ok "Log viewer installed from repo"
  else
    cat > "$VIEWER" <<'EOF'
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
    chmod +x "$VIEWER"
    ok "Log viewer written to $VIEWER"
  fi
fi

# ── 9. Widget shortcuts ───────────────────────────────────────────────────

step "Widget shortcuts"

mkdir -p "$HOME/.shortcuts"

link_shortcut() {
  local name="$1" target="$2"
  local link="$HOME/.shortcuts/$name"
  if [ -L "$link" ] || [ -e "$link" ]; then
    skip "$name"
  else
    ln -s "$target" "$link" && ok "$name → $(basename "$target")"
  fi
}

link_shortcut ObsidianSync "$SYNC"
link_shortcut ViewSyncLog  "$VIEWER"

printf '\n'
info "Add them to your home screen: long-press → widget → ${B}Termux Widget${R}"
info "One widget runs the sync, the other shows the last 10 runs."

# ── 10. First sync ────────────────────────────────────────────────────────

step "First sync"

if confirm "Run a sync now to check everything works?" y; then
  printf '\n'
  bash "$SYNC"
else
  note "Run it later with:  bash $SYNC"
fi

# ── Summary ───────────────────────────────────────────────────────────────

printf '\n%s━━ Done %s\n' "$B$GREEN" "$R"
printf '   %d step(s) applied, %d already in place.\n\n' "$DONE_COUNT" "$SKIPPED"

info "Vault     ${B}$VAULT${R}"
info "Git dir   ${B}$GITDIR/.git${R}"
info "Logs      ${B}$HOME/sync-logs/${R}  ${DIM}(10 most recent)${R}"
printf '\n'
info "Open the vault in Obsidian: vault switcher → Open folder as vault → ${B}$VAULT_NAME${R}"
printf '\n'
note "Adding another vault later? Re-run this script with a different name,"
note "then switch the widget to scripts/sync-all-vaults.sh to sync both at once."
printf '\n'
