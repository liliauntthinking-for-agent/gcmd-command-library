# gcmd

[中文文档](README.zh-CN.md)

`gcmd` is a small local-first command library for Ghostty and other terminals.
It does not open a permanent window. The CLI starts only when you save, search,
or synchronize commands.

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

The integration adds:

- `Option-Space`: search and replace the current input line.
- `Option-S`: save the current input line.

The selected command is inserted but never executed automatically.

## CLI

```bash
gcmd save --title "Git status" --tags git,daily "git status -sb"
gcmd list
gcmd list git
gcmd pick
gcmd delete COMMAND_ID
gcmd path
```

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
