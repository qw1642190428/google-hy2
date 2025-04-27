#!/bin/bash

set -e

# 检查root权限
if [ "$EUID" -ne 0 ]; then
  echo "请以root权限运行此脚本！"
  exit 1
fi

# 生成随机端口和密码
PORT=$((RANDOM%10000+10000))
PASSWORD=$(head -c 16 /dev/urandom | base64)

# 交互输入ZeroTier网络ID
read -p "请输入ZeroTier网络ID: " ZT_NET_ID

# 安装ZeroTier
if ! command -v zerotier-cli &> /dev/null; then
  echo "正在安装ZeroTier..."
  curl -s https://install.zerotier.com | bash
fi

# 启动ZeroTier服务
systemctl enable zerotier-one
systemctl start zerotier-one

# 加入ZeroTier网络
zerotier-cli join $ZT_NET_ID

# 获取本机ZeroTier Node ID
ZT_NODE_ID=$(zerotier-cli info | awk '{print $3}')

# 等待获取ZeroTier IP（延长至最多30次，每次2秒，约1分钟）
ZT_IP=""
for i in {1..30}; do
  ZT_IP=$(zerotier-cli listnetworks | grep $ZT_NET_ID | awk '{print $8}' | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -n1)
  if [[ -n "$ZT_IP" ]]; then
    break
  fi
  echo "等待ZeroTier分配IP...\n请登录 https://my.zerotier.com/，在你的网络下授权本节点（Node ID: $ZT_NODE_ID）"
  sleep 2
done
if [[ -z "$ZT_IP" ]]; then
  echo "未能获取ZeroTier分配的IP，请检查网络和ZeroTier状态。"
  exit 1
fi

echo "ZeroTier分配的IP: $ZT_IP"

# 下载歇斯底里2（Hysteria2）
if ! command -v hysteria &> /dev/null; then
  echo "正在下载歇斯底里2..."
  ARCH=$(uname -m)
  if [[ "$ARCH" == "x86_64" ]]; then
    ARCH=amd64
  elif [[ "$ARCH" == "aarch64" ]]; then
    ARCH=arm64
  fi
  VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep tag_name | cut -d '"' -f4)
  wget -O hysteria.tar.gz https://github.com/apernet/hysteria/releases/download/${VER}/hysteria-linux-${ARCH}.tar.gz
  tar -xzf hysteria.tar.gz -C /usr/local/bin hysteria
  chmod +x /usr/local/bin/hysteria
  rm -f hysteria.tar.gz
fi

# 生成歇斯底里2配置文件
cat > hysteria2_config.yaml <<EOF
listen: :$PORT
acme:
  enabled: false
  domains: []
  email: ""
auth:
  type: password
  password: "$PASSWORD"
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

echo "歇斯底里2配置文件已生成: hysteria2_config.yaml"

# 启动歇斯底里2服务
nohup hysteria server -c hysteria2_config.yaml > hysteria2.log 2>&1 &

# 生成分享链接
SHARE_LINK="hysteria2://$PASSWORD@$ZT_IP:$PORT?insecure=1"
echo $SHARE_LINK > hysteria2_share_link.txt

echo "分享链接已保存到 hysteria2_share_link.txt"
echo "安装和配置完成！"
echo "歇斯底里2分享链接: $SHARE_LINK" 
