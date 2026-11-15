# Edge 收藏夹同步

把一台机器（默认 `sun`）的 Microsoft Edge 收藏夹，**整份覆盖**到其它机器（默认本机 + `surface`），
并做 MD5 校验，确保三台完全一致。

## 背景

多台机器各自用 Edge，收藏夹会越漂越远。与其手动导出 HTML 再导入，不如直接同步 Chromium 系的
`Bookmarks` 明文 JSON 文件——它是完整快照（书签栏、其它书签、文件夹结构全在里面）。

## 用法

```bash
./edge-bookmark-sync.sh                     # sun → 本机 + surface
./edge-bookmark-sync.sh --dry-run           # 只看动作，不改文件
./edge-bookmark-sync.sh --source sun --targets local,surface,wujie
./edge-bookmark-sync.sh --profile Default   # 指定 Edge 配置文件目录
./edge-bookmark-sync.sh --restore           # 用最近一次备份回滚所有目标
./edge-bookmark-sync.sh --keep-edge         # 不关 Edge（不推荐，见下）
./edge-bookmark-sync.sh --no-verify         # 跳过 MD5 校验
```

输出示例：

```
== 源: sun (.config/microsoft-edge/Default/Bookmarks) ==
源 OK: 41 条 / 19777B / 584e8dbf

目标        条目   MD5        结果
-----------------------------------------------------
local        41    584e8dbf   ✅ 一致
surface      41    584e8dbf   ✅ 一致

全部完成（源 584e8dbfe6945b88c3ab21ef669b045b）
```

## 关键点（踩过的坑）

### 1. 必须先关 Edge

Edge 退出时会把**内存里的收藏夹写回文件**，所以覆盖文件前必须关掉它，否则白干。
脚本默认对每个目标执行 `pkill -x msedge` 并等 2 秒。代价是目标机上的 Edge 会被关闭
（重新打开时一般会恢复上次会话）。

### 2. 覆盖前一定备份

每个目标保留 `Bookmarks.ours-YYYYmmdd-HHMMSS`，用 `--restore` 可一键回滚：

```
Bookmarks                      ← 当前生效
Bookmarks.bak                  ← Edge 自己维护的备份
Bookmarks.ours-20261115-120117 ← 本脚本写的备份
```

### 3. 收藏夹同步会把你覆盖回去

如果目标机的 Edge 登录了账号且开启了 **收藏夹同步**，云端会再把它合并/覆盖回来。
长期以 sun 为准的话，进 `edge://settings/profiles/sync` 关掉「收藏夹」同步。

### 4. 校验要算文件哈希，不要算命令输出

脚本早期版本用 `$(cat file) | md5sum` 校验，`$()` 会吃掉结尾换行 → 永远"不一致"，误报。
正确做法是在目标机上直接 `md5sum 文件`。

## 不同浏览器/系统

- Chrome/Chromium：把 `REL` 里的 `microsoft-edge` 换成 `google-chrome` / `chromium` 即可（同源格式）
- Windows 上的 Edge：路径是 `%LOCALAPPDATA%\Microsoft\Edge\User Data\Default\Bookmarks`，
  用 ssh/rsync 取到再覆盖，格式一致
- 多配置文件：`--profile "Profile 1"`

## 依赖

- `bash`、`openssh-client`、`scp`、`python3`、`md5sum`
- 源和目标都要能免密 `ssh`（`~/.ssh/config` 里配好别名，如 `sun`、`surface`）
