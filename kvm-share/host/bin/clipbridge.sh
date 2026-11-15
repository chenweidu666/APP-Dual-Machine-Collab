#!/bin/bash
# 剪贴板双向同步桥（主机 Wayland ↔ Surface X11，仅文本）
# Deskflow 1.26 的 Wayland 后端（libei）只管输入，不处理剪贴板，
# 所以用 wl-clipboard + xclip 自己同步。
set -u
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-0}

SURFACE=${SURFACE:-surface}
STATE=/tmp/clipbridge.state
LOCK=/tmp/clipbridge.lock
LOG=/tmp/clipbridge.log
log() { echo "$(date +%H:%M:%S) $*" >> "$LOG"; }

host_clip() { timeout 3 wl-paste --no-newline 2>/dev/null || true; }
state_get() { cat "$STATE" 2>/dev/null || true; }
state_set() { printf '%s' "$1" > "$STATE"; }

# 启动时以主机当前剪贴板为基准，避免被 Surface 上的旧内容覆盖
[ -s "$STATE" ] || host_clip > "$STATE"
log "启动"

# ---- 方向 A：主机 → Surface ----
push_host() {
    local cur
    while :; do
        cur=$(host_clip)
        if [ -n "${cur:-}" ] && [ "$cur" != "$(state_get)" ]; then
            if printf '%s' "$cur" | base64 -w0 \
                | ssh -o BatchMode=yes -o ConnectTimeout=5 "$SURFACE" \
                    'base64 -d | DISPLAY=:0 xclip -selection clipboard' >/dev/null 2>&1; then
                ( flock 9; state_set "$cur" ) 9>"$LOCK"
                log "host→surface ${#cur}B"
            else
                log "host→surface 失败，稍后重试"
            fi
        fi
        sleep 1
    done
}

push_host &
SENDER=$!

# ---- 方向 B：Surface → 主机（一条常驻 ssh，Surface 侧轮询）----
ssh -o BatchMode=yes -o ConnectTimeout=5 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 "$SURFACE" \
    'prev=""; while :; do cur=$(DISPLAY=:0 timeout 3 xclip -o -selection clipboard 2>/dev/null | base64 -w0); if [ "$cur" != "$prev" ]; then prev="$cur"; echo "$cur"; fi; sleep 1; done' \
| while read -r line; do
    [ -z "${line:-}" ] && continue
    txt=$(printf '%s' "$line" | base64 -d 2>/dev/null) || continue
    if [ "$txt" != "$(state_get)" ]; then
        if printf '%s' "$txt" | wl-copy 2>/dev/null; then
            ( flock 9; state_set "$txt" ) 9>"$LOCK"
            log "surface→host ${#txt}B"
        fi
    fi
done

kill "$SENDER" 2>/dev/null
log "退出"
