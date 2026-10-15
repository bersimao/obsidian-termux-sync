# Templates

Copy these into your vault, renaming them with the leading dot:

```bash
VAULT=~/storage/shared/my-obsidian-vault

cp templates/gitattributes "$VAULT/.gitattributes"
cp templates/gitignore     "$VAULT/.gitignore"
```

They are stored without the dot here so they don't take effect on this repo itself.

## `gitattributes`

Routes binaries (images, PDFs, audio, video, fonts) through Git LFS and normalizes line endings to LF for text files — which prevents conflicts when the same vault is edited on Android, Windows, macOS and Linux.

## `gitignore`

Excludes the files that cause constant merge conflicts with no value in history:

- `.obsidian/workspace.json` and `workspace-mobile.json` — which tabs are open, rewritten every session
- `.obsidian/plugins/` and `community-plugins.json` — plugin code is large and often platform-specific; let each device manage its own
- Plugin caches, `.trash/`, OS junk, `.env`

Themes, snippets, hotkeys and appearance settings are **not** ignored, so those still sync across devices.

> If you already committed plugins before adding this, `.gitignore` alone won't stop them syncing. Untrack them first:
> ```bash
> git rm -r --cached .obsidian/plugins/
> git rm --cached .obsidian/community-plugins.json
> git commit -m "Stop tracking community plugins"
> ```
> On other devices, back up `.obsidian/plugins/` before pulling — the pull will delete it from disk, and you restore it afterwards.
