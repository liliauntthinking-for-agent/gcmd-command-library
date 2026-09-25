# gcmd Git 同步

先理解两个仓库：

```text
gcmd-command-library.git
  代码仓库：保存 gcmd 程序本身

gcmd-command-data.git
  数据仓库：保存你收藏的命令
```

建议为命令数据单独创建一个 private repository（私有仓库）。
不要把命令数据直接混进代码仓库。

## 第一次配置：第一台 Mac

假设你在 Codeup 创建了一个空的私有仓库：

```text
git@codeup.aliyun.com:你的空间/gcmd-command-data.git
```

先 clone（克隆）这个数据仓库：

```bash
git clone git@codeup.aliyun.com:你的空间/gcmd-command-data.git \
  ~/Documents/gcmd-command-data
```

然后告诉 gcmd 这个目录是同步目录：

```bash
cd /Users/hrzy/Desktop/gcmd-command-library
./build/gcmd sync init ~/Documents/gcmd-command-data
```

如果你已经在本地创建了目录，也可以使用：

```bash
./build/gcmd sync init ~/Documents/gcmd-command-data --git
```

## 保存并上传命令

先正常使用 gcmd 保存命令：

```bash
./build/gcmd save --title "查看 Pod" "kubectl get pods"
```

然后执行：

```bash
./build/gcmd sync --git
```

这个命令会自动完成：

```text
1. git pull --rebase
2. 读取本机 SQLite 数据库
3. 把命令写成 commands/*.json
4. 合并远程命令
5. git commit
6. git push
```

上传后，数据仓库大概会变成：

```text
gcmd-command-data/
  commands/
    8b2...json
    c41...json
  .gcmd-state.json
```

SQLite 数据库不会上传。每条命令对应一个 JSON 文件。

## 第二台 Mac

第二台 Mac 先安装同一个 gcmd 项目，然后 clone（克隆）同一个数据仓库：

```bash
git clone git@codeup.aliyun.com:你的空间/gcmd-command-data.git \
  ~/Documents/gcmd-command-data
```

配置同步目录：

```bash
cd /Users/hrzy/Desktop/gcmd-command-library
./build/gcmd sync init ~/Documents/gcmd-command-data
```

下载命令：

```bash
./build/gcmd sync --git
```

之后两台 Mac 都使用同一个命令：

```bash
./build/gcmd sync --git
```

## 日常使用

```text
MacBook 保存命令
    ↓
gcmd sync --git
    ↓
Codeup 命令数据仓库
    ↓
另一台 Mac 执行 gcmd sync --git
    ↓
另一台 Mac 获得命令
```

如果两台设备同时修改同一条命令，gcmd 会保留本地版本，并创建一个
`(conflict copy)` 冲突副本，不会静默覆盖。

## 直接使用当前代码仓库

技术上也可以把当前项目目录作为同步目录：

```bash
cd /Users/hrzy/Desktop/gcmd-command-library
./build/gcmd sync init /Users/hrzy/Desktop/gcmd-command-library
./build/gcmd sync --git
```

但这样会在代码仓库里增加 `commands/` 和 `.gcmd-state.json`。
因此更推荐单独创建 `gcmd-command-data.git`。
