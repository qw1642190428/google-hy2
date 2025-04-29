#!/bin/bash

set -e
# 安装 unzip
apt update
apt install -y unzip

# 下载 Hy2 最新版
HY2_VER=$(curl -s https://api.github.com/repos/apernet/hysteria/releases/latest | grep tag_name | cut -d '"' -f 4)
wget -O hy2.zip "https://github.com/apernet/hysteria/releases/download/${HY2_VER}/hysteria-linux-amd64.zip"

# 解压
unzip hy2.zip
chmod +x hysteria
mv hysteria /usr/local/bin/hy2


# 创建配置目录
mkdir -p /etc/hysteria
PORT=5666
PASSWORD=$(head -c 8 /dev/urandom | base64)

# 创建 TLS 自签证书
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout /etc/hysteria/privkey.pem -out /etc/hysteria/fullchain.pem \
  -subj "/CN=hy2.local"

# 生成配置文件
cat > /etc/hysteria/config.yaml <<EOF
listen:
  udp: ":${PORT}"
  tls:
    cert: "fullchain.pem"
    key: "privkey.pem"

auth: "${PASSWORD}"

bandwidth:
  up_mbps: 1500
  down_mbps: 1500

congestion_control: cubic

obfs:
  type: none
EOF

# 创建 systemd 服务
cat > /etc/systemd/system/hy2-server.service <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=/usr/local/bin/hy2 server -c /etc/hysteria/config.yaml
Restart=on-failure
User=nobody
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# 启动服务
systemctl daemon-reload
systemctl enable hy2-server
systemctl restart hy2-server

# 输出连接信息
IP=$(hostname -I | awk '{print $1}')
echo
echo "✅ Hysteria2 安装完成！"
echo "服务已启动，监听端口：${PORT}"
echo
echo "▶️ 客户端连接信息："
echo "hy2://${PASSWORD}@${IP}:${PORT}?insecure=1&upmbps=1500&downmbps=1500"
echo
echo "📄 配置文件路径：/etc/hysteria/config.yaml"
