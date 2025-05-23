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

# 检查ZeroTier是否已安装
if ! command -v zerotier-cli &> /dev/null; then
  echo "正在安装ZeroTier..."
  curl -s https://install.zerotier.com | bash
  systemctl enable zerotier-one
  systemctl start zerotier-one
else
  echo "ZeroTier已安装，跳过安装步骤。"
  systemctl enable zerotier-one
  systemctl start zerotier-one
fi

# 检查当前已加入的ZeroTier网络及分配的IP
get_networks_with_ip() {
  NETWORK_RAW=$(zerotier-cli listnetworks | tail -n +2)
  NETWORK_LIST=$(echo "$NETWORK_RAW" | awk '{print NR ") " $1 "  " $2}')
  NETWORK_IPS=()
  while read -r line; do
    NET_ID=$(echo "$line" | awk '{print $2}')
    IPS=$(echo "$NETWORK_RAW" | grep "$NET_ID" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -n1)
    if [[ -n "$IPS" ]]; then
      NETWORK_IPS+=("$NET_ID:$IPS")
    fi
  done <<< "$NETWORK_LIST"
}

get_networks_with_ip

# 如果没有网络或没有分配IP，则提示输入网络ID并加入
if [ "${#NETWORK_IPS[@]}" -eq 0 ]; then
  echo "当前未检测到已分配IP的ZeroTier网络。"
  read -p "请输入ZeroTier网络ID: " ZT_NET_ID
  zerotier-cli join $ZT_NET_ID
  # 自动等待授权和分配IP，最多等待1分钟
  for i in {1..30}; do
    sleep 2
    get_networks_with_ip
    if [ "${#NETWORK_IPS[@]}" -gt 0 ]; then
      break
    fi
    NODE_ID=$(zerotier-cli info | awk '{print $3}')
    echo "等待ZeroTier分配IP...请登录 https://my.zerotier.com/ 授权本节点（Node ID: $NODE_ID）"
  done
  if [ "${#NETWORK_IPS[@]}" -eq 0 ]; then
    echo "仍未分配到IP，请检查网络ID、授权状态或稍后重试。"
    exit 1
  fi
fi

echo -e "\n当前节点已加入的ZeroTier网络："
for i in "${!NETWORK_IPS[@]}"; do
  NET_ID=$(echo "${NETWORK_IPS[$i]}" | cut -d: -f1)
  IP=$(echo "${NETWORK_IPS[$i]}" | cut -d: -f2)
  echo "$((i+1))) $NET_ID  $IP"
done
read -p "请输入你要使用的网络编号: " NET_CHOICE
SELECTED_NET_ID=$(echo "${NETWORK_IPS[$((NET_CHOICE-1))]}" | cut -d: -f1)
ZT_IP=$(echo "${NETWORK_IPS[$((NET_CHOICE-1))]}" | cut -d: -f2)

# 获取本机ZeroTier Node ID
ZT_NODE_ID=$(zerotier-cli info | awk '{print $3}')

# 再次确认IP（等待最多30次，每次2秒）
for i in {1..30}; do
  if [[ -n "$ZT_IP" ]]; then
    break
  fi
  echo "等待ZeroTier分配IP...\n请登录 https://my.zerotier.com/，在你的网络下授权本节点（Node ID: $ZT_NODE_ID）"
  sleep 2
  get_networks_with_ip
  ZT_IP=$(echo "${NETWORK_IPS[$((NET_CHOICE-1))]}" | cut -d: -f2)
done
if [[ -z "$ZT_IP" ]]; then
  echo "未能获取ZeroTier分配的IP，请检查网络和ZeroTier状态。"
  exit 1
fi

echo "ZeroTier分配的IP: $ZT_IP"

# 安装 Hysteria2（官方一键脚本）
if ! command -v hysteria &> /dev/null; then
  echo "正在安装歇斯底里2..."
  bash <(curl -fsSL https://get.hy2.sh/)
fi

# 自动生成自签名证书
if [ ! -f /etc/hysteria/server.crt ] || [ ! -f /etc/hysteria/server.key ]; then
  echo "正在生成自签名证书..."
  mkdir -p /etc/hysteria
  openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
    -subj "/CN=bing.com" -days 36500
  chown hysteria /etc/hysteria/server.key /etc/hysteria/server.crt 2>/dev/null || true
fi

# 生成歇斯底里2配置文件
cat > /etc/hysteria/config.yaml <<EOF
listen: :$PORT
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: "$PASSWORD"
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
EOF

echo "歇斯底里2配置文件已生成: /etc/hysteria/config.yaml"

# 启动/重启歇斯底里2服务
systemctl restart hysteria-server.service
systemctl enable hysteria-server.service

# 生成分享链接
SHARE_LINK="hysteria2://$PASSWORD@$ZT_IP:$PORT?insecure=1"
echo $SHARE_LINK > hysteria2_share_link.txt

echo "分享链接已保存到 hysteria2_share_link.txt"
echo "安装和配置完成！"
echo "歇斯底里2分享链接: $SHARE_LINK" 
