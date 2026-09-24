# gcmd remote sync

The important idea is:

```text
MacBook local database
        |
        | gcmd sync --git
        v
private Git repository
        |
        | gcmd sync --git
        v
Mac mini local database
```

The SQLite database is never uploaded directly. `gcmd` converts each saved
command into one JSON file:

```text
private-command-library/
  commands/
    2c1...json
    8a4...json
  .gcmd-state.json
```

## One-time setup

Create a private repository on GitHub, GitLab, or Gitea. Then clone it on the
first Mac:

```bash
git clone git@github.com:YOUR_ACCOUNT/YOUR_PRIVATE_REPO.git \
  ~/Documents/private-command-library

gcmd sync init ~/Documents/private-command-library
```

The repository can also be initialized locally:

```bash
gcmd sync init ~/Documents/private-command-library --git
cd ~/Documents/private-command-library
git remote add origin git@github.com:YOUR_ACCOUNT/YOUR_PRIVATE_REPO.git
```

## Daily sync

On the first Mac:

```bash
gcmd sync --git
```

This performs:

```text
1. git pull --rebase
2. Read local SQLite records
3. Read commands/*.json
4. Merge local and remote records
5. Write the merged JSON files
6. git commit
7. git push
```

On the second Mac, install `gcmd`, configure the same repository, and run the
same command:

```bash
gcmd sync init ~/Documents/private-command-library
gcmd sync --git
```

## What happens when both Macs edit one command?

If only one side changed, that change wins. If both sides changed the same
command, `gcmd` keeps the local version and creates a second command with
`(conflict copy)` in its title. This avoids silently losing a command.

## What is remote and what is local?

Remote Git repository:

- JSON command records
- timestamps and tags
- sync state

Local Mac:

- SQLite index
- interactive picker
- shell shortcuts
- current working directory metadata

Never save passwords, API keys, or private keys in a command record. Use shell
environment variables or macOS Keychain references instead.
