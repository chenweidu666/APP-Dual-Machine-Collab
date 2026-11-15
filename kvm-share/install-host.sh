#!/bin/bash
# 主机端安装：Deskflow 服务端 + 剪贴板桥 + 自动授权 + 桌面图标
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
PEER=${PEER:-surface}          # ~/.ssh/config 里指向 Surface 的别名
HOST_NAME=$(hostname)
PEER_NAME=${PEER_NAME:-}       # 留空则执行时尝试 ssh 取 hostname

echo "== 依赖检查 =="
missing=()
for c in deskflow-core ydotool wl-copy wl-paste ssh; do
    command -v "$c" >/dev/null || missing+=("$c")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "缺少: ${missing[*]}"
    echo "请先执行: sudo apt install deskflow ydotool wl-clipboard openssh-client"
    exit 1
fi

echo "== 安装脚本到 ~/bin =="
mkdir -p "$HOME/bin"
install -m 755 "$here"/host/bin/*.sh "$HOME/bin/"
install -m 755 "$here"/bin/kvm-indicator.py "$HOME/bin/"

echo "== 安装 Deskflow 配置 =="
mkdir -p "$HOME/.config/Deskflow"
install -m 644 "$here"/host/deskflow/Deskflow.conf "$HOME/.config/Deskflow/Deskflow.conf"
if [ -f "$HOME/.config/Deskflow/screen-layout.conf" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "  已存在 screen-layout.conf，跳过（FORCE=1 覆盖）"
else
    install -m 644 "$here"/host/deskflow/screen-layout.conf "$HOME/.config/Deskflow/screen-layout.conf"
fi

# 屏幕拓扑里的机器名必须和实际 hostname 一致
if [ -n "$PEER_NAME" ]; then
    sed -i "s/chenwei-Surface-Pro/$PEER_NAME/g" "$HOME/.config/Deskflow/screen-layout.conf"
    sed -i "s/i5-5200u/$HOST_NAME/g" "$HOME/.config/Deskflow/screen-layout.conf"
    sed -i "s/i5-5200u/$HOST_NAME/g" "$HOME/.config/Deskflow/Deskflow.conf" 2>/dev/null || true
    echo "  已按 $HOST_NAME / $PEER_NAME 改写屏幕拓扑"
else
    echo "  提示: 屏幕名需与 hostname 一致，若不匹配请设 PEER_NAME=<被控端hostname> 重跑"
fi

echo "== 安装 systemd 用户服务 =="
mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$here"/host/systemd-user/*.service "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
systemctl --user enable --now ydotool 2>/dev/null || true
systemctl --user enable --now deskflow-server
sleep 2
systemctl --user enable --now clipbridge
systemctl --user enable --now kvm-indicator

echo "== 桌面图标 =="
mkdir -p "$HOME/Desktop"
install -m 755 "$here"/host/desktop/*.desktop "$HOME/Desktop/"
gio set "$HOME/Desktop/键鼠共享.desktop" metadata::trusted true 2>/dev/null || true

echo
echo "完成。状态："
systemctl --user is-active deskflow-server clipbridge ydotool | paste -sd' ' -
echo "桌面图标: ~/Desktop/键鼠共享.desktop（点一下开关）"
echo "顶栏状态: 右上角托盘「⌨ KVM」，点击可开关"
echo "命令行:   ~/bin/kvm-share.sh [toggle|start|stop|status]"
