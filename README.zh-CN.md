# gcmd

[English documentation](README.md)

`gcmd` 是一个 local-first（本地优先）的命令库，适用于 Ghostty 以及其他
terminal（终端）。现在所有存储、搜索、编辑、同步和 macOS 界面都使用同一个
Swift codebase（Swift 代码库）。

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

zsh 集成只在按下快捷键时启动 app：

- `Ctrl-G`：搜索命令并替换当前输入行。
- `Ctrl-X`：保存当前输入行。

选中的命令只会插入，不会自动执行。

## macOS App

构建原生 popup（弹窗）应用和 Swift CLI：

```bash
./mac-app/build-app.sh
```

app 是按需启动的 one-shot app（一次性应用）：完成一次操作后自动退出。
快捷键：

- `Ctrl-G`：打开命令搜索。
- `Ctrl-X`：打开保存命令编辑器。

app 和 `gcmd` launcher（启动器）共用同一个 Swift core（核心层）以及 SQLite 数据库。
选中命令后，app 会先复制到剪贴板，并尝试通过 AppleScript 插入当前聚焦的
Ghostty terminal。如果 macOS 尚未允许自动化控制 Ghostty，可以手动按 `Cmd-V`
粘贴。

## zsh 快捷键

zsh widget（zsh 输入组件）直接绑定 control key（控制键），按需启动 app。
因此没有常驻 helper（辅助进程）；只要当前 terminal（终端）运行 zsh 并加载
集成脚本，其他 terminal 也可以使用：

- `Ctrl-G`：打开命令搜索。
- `Ctrl-X`：打开保存编辑器。

重新加载 shell，然后执行：

```bash
source ~/.zshrc
```

## CLI 用法

```bash
gcmd save --title "Git 状态" --tags git,daily "git status -sb"
gcmd list
gcmd list git
gcmd pick
gcmd update COMMAND_ID --title "新标题" --command "新命令"
gcmd delete COMMAND_ID
gcmd import-warp
gcmd path
```

`gcmd import-warp` 会清空本地命令数据库，并从当前 Warp 的 SQLite 数据库导入
全部命令。Warp 文件夹会转换成 tag（标签），Warp 参数会转换成命令变量。

命令可以使用变量，例如：

```text
kubectl -n {{namespace}} get pods
```

在编辑器的 `VARIABLES` 区域添加 `namespace` 后，插入命令时会先弹出参数
填写窗口，再把变量替换成实际值。`WORKING DIRECTORY` 只是记录这条命令
所属的目录上下文，不会自动切换当前 terminal（终端）目录。

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

完整流程请看 [SYNC.zh-CN.md](gcmd/SYNC.zh-CN.md)。

## 项目文件

- `mac-app/Sources/GcmdCore/GcmdCore.swift`：共享存储、搜索和同步核心。
- `mac-app/Sources/GcmdApp/main.swift`：macOS popup app。
- `mac-app/Sources/GcmdCLI/main.swift`：Swift CLI 和 app launcher。
- `gcmd/bin/gcmd`：可执行入口。
- `gcmd/shell/gcmd.zsh`：zsh 快捷键集成。
- `mac-app/Tests/`：Swift 测试。
