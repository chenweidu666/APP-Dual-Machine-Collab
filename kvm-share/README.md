# Surface KVM Share

把一台 **Linux 主机（GNOME/Wayland）** 的键盘、鼠标、剪贴板共享给一台 **Surface（Linux/X11）**，
效果对标 macOS 的 Universal Control：一套键鼠，光标从主机屏幕边缘滑进另一台机器，剪贴板双向互通。

配套 `surface-tune.sh` 解决 Surface 无风扇机型被固件/pstate 压到 900 MHz 的问题。

```
        ┌────────────────────────────┐        ┌────────────────────────────┐
        │  主机 (GNOME 50 / Wayland)  │        │  Surface (GNOME / X11)     │
        │                            │        │                            │
        │  deskflow-server  ─────────┼───────▶│  barrierc (协议 v1.8)       │
        │    libei + portal 抓输入    │  24800 │    XTest 注入输入           │
        │                            │        │                            │
        │  clipbridge (wl-clipboard) │◀──────▶│  xclip                     │
        │  ydotool + autogrant       │  ssh   │                            │
        └────────────────────────────┘        └────────────────────────────┘
```

## 为什么不是 RDP / 无线投屏

一开始试过 GNOME 远程桌面（RDP + `screen-share-mode=extend` 虚拟显示器），能当扩展屏，但：

- 光标在扩展屏上不可见（FreeRDP + mutter 虚拟显示器组合的问题）
- Ubuntu 的 `freerdp3` 编译时 `WITH_GFX_H264=OFF`，无法走 H.264 硬编，只能软编 → 卡顿
- 只是"多一块屏"，不是"一套键鼠控两台机器"

所以最终方案是 **Deskflow（键鼠共享）+ 自建剪贴板桥**。

## 目录结构

```
bin/kvm-indicator.py           # 右上角托盘状态图标（host/client 两种角色）
host/                          # 装在主机（键鼠所在的机器）
  bin/kvm-share.sh             # 开关脚本：toggle/start/stop/status
  bin/clipbridge.sh            # 剪贴板双向同步桥
  bin/deskflow-autogrant.sh    # 自动确认 GNOME 的「Capture Input」授权对话框
  deskflow/Deskflow.conf       # Deskflow 主配置（服务端模式、关 TLS、开剪贴板）
  deskflow/screen-layout.conf  # 屏幕拓扑（上下排布）
  desktop/键鼠共享.desktop      # 桌面图标（点一下开关共享）
  systemd-user/*.service       # deskflow-server / clipbridge / kvm-indicator
surface/                       # 装在 Surface（被控端）
  bin/surface-tune.sh          # 解除 pstate 频率上限（perf/balanced/powersave）
  systemd/barrier-client.service
  systemd/surface-tune.service
  systemd/kvm-indicator.service
install-host.sh                # 主机一键安装
install-surface.sh             # Surface 一键安装（可直接 scp 过去跑）
```

## 右上角状态图标

两端都会在 GNOME 顶栏（右上角）显示一个托盘项，肉眼就能确认共享状态：

| 图标 | 文字 | 含义 |
|---|---|---|
| ⌨ | `KVM` | 已连接，键鼠+剪贴板共享中 |
| ⓘ | `KVM…` | 服务已起，等待对端连接 |
| ⛔ | `KVM —` | 已关闭，键鼠只在本机 |

点击图标有菜单：状态详情、角色、`开启/关闭共享`、`刷新状态`、`隐藏指示器`。

实现方式：`bin/kvm-indicator.py`（Python + GTK3 + AyatanaAppIndicator3），由 systemd 用户服务
`kvm-indicator.service` 常驻，每 3 秒刷新一次状态。依赖 Ubuntu 默认启用的
**ubuntu-appindicators** 扩展（GNOME 自带的托盘支持）。

> 也可以做成 GNOME Shell 扩展（`St.BoxLayout` + `addToStatusArea`），显示文字更自由，
> 但 **Wayland 下新装扩展必须注销重登才会加载**，所以这里选择托盘方案，改完立即生效。


## 依赖

| 机器 | 依赖 | 说明 |
|---|---|---|
| 主机 | `deskflow` | 键鼠共享服务端（Ubuntu 26.04 源里有 1.26） |
| 主机 | `ydotool` | uinput 虚拟输入，用于自动确认门户对话框 |
| 主机 | `wl-clipboard` | `wl-copy` / `wl-paste`，剪贴板读写 |
| 主机 | `openssh-client` | 连 Surface 起客户端、传剪贴板 |
| Surface | `barrier` | 客户端（Ubuntu 24.04 源里 2.4.0，走 Barrier 协议） |
| Surface | `xclip` `xdotool` | 剪贴板读写 / 测试 |

```bash
# 主机
sudo apt install deskflow ydotool wl-clipboard
# Surface
sudo apt install barrier xclip xdotool
```

## 安装

前提：主机能免密 `ssh surface` 到 Surface（`~/.ssh/config` 里加别名 `surface`）。

```bash
# 主机
./install-host.sh

# Surface（在主机上执行，自动 scp 安装）
./install-surface.sh
```

## 使用

- **光标切换**：鼠标推向主机屏幕**下边缘** → 进入 Surface；从 Surface **上边缘**推回
- **剪贴板**：任一机器复制文本，另一台直接粘贴（约 1 秒延迟，仅文本）
- **桌面图标**：`键鼠共享` —— 点一下切换开/关（会弹通知）
- **命令行**：

```bash
~/bin/kvm-share.sh status     # 看服务端 / 客户端状态
~/bin/kvm-share.sh stop       # 只在主机上用键鼠
~/bin/kvm-share.sh start      # 恢复共享
```

## 关键实现说明

### 1. 为什么 `tlsEnabled=false`

Deskflow 1.26 默认强制 TLS（`~/.config/Deskflow/tls/deskflow.pem`），
而 Ubuntu 源里的 `barrier` 2.4 客户端只认老协议。关掉 TLS 后握手成功：

```
[server] INFO: saying hello as Barrier, protocol v1.8
[server] IPC: client "chenwei-Surface-Pro" has connected
```

服务端配置里 `protocol = barrier`，否则会按新协议打招呼。

### 2. 为什么需要 ydotool 自动点授权

Wayland 下抓全局输入必须经 `org.freedesktop.portal.RemoteDesktop`，
GNOME 会弹 **「Capture Input / Allow Remote Input Capturing」** 模态框，**sudo 也替不了**（这是安全门，不是权限问题）。

`deskflow-autogrant.sh` 目前是**尽力而为**，实测无法稳定自动化，原因：

1. 「Allow Remote Input Capturing」是开关，状态会沿用上一次的选择，用 Tab 无法判断当前状态
2. 确认时若开关是关闭，门户直接返回 `CreateSession canceled`，deskflow 随即退出
3. 从对话框出现到被取消只有约 2 秒，注入按键的时间窗极窄（实测约 50% 成功率）

实测过的方案：`Tab→Space→Tab→Enter`、`Space→Tab→Enter`、`Enter`、`Alt+S` 助记键、
绝对坐标鼠标点击（开关/Share），都只能偶发成功。

脚本现在的行为：检测到对话框就按一次 Enter（开关默认是开的，直接确认大概率成功），
失败只写日志，**不会重启服务刷屏**。配合 `deskflow-server.service` 的
`StartLimitIntervalSec=180` / `StartLimitBurst=6` / `RestartSec=10`，
即使失败也最多几分钟内试几次就安静停下。

**最稳的用法**：托盘图标 → 开启共享 → 弹出的对话框上点一次 **Share**（开关默认已开）。
每次 deskflow 重新启动（含每次登录）需要点这一次，这是 GNOME 的安全门，`sudo` 绕不过。

### 3. 剪贴板为什么要自己写桥

Deskflow 的 Wayland 后端（libei）**只处理输入**，二进制里没有任何 `ext-data-control` 相关符号，
所以剪贴板在 GNOME Wayland 主机上完全不工作（实测两个方向都不同步）。

`clipbridge.sh` 的做法：

- 主机侧 `wl-paste` 轮询（1s）→ 变化则 base64 经 ssh 推到 Surface → `xclip`
- Surface 侧一条常驻 ssh 里轮询 `xclip -o` → 变化则回传 → 主机 `wl-copy`
- 用「最后同步内容」文件做去环；**只有写入成功才更新状态**（早期版本先更新状态导致失败后不再重试）
- 启动时以主机剪贴板为基准，避免被 Surface 上的旧内容覆盖

### 4. Surface 频率为什么被压

Surface Pro 5（i5-7300U）默认被限制成：`no_turbo=1`、`max_perf_pct=60`、`EPP=power`、`platform_profile=balanced`
→ 满载只有 **900 MHz**（温度才 47 °C，`core_throttle_count=0`，根本不是过热）。

`surface-tune.sh perf` 放开后满载 **1.7 GHz**，温度 53 °C。

```bash
sudo surface-tune.sh perf        # 最快
sudo surface-tune.sh balanced    # 折中
sudo surface-tune.sh powersave   # 最省电
```

## 排障

| 现象 | 检查 |
|---|---|
| 光标不跨屏 | `journalctl --user -u deskflow-server -n 30 \| grep -E 'switch\|error'` |
| 授权对话框反复弹 | `cat /tmp/deskflow-autogrant.log`，确认有 `已发送确认按键` |
| 剪贴板不动 | `tail -20 /tmp/clipbridge.log`；确认 `wl-paste` 能读到内容 |
| 服务端没监听 | `ss -ltn \| grep 24800`；`systemctl --user status deskflow-server` |
| 客户端连不上 | `ssh surface 'journalctl --user -u barrier-client -n 30 --no-pager'` |
| Surface 卡 | `ssh surface 'grep "cpu MHz" /proc/cpuinfo; sensors \| grep Package'` |

## 已知限制

- 剪贴板**仅文本**，图片/文件不支持（Deskflow 本身也不支持文件传输）
- 剪贴板轮询间隔 1 秒，大段文本有可感延迟
- 屏幕拓扑写死在 `screen-layout.conf`（`i5-5200u` / `chenwei-Surface-Pro`），换机器要改名字
- 主机若是纯 Wayland 且 GNOME 版本低于 46，libei 抓取不可用（本项目在 GNOME 50 上验证）
- Surface 端用的是 `barrier` 2.4 老客户端（Deskflow 1.27 没有 noble 的 deb），协议兼容但功能受限

## 验证环境

- 主机：Ubuntu 26.04.1 LTS + GNOME Shell 50.1（Wayland）+ Deskflow 1.26.0
- Surface：Ubuntu 24.04.4 LTS + linux-surface 6.18.7（X11）+ barrier 2.4.0
