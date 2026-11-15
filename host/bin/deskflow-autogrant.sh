#!/bin/bash
# Deskflow 在 Wayland 下需要 GNOME 的「允许捕获输入」门户授权对话框。
# 这个脚本在 deskflow-server 启动后自动把它确认掉（用 ydotool 注入按键），
# 不给用户手动点击的机会。
#
# 触发依据：xdg-desktop-portal-gnome 弹出窗口时会在日志里写
#   "Failed to associate portal window with parent window"
# 没看到这条日志就绝不发按键（避免误触其它窗口）。
set -u
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
export YDOTOOL_SOCKET=${YDOTOOL_SOCKET:-/tmp/.ydotool_socket}
LOG=/tmp/deskflow-autogrant.log

log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }

# ydotool 服务没起来就拉起来
systemctl --user start ydotool 2>/dev/null
sleep 1

for i in $(seq 1 40); do
    if journalctl --user -u xdg-desktop-portal-gnome --since "-25s" --no-pager 2>/dev/null \
        | grep -q "Failed to associate portal window"; then
        log "检测到门户授权对话框，开始自动确认"
        sleep 1.2
        # Tab 到开关 → 空格打开「Allow Remote Input Capturing」→ Tab 到 Share → Enter
        ydotool key 15:1 15:0; sleep 0.35
        ydotool key 57:1 57:0; sleep 0.35
        ydotool key 15:1 15:0; sleep 0.35
        ydotool key 28:1 28:0
        log "已发送确认按键"
        exit 0
    fi
    sleep 0.5
done
log "超时：没检测到门户对话框（可能这次不需要授权）"
exit 0
