# 双机协同（主机 i5-5200u + Surface Pro 5）

一台 Linux 主机 + 一台 Surface（装 Ubuntu + linux-surface）的日常协同工具集。
目标：**一套键鼠控两台、剪贴板互通、收藏夹一致**，外加 Surface 的性能调优。

```
        ┌────────────────────────────┐        ┌────────────────────────────┐
        │  主机 (GNOME 50 / Wayland)  │        │  Surface (GNOME / X11)     │
        │                            │        │                            │
        │  deskflow-server  ─────────┼───────▶│  barrierc (协议 v1.8)       │
        │    libei + portal 抓输入    │  24800 │    XTest 注入输入           │
        │  clipbridge (wl-clipboard) │◀──────▶│  xclip                     │
        │  ydotool + autogrant       │  ssh   │  surface-tune (pstate)     │
        └────────────────────────────┘        └────────────────────────────┘
                    │                                      ▲
                    └──── edge-bookmarks: 以 sun 为准整份覆盖 ─────┘
```

## 目录

```
kvm-share/                 # 键鼠共享 + 剪贴板桥（Deskflow + 自建桥）
  README.md                #   详细说明、踩坑、排障
  install-host.sh          #   主机一键安装
  install-surface.sh       #   Surface 一键安装（scp 过去执行）
  host/                    #   主机侧脚本、Deskflow 配置、systemd 用户服务、桌面图标
  surface/                 #   Surface 侧频率调优、barrier 客户端服务
edge-bookmarks/            # Edge 收藏夹同步（多机整份覆盖 + 备份回滚）
  README.md
  edge-bookmark-sync.sh
```

## 三件事一句话版

| 能力 | 命令 / 位置 | 说明 |
|---|---|---|
| 键鼠共享 | 桌面图标 `键鼠共享`，或 `~/bin/kvm-share.sh toggle` | 光标推过主机**下边缘**进 Surface，推回上边缘回来 |
| 剪贴板 | 自动（`clipbridge` 服务） | 双向文本同步，约 1 秒延迟，不支持图片/文件 |
| 收藏夹同步 | `edge-bookmarks/edge-bookmark-sync.sh` | 以 `sun` 为准整份覆盖本机 + Surface，自动备份可回滚 |

## 安装

```bash
# 键鼠共享 —— 主机
cd kvm-share && PEER_NAME=<被控端hostname> ./install-host.sh

# 键鼠共享 —— Surface（在主机上跑）
HOST_IP=<主机IP> ./install-surface.sh

# 收藏夹同步（无安装，直接跑；需要能 ssh 到 sun 与 surface）
cd ../edge-bookmarks && ./edge-bookmark-sync.sh
```

## 组成明细

| 组件 | 机器 | 作用 |
|---|---|---|
| `deskflow-server` (systemd user) | 主机 | 抓全局输入（libei），监听 24800 |
| `deskflow-autogrant.sh` | 主机 | 自动确认 GNOME「Capture Input」门户对话框（ydotool 播键） |
| `clipbridge` (systemd user) | 主机 | 剪贴板双向桥（wl-clipboard ↔ xclip，常驻 ssh） |
| `ydotool` (systemd user) | 主机 | uinput 虚拟输入，供自动授权使用 |
| `barrier-client` (systemd user) | Surface | 连主机 24800，XTest 注入输入 |
| `surface-tune.sh` (systemd) | Surface | 解除 pstate 频率上限：满载 900 MHz → 1.7 GHz |
| `edge-bookmark-sync.sh` | 主机执行 | 收藏夹整份覆盖 + 备份 + MD5 校验 + `--restore` |

## 为什么不用 RDP 投屏

早期试过 GNOME 远程桌面（`screen-share-mode=extend` 虚拟显示器），能当扩展屏但：光标在扩展屏不可见、
Ubuntu 的 freerdp3 编译时 `WITH_GFX_H264=OFF` 只能软编导致卡顿、且是"多一块屏"而非"一套键鼠控两台"。
相关配置、证书、凭据已全部清除，详见 `kvm-share/README.md`。

## 已验证环境

- 主机：Ubuntu 26.04.1 LTS + GNOME Shell 50.1（Wayland）+ Deskflow 1.26.0
- Surface：Ubuntu 24.04.4 LTS + linux-surface 6.18.7（X11）+ barrier 2.4.0
- 第三方参考源：`sun`（Edge 收藏夹来源机）

## 命名约定

沿用 `~/Linux-App` 的编号规范：

| 位置 | 名称 |
|---|---|
| 本地文件夹 | `12-Dual-Machine-Collab`（`NN-PascalCase`，05/11 已被占用，本仓库取 12） |
| 远程仓库 | `APP-Dual-Machine-Collab`（`APP-` 前缀，与 `APP-Baton`、`APP-System-Monitor-Bar` 一致） |

