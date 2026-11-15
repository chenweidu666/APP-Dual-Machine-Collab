#!/usr/bin/python3
"""键鼠共享状态指示器（GNOME 右上角托盘图标）

用法: kvm-indicator.py [host|client]
  host   —— 本机是 Deskflow 服务端（键鼠所在机器）
  client —— 本机是 barrier 被控端（Surface）

状态 → 图标/标签:
  已连接   input-keyboard        KVM
  等待/连接中 dialog-information  KVM…
  已关闭   network-offline       KVM —

点击图标可开关共享。依赖: python3-gi, gir1.2-ayatanaappindicator3-0.1,
以及 Ubuntu 默认启用的 ubuntu-appindicators 扩展。
"""
import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("AyatanaAppIndicator3", "0.1")
from gi.repository import AyatanaAppIndicator3 as AppIndicator  # noqa: E402
from gi.repository import GLib, Gtk  # noqa: E402

ROLE = "client" if (len(sys.argv) > 1 and sys.argv[1] == "client") else "host"
APP_ID = "kvm-share-indicator"

ICON = {"on": "input-keyboard", "wait": "dialog-information", "off": "network-offline"}
LABEL = {"on": "KVM", "wait": "KVM…", "off": "KVM —"}
TEXT = {
    "on": "已连接：键鼠共享中",
    "wait": "服务已启动，等待(或正在)连接对端",
    "off": "已关闭，键鼠只在本机",
}


def sh(cmd, timeout=4):
    try:
        return subprocess.run(
            cmd, shell=True, capture_output=True, text=True, timeout=timeout
        ).stdout.strip()
    except Exception:
        return ""


def state_host():
    active = sh("systemctl --user is-active deskflow-server") == "active"
    if not active:
        return "off"
    conns = sh("ss -tn state established '( sport = :24800 )' | tail -n +2")
    return "on" if conns else "wait"


def state_client():
    active = sh("systemctl --user is-active barrier-client") == "active"
    if not active:
        return "off"
    conns = sh("ss -tn state established '( dport = :24800 )' | tail -n +2")
    return "on" if conns else "wait"


def peer_note():
    if ROLE == "host":
        name = sh("ss -tn state established '( sport = :24800 )' | tail -n +2 | head -1")
        return "已连接" if name else "等待 Surface 连接"
    return "已连接主机" if state_client() == "on" else "等待主机"


class Indicator:
    def __init__(self):
        self.ind = AppIndicator.Indicator.new(
            APP_ID, ICON["off"], AppIndicator.IndicatorCategory.HARDWARE
        )
        self.ind.set_status(AppIndicator.IndicatorStatus.ACTIVE)
        self.ind.set_label("KVM —", "")

        self.menu = Gtk.Menu()

        self.item_state = Gtk.MenuItem(label="状态：未知")
        self.item_state.set_sensitive(False)
        self.menu.append(self.item_state)

        self.item_peer = Gtk.MenuItem(label="")
        self.item_peer.set_sensitive(False)
        self.menu.append(self.item_peer)

        self.menu.append(Gtk.SeparatorMenuItem())

        self.item_toggle = Gtk.MenuItem(label="开启 / 关闭")
        self.item_toggle.connect("activate", self.on_toggle)
        self.menu.append(self.item_toggle)

        self.item_refresh = Gtk.MenuItem(label="刷新状态")
        self.item_refresh.connect("activate", lambda *_: self.refresh())
        self.menu.append(self.item_refresh)

        self.menu.append(Gtk.SeparatorMenuItem())
        item_quit = Gtk.MenuItem(label="隐藏指示器")
        item_quit.connect("activate", lambda *_: Gtk.main_quit())
        self.menu.append(item_quit)

        self.menu.show_all()
        self.ind.set_menu(self.menu)
        self.refresh()
        GLib.timeout_add_seconds(3, self.refresh)

    def refresh(self):
        st = state_host() if ROLE == "host" else state_client()
        self.ind.set_icon_full(ICON[st], TEXT[st])
        self.ind.set_label(LABEL[st], "")
        role = "服务端（主机）" if ROLE == "host" else "被控端（Surface）"
        self.item_state.set_label(f"状态：{TEXT[st]}")
        self.item_peer.set_label(f"角色：{role} ｜ {peer_note()}")
        self.item_toggle.set_label("关闭共享" if st != "off" else "开启共享")
        return True

    def on_toggle(self, *_):
        if ROLE == "host":
            sh(f"{os.path.expanduser('~')}/bin/kvm-share.sh toggle", timeout=25)
        else:
            st = state_client()
            sh(
                "systemctl --user {} barrier-client".format(
                    "stop" if st != "off" else "start"
                ),
                timeout=15,
            )
        GLib.timeout_add(1500, self.refresh)


if __name__ == "__main__":
    Indicator()
    Gtk.main()
