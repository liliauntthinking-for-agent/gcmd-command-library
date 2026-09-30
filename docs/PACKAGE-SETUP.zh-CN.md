# gcmd 打包分发与目标机安装

本文只描述 standard flow（标准流程）：在一台 Mac 上构建 package（安装包），
复制到目标 Mac 使用。目标 Mac 不需要安装 Xcode，也不需要运行 SwiftPM
（Swift 包管理器）。

## 1. 在构建机上选择 package

在保存代码仓库的 Mac 上执行：

```bash
cd /path/to/gcmd-command-library
./mac-app/build-app.sh --arch universal
```

如果已经确认目标 Mac 的 architecture（架构），可以生成更小的单架构包：

```bash
# Apple Silicon Mac
./mac-app/build-app.sh --arch arm64

# Intel Mac
./mac-app/build-app.sh --arch x86_64
```

生成的 package（安装包）在：

```text
build/gcmd-macos-universal.zip
build/gcmd-macos-arm64.zip
build/gcmd-macos-x86_64.zip
```

package 里包含这些文件：

```text
gcmd.app    macOS popup app（弹窗应用）
gcmd        CLI launcher（命令行启动器）
gcmd.zsh    zsh shortcut integration（zsh 快捷键集成）
README.txt  使用说明
```

计算 checksum（校验值），方便目标 Mac 确认文件完整：

```bash
shasum -a 256 build/gcmd-macos-x86_64.zip
```

## 2. 传输 package

把 zip file（压缩文件）复制到目标 Mac，例如使用 AirDrop、USB drive（U 盘）
或内部 file transfer（文件传输）。

目标 Mac 需要 macOS 13 或更高版本。

## 3. 在目标 Mac 安装

解压 package：

```bash
unzip gcmd-macos-x86_64.zip -d ~/Tools
```

目录名会类似：

```text
~/Tools/gcmd-macos-x86_64
```

把下面两行加入 `~/.zshrc`。如果之前有旧的 gcmd 配置，先删除或注释：

```bash
export PATH="$HOME/Tools/gcmd-macos-x86_64:$PATH"
source "$HOME/Tools/gcmd-macos-x86_64/gcmd.zsh"
```

重新加载 shell：

```bash
exec zsh
```

`gcmd.app`、`gcmd`、`gcmd.zsh` 必须保持在同一个 folder（目录）。
`gcmd.zsh` 会自动找到旁边的 app 和 CLI。

快捷键：

```text
Ctrl-G        搜索并插入命令
Ctrl-X        保存当前输入命令
Return        插入选中命令
Cmd-E         编辑选中命令
```

选中的命令只会插入当前输入行，不会自动执行。

直接 `ssh` 到服务器以后，本地快捷键不会再被处理。需要远端会话时使用：

```bash
gcmd ssh user@server
```

这个命令只在 SSH 会话期间建立 temporary bridge（临时桥接）。详见
[CLI 使用手册](CLI.zh-CN.md)中的 `ssh` 说明。

## 4. 准备 data repository

命令数据使用独立的 private repository（私有仓库）：

```text
git@github-lili.com:liliauntthinking-for-agent/gcmd-command-library-data.git
```

在目标 Mac 上确认 SSH key（SSH 密钥）可以访问这个 repository，然后 clone：

```bash
git clone git@github-lili.com:liliauntthinking-for-agent/gcmd-command-library-data.git \
  ~/Documents/gcmd-command-library-data
```

配置 gcmd 使用这个目录：

```bash
gcmd sync init ~/Documents/gcmd-command-library-data
```

导入远程命令：

```bash
gcmd sync --git
gcmd list
```

以后日常同步：

```bash
gcmd sync --git
```

完整的 CLI usage（命令行用法）见 [CLI.zh-CN.md](CLI.zh-CN.md)。

如果 Git network access（Git 网络访问）暂时不可用，但 data repository 已经
clone 到本地，可以先导入已下载的 JSON files（JSON 文件）：

```bash
gcmd sync
```

## 5. 检查安装

执行：

```bash
gcmd doctor
```

重点确认：

```text
active commands: 63
app exists: true
app quarantined: false
zsh integration file: /path/to/gcmd.zsh
```

再测试 launcher：

```bash
gcmd launch search
```

如果这个命令能弹出窗口，`Ctrl-G` 也可以使用。

## 6. Ghostty automation permission

第一次插入命令时，macOS 可能询问是否允许 gcmd 控制 Ghostty。选择允许。

如果没有出现授权弹窗，命令仍会复制到 clipboard（剪贴板）。
在 Ghostty 里按 `Cmd-V` 粘贴。

## 安全提醒

data repository 里已经包含从 Warp 原样导入的命令，其中可能有 token、vkey
或其他 credential（凭据）。不要把包含敏感信息的 data repository 设为
public repository（公开仓库）。更稳妥的做法是改用 environment variable
（环境变量）或 macOS Keychain reference（钥匙串引用）。
