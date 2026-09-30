# gcmd CLI 使用手册

`gcmd` 是一个 local-first（本地优先）的 command library（命令库）。
所有命令都操作同一份 local database（本地数据库）；macOS popup app（弹窗
应用）也使用这份数据。CLI（命令行工具）适合快速 save（保存）、search
（搜索）、sync（同步）和 troubleshoot（排错）。

## 基本约定

### 数据位置

默认 database path（数据库路径）是：

```text
~/Library/Application Support/gcmd/commands.sqlite3
```

同步目录和 remote URL（远程地址）保存在：

```text
~/Library/Application Support/gcmd/config.json
```

测试或隔离数据时，可以在所有命令前设置：

```bash
export GCMD_HOME="$HOME/Tests/gcmd-data"
```

### ID 从哪里来

大多数修改命令都需要 command ID（命令 ID）。先用 list（列表）查看：

```bash
gcmd list
```

输出格式：

```text
12a64141-e90b-48e0-8f81-9334f0224c22  Git status
  git status -sb
```

第一列就是 ID。

### 描述和变量在哪编辑

CLI 可以保存 command text（命令文本）、title（标题）、tags（标签）和
working directory（工作目录）。

description（描述）和 variables（变量）建议在 macOS popup app（弹窗应用）
里编辑：

```bash
gcmd launch search
```

选中一条命令后按 `Cmd-E`，在 `DESCRIPTION` 和 `VARIABLES` 区域修改。

## save：保存命令

保存一条简单命令：

```bash
gcmd save "git status -sb"
```

保存时指定 title（标题）和 tags（标签）：

```bash
gcmd save \
  --title "查看 Git 状态" \
  --tags "git,daily" \
  "git status -sb"
```

记录这条命令适用的 working directory（工作目录）：

```bash
gcmd save \
  --title "重启本机 Jenkins" \
  --tags "jenkins,service" \
  --cwd "/etc/init.d" \
  "./jenkins start"
```

从 stdin（标准输入）保存多行命令：

```bash
gcmd save --stdin \
  --title "重启 Jenkins agent" \
  --tags "jenkins,agent"
```

输入完成后按 `Control-D` 结束。

也可以显式使用 `--command`，适合命令本身以 `-` 开头：

```bash
gcmd save \
  --title "显示帮助" \
  --command "git help -a"
```

规则：

- 不写 `--title` 时，默认使用 command text（命令文本）的第一行。
- 标题超过 72 个字符会自动截断。
- tags（标签）会自动去重并按字母顺序保存。
- 如果已存在一条内容完全相同的 active command（有效命令），旧记录会被新记录替换。

## list：查看和搜索

查看全部有效命令：

```bash
gcmd list
```

按 keyword（关键词）过滤。搜索范围包括 title（标题）、command text（命令
文本）、description（描述）、tag（标签）和 variable name（变量名）：

```bash
gcmd list git
gcmd list docker
gcmd list "git status"
```

输出 JSON，方便脚本处理：

```bash
gcmd list --json
gcmd list git --json | jq '.[].command'
```

包含 soft-deleted records（软删除记录）：

```bash
gcmd list --all
```

## pick：交互式选择一条命令

```bash
gcmd pick
```

带初始 query（查询词）：

```bash
gcmd pick --query "docker compose"
```

CLI 会把候选列表和 prompt（提示符）写到 stderr（标准错误），把最终选中的
command text（命令文本）写到 stdout（标准输出）。因此可以配合管道使用：

```bash
gcmd pick --query git | pbcopy
```

直接输入序号后按 `Return`。直接按 `Return` 默认选择第 1 条。

## update：更新命令

先获取 ID：

```bash
gcmd list
```

更新 title（标题）和 command text（命令文本）：

```bash
gcmd update COMMAND_ID \
  --title "查看 Git 状态" \
  --command "git status -sb --branch"
```

只改 tags（标签）：

```bash
gcmd update COMMAND_ID --tags "git,daily,important"
```

只改 cwd（工作目录）：

```bash
gcmd update COMMAND_ID --cwd "/etc/init.d"
```

注意：

- 没有传的 field（字段）会保留原值。
- description（描述）和 variables（变量）会保留原值。
- 如果原记录是 soft-deleted（软删除）状态，update 会让它重新变成 active
  command（有效命令）。

## delete：删除命令

```bash
gcmd delete COMMAND_ID
```

这是 soft delete（软删除）：记录还在本地 SQLite database（SQLite 数据库）
里，但不再出现在默认 search results（搜索结果）中。

查看已删除记录：

```bash
gcmd list --all
```

如果误删，可以用原来的 ID 恢复：

```bash
gcmd update COMMAND_ID --command "原来的命令"
```

## import-warp：从 Warp 导入

从默认 Warp database（Warp 数据库）导入：

```bash
gcmd import-warp
```

显式指定 Warp SQLite file（SQLite 文件）：

```bash
gcmd import-warp "/path/to/warp.sqlite"
```

这个 command（命令）会：

```text
1. 清空当前 gcmd 本地命令表
2. 读取 Warp workflows（Warp 工作流）
3. 把 Warp folder name（Warp 文件夹名）转成 tag（标签）
4. 把 Warp argument（Warp 参数）转成 gcmd variable（gcmd 变量）
5. 导入 command text（命令文本）和 description（描述）
```

这是 destructive operation（破坏性操作）。执行前建议备份：

```bash
cp "$HOME/Library/Application Support/gcmd/commands.sqlite3" \
  "$HOME/Desktop/commands.sqlite3.backup"
```

## path：查看数据目录

```bash
gcmd path
```

输出示例：

```text
/Users/yourname/Library/Application Support/gcmd
```

如果设置了 `GCMD_HOME`，输出会是这个环境变量指向的 directory（目录）。

## sync init：配置同步目录

推荐先 clone（克隆）独立的 data repository（数据仓库）：

```bash
git clone git@github-lili.com:liliauntthinking-for-agent/gcmd-command-library-data.git \
  ~/Documents/gcmd-command-library-data
```

告诉 gcmd 这个目录就是 sync directory（同步目录）：

```bash
gcmd sync init ~/Documents/gcmd-command-library-data
```

如果目录还不存在，也可以让 gcmd 初始化 Git：

```bash
gcmd sync init ~/Documents/gcmd-command-library-data --git
```

`sync init` 只写入 configuration（配置），不会自动 pull（拉取）或 import
（导入）远程命令。

如果目录不是 Git repository（Git 仓库），还需要自行添加 remote（远程地址）：

```bash
cd ~/Documents/gcmd-command-library-data
git remote add origin git@github-lili.com:liliauntthinking-for-agent/gcmd-command-library-data.git
```

更推荐直接 `git clone`，这样 branch（分支）和 upstream（上游分支）会自动配置。

## sync：同步命令

### 只合并本地 sync directory

```bash
gcmd sync
```

这个 command（命令）不访问 network（网络）。它只做：

```text
1. 读取本地 SQLite records（SQLite 记录）
2. 读取 sync directory（同步目录）里的 commands/*.json
3. 合并两边记录
4. 更新本地 SQLite database（SQLite 数据库）
5. 重写 commands/*.json 和 .gcmd-state.json
```

如果第二台 Mac 已经把 data repository clone 到本地，但 Git network access
（Git 网络访问）暂时不可用，这条命令特别有用。

### 执行完整 Git sync

```bash
gcmd sync --git
```

它会按顺序执行：

```text
1. git pull --rebase
2. 读取本地 SQLite records（SQLite 记录）
3. 读取远程 JSON records（JSON 记录）
4. 合并冲突和新增记录
5. 更新本地 SQLite database（SQLite 数据库）
6. 写入 commands/*.json 和 .gcmd-state.json
7. git add
8. 如有变更则 git commit
9. git push
```

临时指定另一个 sync directory（同步目录）：

```bash
gcmd sync --directory /path/to/gcmd-command-library-data --git
```

如果两台设备同时修改同一条命令，gcmd 会保留本地版本，并给远程版本创建一个
`(conflict copy)` conflict copy（冲突副本）。

## launch：打开 popup app

打开 command search（命令搜索）：

```bash
gcmd launch search
```

打开 save editor（保存编辑器），并预填当前命令：

```bash
gcmd launch save --command "git status -sb" --cwd "$PWD"
```

补上 title（标题）和 tags（标签）：

```bash
gcmd launch save \
  --command "kubectl -n staging get pods" \
  --title "查看 Staging Pod" \
  --tags "k8s,staging" \
  --cwd "$PWD"
```

打开 sync window（同步窗口）：

```bash
gcmd launch sync
```

`launch` 会通过 macOS `open` 启动 popup app（弹窗应用）。app 是 one-shot app
（一次性应用），完成操作后自动退出。

## doctor：检查安装状态

遇到 shortcut（快捷键）、app、database（数据库）或 sync（同步）问题时，先执行：

```bash
gcmd doctor
```

它会显示：

```text
data directory          本地数据目录
executable path         当前执行的 gcmd binary（二进制文件）
GCMD_APP                手工指定的 app path（应用路径）
active commands         有效命令数量
total records           包含 soft-deleted records（软删除记录）的总数
sync directory          数据同步目录
remote JSON files       已下载的 JSON command records（JSON 命令记录）
remote URL              data repository（数据仓库）地址
app path / app exists   popup app（弹窗应用）位置和状态
app quarantined         macOS quarantine（隔离标记）
zsh integration file    gcmd.zsh 的路径和加载状态
```

常见结果：

```text
active commands: 0
remote JSON files: 63
```

说明 remote records（远程记录）已经在 sync directory（同步目录）里，但还没
导入 SQLite database（SQLite 数据库）。执行：

```bash
gcmd sync
```

如果能访问 Git，推荐直接执行：

```bash
gcmd sync --git
```

如果显示：

```text
app exists: false
```

说明 launcher（启动器）找不到 app。确认 `gcmd.app` 和 `gcmd` 在同一个
folder（目录），或者设置：

```bash
export GCMD_APP="/Applications/gcmd.app"
```

如果显示：

```text
app quarantined: true
```

在该 package directory（软件包目录）执行：

```bash
xattr -dr com.apple.quarantine gcmd.app
```

## 快捷键对应的 workflow

加载 `gcmd.zsh` 后：

```text
Ctrl-G    打开 search popup（搜索弹窗）
Ctrl-X    把当前输入行送入 save editor（保存编辑器）
```

搜索窗口内：

```text
上下方向键 选择命令
Return    插入选中命令
Cmd-E     编辑选中命令
Esc       返回或退出
```

命令只会 insert（插入）到当前输入行，不会自动 execute（执行）。

## ssh：在远端 shell 使用快捷键

普通 `ssh user@server` 进入远端后，本地 zsh 不再接收 `Ctrl-G`。这是终端
进程模型的正常行为，不是 Ghostty 或 gcmd 失效。

改用 gcmd 的 SSH wrapper：

```bash
gcmd ssh user@example.com
gcmd ssh -p 2222 deploy@example.com
gcmd ssh --remote-port 23456 user@example.com
gcmd ssh --local-port 34567 user@example.com
```

`--remote-port` 是远端 loopback listener（回环监听端口），默认随机选择。
如果该端口已被占用或被远端 sshd 禁止转发，换一个端口重试。`--local-port`
一般不需要设置；默认由 macOS 分配可用端口。

wrapper 会：

```text
1. 在本机 127.0.0.1 启动 temporary bridge（临时桥接）
2. 生成 one-time token（一次性令牌）
3. 建立 SSH reverse tunnel（SSH 反向隧道）
4. 在远端 zsh/bash 里加载 shortcuts（快捷键）
5. SSH 退出时停止 bridge 和 tunnel
```

远端 shell 里的快捷键：

```text
Ctrl-G    唤起本机 gcmd search popup
Ctrl-X    把远端当前输入行送入本机 save editor
```

popup 仍然运行在本地 Mac 上，因此使用的是本地 command library（命令库）。
选中命令后，gcmd 会把它插入当前 focused Ghostty terminal（聚焦终端），
也就是当前的 SSH 会话。

安全限制：

- 本地 bridge 只绑定 `127.0.0.1`。
- URL 中包含 one-time token（一次性令牌）。
- 远端 listener 也只绑定 `127.0.0.1`。
- bridge 不是 daemon（守护进程）；只在 `gcmd ssh` 进程存活期间运行。
- bridge 会在 source（加载）后删除远端临时 bootstrap file（引导文件）。

如果远端显示 `gcmd: SSH bridge unavailable`：

1. 看 SSH 启动时是否有 `Warning: remote port forwarding failed`。
2. 用 `--remote-port PORT` 换端口。
3. 确认远端 `curl` 可用。
4. 确认远端 sshd 允许 loopback remote forwarding（回环远程转发）。
5. 退出后重新执行 `gcmd ssh`，不要复用旧 SSH session（会话）。

## 常用 workflow（工作流）示例

保存一条日常命令：

```bash
gcmd save --title "查看 Git 状态" --tags "git,daily" "git status -sb"
```

保存带变量的命令：

```bash
gcmd save --title "查看 Namespace Pod" --tags "k8s" \
  "kubectl -n {{namespace}} get pods"
```

然后用 popup app（弹窗应用）编辑这条命令，在 `VARIABLES` 区域添加：

```text
namespace
```

以后使用 `Ctrl-G` 搜索并插入时，gcmd 会先要求填写 `namespace`。

在另一台 Mac 拉取最新命令：

```bash
gcmd sync --git
```

检查为什么快捷键不弹窗：

```bash
gcmd doctor
gcmd launch search
```

## 快速 reference（参考）

```bash
# 保存
gcmd save "git status -sb"
gcmd save --title "标题" --tags "a,b" --cwd "/path" "command"
gcmd save --stdin --title "标题"

# 查看
gcmd list
gcmd list QUERY
gcmd list --json
gcmd list --all

# 选择
gcmd pick
gcmd pick --query QUERY

# 修改
gcmd update ID --title "标题"
gcmd update ID --command "新命令"
gcmd update ID --tags "a,b"
gcmd update ID --cwd "/path"

# 删除
gcmd delete ID

# 从 Warp 导入
gcmd import-warp
gcmd import-warp /path/to/warp.sqlite

# SSH bridge（SSH 桥接）
gcmd ssh user@example.com
gcmd ssh -p 2222 user@example.com
gcmd ssh --remote-port 23456 user@example.com

# 同步
gcmd sync init /path/to/data-repository
gcmd sync init /path/to/data-repository --git
gcmd sync
gcmd sync --git
gcmd sync --directory /path/to/data-repository --git

# 诊断和启动
gcmd path
gcmd doctor
gcmd launch search
gcmd launch save --command "command"
gcmd launch sync
```
