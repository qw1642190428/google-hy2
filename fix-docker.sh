#!/bin/bash
# fix-docker.sh
# 自动修复 containerd 和 Docker 启动失败的问题

set -e

echo "[INFO] 正在取消屏蔽 docker.socket 和 docker.service..."
sudo systemctl unmask docker.socket || true
sudo systemctl unmask docker.service || true

echo "[INFO] 正在取消屏蔽 containerd.service..."
sudo systemctl unmask containerd.service || true

echo "[INFO] 正在安装 containerd（如果尚未安装）..."
if ! command -v containerd &> /dev/null; then
    sudo apt update
    sudo apt install -y containerd
fi

echo "[INFO] 正在启用并启动 containerd.service..."
sudo systemctl enable --now containerd.service

echo "[INFO] 检查 containerd.service 状态..."
sudo systemctl status containerd.service --no-pager

echo "[INFO] 正在启用并启动 docker.service..."
sudo systemctl enable --now docker.service

echo "[INFO] 检查 docker.service 状态..."
sudo systemctl status docker.service --no-pager

echo "[SUCCESS] 修复完成。Docker 应该已经正常运行。"
