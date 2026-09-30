# gcmd

[English documentation](README.md)

`gcmd` 是一个 local-first（本地优先）的命令库，适用于 Ghostty 以及其他
terminal（终端）。现在所有存储、搜索、编辑、同步和 macOS 界面都使用同一个
Swift codebase（Swift 代码库）。

打包分发和目标 Mac 安装流程请看：[安装包指南](docs/PACKAGE-SETUP.zh-CN.md)

## 本地安装

在项目根目录执行：

```bash
export PATH="$PWD/gcmd/bin:$PATH"
```

如果希望永久启用 zsh 集成：

```bash
echo 'export PATH="/absolute/path/to/gcmd-command-library/gcmd/bin:$PATH"' >> ~/.zshrc
echo 'source "/absolute/path/to/gcmd-command-library/gcmd/shell/gcmd.zsh"' >> ~/.zshrc
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

默认只构建 current architecture（当前架构）。也可以显式选择：

```bash
./mac-app/build-app.sh --arch arm64
./mac-app/build-app.sh --arch x86_64
./mac-app/build-app.sh --arch universal
./mac-app/build-app.sh --arch all
```

app 是按需启动的 one-shot app（一次性应用）：完成一次操作后自动退出。
快捷键：

- `Ctrl-G`：打开命令搜索。
- `Ctrl-X`：打开保存命令编辑器。

app 运行期间，macOS 菜单栏会暂时显示一个 terminal 图标。popup（弹窗）关闭
后 app 自动退出，图标也会消失。点击图标可以进入搜索、新建命令、同步、打开
数据目录和退出等功能。

同步操作会打开 progress window（进度窗口），实时显示 Git 输出；也可以保存
和测试远程数据仓库地址，或在网络等待过久时取消同步。

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

## SSH 会话

gcmd 会自动包装交互式 `ssh` 调用。直接运行 `ssh user@server` 即可，
远端 shell 里的 `Ctrl-G` 和 `Ctrl-X` 会正常工作。

也可以显式使用：

```bash
gcmd ssh user@server
gcmd ssh -p 2222 user@server
gcmd ssh --remote-port 23456 user@server
```

wrapper 只包装交互式登录。如果命令中包含远端命令（例如
`ssh host uptime`），则直接使用原始 `ssh`，不会建立 bridge。

如果某次不需要 bridge，可以跳过：

```bash
GCMD_NO_BRIDGE=1 ssh user@server
```

这个 wrapper 只在 SSH 进程存活期间建立 loopback reverse tunnel。远端 zsh
或 bash 里的 `Ctrl-G` 会通知本机临时启动 popup；选中命令后，仍会插入当前
Ghostty 终端。远端 `Ctrl-X` 也可以保存当前输入行。退出远端 shell 后，
tunnel 和本地 bridge 会一起结束。

## CLI 用法

详细的 command options（命令选项）、variables（变量）、sync（同步）行为和
troubleshooting（排错）说明见：

[CLI 使用手册](docs/CLI.zh-CN.md)

```bash
gcmd save --title "Git 状态" --tags git,daily "git status -sb"
gcmd list
gcmd list git
gcmd pick
gcmd update COMMAND_ID --title "新标题" --command "新命令"
gcmd delete COMMAND_ID
gcmd import-warp
gcmd path
gcmd doctor
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

`gcmd doctor` 会显示本地命令数量、sync directory（同步目录）、Git remote
（远程地址）、app path（应用路径）、quarantine（隔离标记）和 zsh integration
（zsh 集成）状态。如果目标 Mac 上快捷键或同步异常，先执行这个命令。

## Git 远程同步

先在 GitHub、GitLab 或 Gitea 创建一个 private repository（私有仓库），
然后在第一台 Mac 上执行：

```bash
git clone git@github-lili.com:liliauntthinking-for-agent/gcmd-command-library-data.git \
  ~/Documents/gcmd-command-library-data

gcmd sync init ~/Documents/gcmd-command-library-data
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
