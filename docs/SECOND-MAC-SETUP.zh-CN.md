# 在另一台 Mac 上安装并同步 gcmd

本文用于在另一台 Mac 上安装 gcmd，并同步现有的命令库。

## 1. 配置 SSH key

推荐在新 Mac 生成一把新的 SSH key（SSH 密钥）：

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_lili
pbcopy < ~/.ssh/id_ed25519_lili.pub
```

把复制的公钥添加到 GitHub 账号的 SSH Keys 页面。

创建或编辑 `~/.ssh/config`：

```ssh
Host github-lili.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519_lili
```

验证 key 是否生效：

```bash
ssh -T git@github-lili.com
```

## 2. Clone 代码仓库

```bash
mkdir -p ~/Desktop

git clone \
  git@github-lili.com:liliauntthinking-for-agent/gcmd-command-library.git \
  ~/Desktop/gcmd-command-library
```

## 3. Clone 数据仓库

```bash
git clone \
  git@github-lili.com:liliauntthinking-for-agent/gcmd-command-library-data.git \
  ~/Documents/gcmd-command-library-data
```

代码仓库和命令数据仓库是两个独立的 Git repository（Git 仓库）。

## 4. Build macOS app

```bash
cd ~/Desktop/gcmd-command-library
./mac-app/build-app.sh
```

项目需要 Swift 和 macOS 13 或更高版本。

## 5. 启用 zsh 快捷键

```bash
echo 'export PATH="$HOME/Desktop/gcmd-command-library/gcmd/bin:$PATH"' >> ~/.zshrc
echo 'source "$HOME/Desktop/gcmd-command-library/gcmd/shell/gcmd.zsh"' >> ~/.zshrc
source ~/.zshrc
```

快捷键：

- `Ctrl-G`：打开命令搜索。
- `Ctrl-X`：保存当前输入命令。
- 第一次点击：选中命令。
- 第二次点击：插入并使用命令。
- `Cmd-E`：编辑选中命令。

## 6. 配置并执行同步

告诉 gcmd 数据仓库的位置：

```bash
cd ~/Desktop/gcmd-command-library
./build/gcmd sync init ~/Documents/gcmd-command-library-data
```

从远程仓库拉取命令：

```bash
./build/gcmd sync --git
```

如果输出类似下面内容，说明同步成功：

```text
synced 63 commands
```

以后日常同步：

```bash
cd ~/Desktop/gcmd-command-library
./build/gcmd sync --git
```

## 7. Ghostty 自动插入权限

第一次插入命令时，macOS 可能会询问是否允许 gcmd 控制 Ghostty。
请选择允许。

如果没有出现权限弹窗，命令仍会复制到 clipboard（剪贴板）。
在 Ghostty 中按 `Cmd-V` 即可粘贴。

## 安全提醒

当前数据仓库包含从 Warp 原样导入的命令，其中可能有 token、vkey 或其他
敏感信息。同步到第二台 Mac 前，请确认这些凭据仍然可以公开存储；
更稳妥的做法是使用环境变量或 macOS Keychain。
