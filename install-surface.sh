#!/bin/bash
# Surface（被控端）安装：barrier 客户端 + 频率调优
# 在主机上执行即可，会通过 ssh 把文件装过去：PEER=surface HOST_IP=192.168.100.188 ./install-surface.sh
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
PEER=${PEER:-surface}                  # ssh 别名
HOST_IP=${HOST_IP:-192.168.100.188}    # 主机（服务端）IP
PEER_NAME=${PEER_NAME:-$(ssh "$PEER" hostname)}

echo "被控端 = $PEER ($PEER_NAME)，服务端 = $HOST_IP"

echo "== 传文件 =="
scp -q "$here"/surface/bin/surface-tune.sh "$PEER":/tmp/surface-tune.sh
scp -q "$here"/surface/systemd/barrier-client.service "$PEER":/tmp/barrier-client.service.tpl
scp -q "$here"/surface/systemd/surface-tune.service "$PEER":/tmp/surface-tune.service

echo "== 安装依赖 + 落地文件 =="
ssh "$PEER" "bash -s" <<EOF
set -e
sudo apt-get install -y barrier xclip xdotool >/dev/null

sudo install -m 755 /tmp/surface-tune.sh /usr/local/bin/surface-tune.sh
sudo install -m 644 /tmp/surface-tune.service /etc/systemd/system/surface-tune.service

mkdir -p ~/.config/systemd/user
sed -e "s|chenwei-Surface-Pro|$PEER_NAME|g" -e "s|192.168.100.188|$HOST_IP|g" \
    /tmp/barrier-client.service.tpl > ~/.config/systemd/user/barrier-client.service

sudo systemctl daemon-reload
sudo systemctl enable --now surface-tune.service
systemctl --user daemon-reload
systemctl --user enable --now barrier-client

echo "== 状态 =="
echo "barrier-client: \$(systemctl --user is-active barrier-client) / \$(systemctl --user is-enabled barrier-client)"
echo "surface-tune:   \$(systemctl is-active surface-tune) / \$(systemctl is-enabled surface-tune)"
EOF

echo
echo "完成。在主机上跑 ~/bin/kvm-share.sh status 确认两端都 active。"
