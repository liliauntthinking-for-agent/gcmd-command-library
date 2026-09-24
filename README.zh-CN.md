# gcmd

[English documentation](README.md)

`gcmd` 是一个 local-first（本地优先）的命令库，适用于 Ghostty 以及其他
terminal（终端）。它不会打开常驻窗口，只有在保存、搜索或同步命令时才会
启动 CLI（命令行工具）。

## 本地安装

在项目根目录执行：

```bash
export PATH="$PWD/gcmd/bin:$PATH"
```

如果希望永久启用 zsh 集成：

```bash
echo 'export PATH="/Users/hrzy/Desktop/gcmd-command-library/gcmd/bin:$PATH"' >> ~/.zshrc
echo 'source "/Users/hrzy/Desktop/gcmd-command-library/gcmd/shell/gcmd.zsh"' >> ~/.zshrc
source ~/.zshrc
```

快捷键：

- `Option-Space`：搜索命令并替换当前输入行。
- `Option-S`：保存当前输入行。

选中的命令只会插入，不会自动执行。

## CLI 用法

```bash
gcmd save --title "Git 状态" --tags git,daily "git status -sb"
gcmd list
gcmd list git
gcmd pick
gcmd delete COMMAND_ID
gcmd path
```

本地数据存储在：

```text
~/Library/Application Support/gcmd/commands.sqlite3
```

测试时可以设置 `GCMD_HOME` 使用独立的数据目录。

## Git 远程同步

先在 Codeup、GitHub、GitLab 或 Gitea 创建一个 private repository（私有仓库），
然后在第一台 Mac 上执行：

```bash
git clone git@codeup.aliyun.com:你的项目路径/gcmd-command-library.git \
  ~/Documents/private-command-library

gcmd sync init ~/Documents/private-command-library
gcmd sync --git
```

日常同步：

```bash
gcmd sync --git
```

这个命令会依次执行：

```text
1. git pull --rebase：拉取远程修改
2. 读取本机 SQLite 数据
3. 读取 commands/*.json
4. 合并本地和远程命令
5. git commit：提交合并结果
6. git push：推送到远程仓库
```

SQLite 数据库不会直接上传。每条命令会被保存成一个 JSON 文件。
两个设备同时修改同一条命令时，gcmd 会保留本地版本，并创建一个
`(conflict copy)` 冲突副本，避免静默覆盖。

完整流程请看 [SYNC.md](gcmd/SYNC.md)。

## 项目文件

- `gcmd/gcmd.py`：核心 CLI。
- `gcmd/bin/gcmd`：可执行入口。
- `gcmd/shell/gcmd.zsh`：zsh 快捷键集成。
- `gcmd/tests/`：测试。
- `ghostty-command-library-demo.html`：交互演示页面。
