# gcmd

[中文文档](README.zh-CN.md)

`gcmd` is a small local-first command library for Ghostty and other terminals.
It uses one Swift codebase for storage, the macOS popup app, the launcher, and
Git synchronization.

## Install locally

From the project root:

```bash
export PATH="$PWD/gcmd/bin:$PATH"
```

To make it permanent for zsh:

```bash
echo 'export PATH="/absolute/path/to/gcmd-command-library/gcmd/bin:$PATH"' >> ~/.zshrc
echo 'source "/absolute/path/to/gcmd-command-library/gcmd/shell/gcmd.zsh"' >> ~/.zshrc
source ~/.zshrc
```

The zsh integration launches the app only when a shortcut is pressed:

- `Ctrl-G`: search and replace the current input line.
- `Ctrl-X`: save the current input line.

The selected command is inserted but never executed automatically.

## macOS app

Build the native popup app and Swift CLI:

```bash
./mac-app/build-app.sh
```

The app is on-demand. It opens a popup for one operation and exits after the
operation is completed:

- `Ctrl-G`: open command search.
- `Ctrl-X`: open the save command editor.

The app and `gcmd` launcher use the same Swift core and SQLite database.
Selecting a command copies it to the clipboard and attempts to insert it into
the focused Ghostty terminal through AppleScript. If macOS has not granted
automation permission, paste it manually with `Cmd-V`.

## zsh shortcuts

The zsh widget binds control keys directly and launches the app on demand. No
helper process remains alive, and the shortcuts work in any terminal running
zsh after the integration is sourced:

- `Ctrl-G`: open command search.
- `Ctrl-X`: open the save editor.

Reload your shell, then run:

```bash
source ~/.zshrc
```

## CLI

```bash
gcmd save --title "Git status" --tags git,daily "git status -sb"
gcmd list
gcmd list git
gcmd pick
gcmd update COMMAND_ID --title "New title" --command "new command"
gcmd delete COMMAND_ID
gcmd import-warp
gcmd path
```

`gcmd import-warp` clears the local command database and imports workflows
from the current Warp SQLite database. Warp folder names become tags, and Warp
arguments become command variables.

Commands can define placeholders such as:

```text
kubectl -n {{namespace}} get pods
```

Add `namespace` in the editor's `VARIABLES` section. When the command is
inserted, gcmd asks for the values and substitutes them before sending the
command to Ghostty. `WORKING DIRECTORY` records context only; it does not
automatically change the current terminal directory.

Data is stored in:

```text
~/Library/Application Support/gcmd/commands.sqlite3
```

Set `GCMD_HOME` to use another data directory, which is useful for tests.

## Git synchronization

Configure a local checkout of a private Git repository:

```bash
gcmd sync init ~/Documents/private-command-library --git
cd ~/Documents/private-command-library
git remote add origin git@codeup.aliyun.com:YOUR_ACCOUNT/YOUR_PRIVATE_REPO.git
```

Run a normal local reconciliation:

```bash
gcmd sync
```

Run pull, merge, commit, and push explicitly:

```bash
gcmd sync --git
```

The remote format is one JSON file per command under `commands/`. SQLite is
never synchronized directly. When both devices edit the same command, the
local version remains primary and the remote version is kept as a conflict copy.

See [SYNC.md](gcmd/SYNC.md) for the complete sync flow.
