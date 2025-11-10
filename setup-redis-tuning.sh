#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "请以 root 或使用 sudo 运行此脚本。" >&2
    exit 1
fi

THP_ENABLED="/sys/kernel/mm/transparent_hugepage/enabled"
THP_DEFRAG="/sys/kernel/mm/transparent_hugepage/defrag"

disable_thp() {
    for path in "$THP_ENABLED" "$THP_DEFRAG"; do
        if [[ -w $path ]]; then
            echo never >"$path"
            echo "已写入 never -> $path"
        else
            echo "警告：无法写入 $path，可能内核或权限不支持。" >&2
        fi
    done
}

persist_thp() {
    cat <<'EOF' >/etc/systemd/system/disable-thp.service
[Unit]
Description=Disable Transparent Huge Pages
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'
ExecStart=/bin/sh -c 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now disable-thp.service
    echo "已启用 disable-thp systemd 服务。"
}

apply_sysctl() {
    sysctl -w net.core.somaxconn=1024 >/dev/null
    cat <<'EOF' >/etc/sysctl.d/99-redis-tuning.conf
net.core.somaxconn = 1024
EOF
    sysctl --system >/dev/null
    echo "net.core.somaxconn 已设置为 1024 并持久化。"
}

disable_thp
persist_thp
apply_sysctl

echo "Redis 宿主机调优完成。"
