#!/bin/bash
# 键鼠共享开关（Deskflow 服务端 = 本机 i5-5200u，被控端 = Surface）
# 用法: kvm-share.sh [toggle|start|stop|status]
set -u
export DBUS_SESSION_BUS_ADDRESS=${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/1000/bus}
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/1000}

SURFACE=surface

say() { command -v notify-send >/dev/null && notify-send -i input-keyboard "键鼠共享" "$1" || echo "$1"; }

srv_active() { systemctl --user is-active --quiet deskflow-server; }
cli_active() { ssh -o BatchMode=yes -o ConnectTimeout=4 "$SURFACE" 'systemctl --user is-active --quiet barrier-client' 2>/dev/null; }

case "${1:-toggle}" in
  start)
      systemctl --user start deskflow-server
      ssh -o BatchMode=yes -o ConnectTimeout=4 "$SURFACE" 'systemctl --user start barrier-client' 2>/dev/null
      sleep 2
      if srv_active; then say "已开启：鼠标往下推 → 进入 Surface（剪贴板共享中）"; else say "启动失败，看 journalctl --user -u deskflow-server"; fi
      ;;
  stop)
      ssh -o BatchMode=yes -o ConnectTimeout=4 "$SURFACE" 'systemctl --user stop barrier-client' 2>/dev/null
      systemctl --user stop deskflow-server
      say "已停止：键鼠只在主机上"
      ;;
  status)
      if srv_active; then srv="服务端运行中"; else srv="服务端已停止"; fi
      if cli_active; then c="Surface 已连接"; else c="Surface 未连接"; fi
      say "$srv / $c"
      ;;
  *)
      if srv_active; then
          ssh -o BatchMode=yes -o ConnectTimeout=4 "$SURFACE" 'systemctl --user stop barrier-client' 2>/dev/null
          systemctl --user stop deskflow-server
          say "已停止：键鼠只在主机上"
      else
          systemctl --user start deskflow-server
          ssh -o BatchMode=yes -o ConnectTimeout=4 "$SURFACE" 'systemctl --user start barrier-client' 2>/dev/null
          sleep 2
          say "已开启：鼠标往下推 → 进入 Surface"
      fi
      ;;
esac
