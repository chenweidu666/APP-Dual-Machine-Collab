#!/bin/bash
# GNOME 门户「Capture Input」授权（Deskflow 在 Wayland 下必需）
#
# 结论（踩坑记录）：
#   这个对话框**无法可靠地自动确认**。原因有三：
#     1. 「Allow Remote Input Capturing」是开关，状态会沿用上一次的选择，键盘 Tab 无法判断当前状态
#     2. 用 Share 按钮确认时如果开关是关闭，门户直接返回 "CreateSession canceled"，deskflow 随即退出
#     3. 从出现到被取消只有约 2 秒，注入按键的时间窗极窄，实测成功率不稳定
#   因此本脚本退化为「尽力自动确认一次」，失败就安静放弃，**绝不重启服务刷屏**。
#   用户只需在对话框上点一次 Share（开关默认是开的）。
#
# 注意：必须用 /usr/bin/ydotool（apt 版，socket 在 /run/user/<uid>/.ydotool_socket），
#      不要用 ~/.local/bin/ydotool ——那是给 mi-remote 的 Python 垫片，语义不同。
set -u
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
export YDOTOOL_SOCKET=${YDOTOOL_SOCKET:-/run/user/1000/.ydotool_socket}

LOG=/tmp/deskflow-autogrant.log
log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }

[ -S "$YDOTOOL_SOCKET" ] || YDOTOOL_SOCKET=/tmp/.ydotool_socket
[ -S "$YDOTOOL_SOCKET" ] || { log "没有 ydotoold socket，跳过自动确认"; exit 0; }

systemctl --user start ydotool 2>/dev/null
sleep 0.6

# 等对话框出现
seen=0
for _ in $(seq 1 25); do
    if journalctl --user -u xdg-desktop-portal-gnome --since "-6s" --no-pager 2>/dev/null \
        | grep -q "Failed to associate portal window"; then
        seen=1
        break
    fi
    sleep 0.15
done
if [ "$seen" = "0" ]; then
    log "未检测到门户对话框（可能已授权），跳过"
    exit 0
fi

# 对话框默认焦点在 Cancel；Tab 到开关、Tab 到 Share。开关默认是开的，所以只按 Enter 确认。
sleep 0.7
/usr/bin/ydotool key 28:1 28:0
sleep 2.5

if journalctl --user -u deskflow-server --since "-6s" --no-pager 2>/dev/null \
    | grep -q "CreateSession canceled"; then
    log "自动确认失败（门户已取消），请在对话框上点一次 Share"
else
    log "已自动确认，输入捕获应已生效"
fi
exit 0
