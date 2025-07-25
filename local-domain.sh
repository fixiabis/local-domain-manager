#!/bin/bash

set -e

DOMAIN=""
PORT=3000
IP="127.0.0.1"
NGINX_MAIN_CONF="/opt/homebrew/etc/nginx/nginx.conf"
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVERS_DIR="$BASE_DIR"
DOMAIN_DIR=""

HOSTS_FILE="/etc/hosts"

usage() {
  echo "Usage:"
  echo "  $0 <domain>                                    # Show domain status"
  echo "  $0 <domain> init [-p <port>] [-a <ip>]"
  echo "  $0 <domain> host-mapping <add|remove>"
  echo "  $0 <domain> port change <port>"
  echo "  $0 <domain> ip change <ip>"
  echo "  $0 <domain> cert regenerate"
  echo ""
  echo "Examples:"
  echo "  $0 example.com                                 # Show status"
  echo "  $0 example.com init -p 3000 -a 192.168.1.100"
  echo "  $0 example.com host-mapping add"
  echo "  $0 example.com port change 3000"
  echo "  $0 example.com ip change 192.168.1.100"
  echo "  $0 example.com cert regenerate"
  exit 1
}

check_args() {
  if [ $# -lt 1 ]; then
    usage
  fi

  DOMAIN="$1"
  COMMAND="$2"
  SUBCOMMAND="$3"
  DOMAIN_DIR="$SERVERS_DIR/$DOMAIN"
}

generate_cert() {
  local force_regenerate="$1"

  echo "=== 產生憑證 ==="
  mkdir -p "$DOMAIN_DIR"

  local cert_file="$DOMAIN_DIR/cert.pem"
  local key_file="$DOMAIN_DIR/cert-key.pem"

  if [ "$force_regenerate" = "force" ]; then
    # 強制重新產生，刪除舊憑證
    [ -f "$cert_file" ] && rm "$cert_file"
    [ -f "$key_file" ] && rm "$key_file"
    echo "重新產生 mkcert 憑證..."
  elif [ -f "$cert_file" ] && [ -f "$key_file" ]; then
    echo "憑證已存在於 $DOMAIN_DIR，略過 mkcert。"
    return
  else
    echo "產生新的 mkcert 憑證..."
  fi

  mkcert -cert-file "$cert_file" -key-file "$key_file" "$DOMAIN"
}

add_host_mapping() {
  echo "=== 新增 host mapping ==="
  if grep -qE "^\s*$IP\s+$DOMAIN(\s|$)" "$HOSTS_FILE"; then
    echo "$DOMAIN 已存在於 $HOSTS_FILE"
  else
    echo "新增 $DOMAIN 到 $HOSTS_FILE (需要 sudo 權限)"
    echo "$IP $DOMAIN" | sudo tee -a "$HOSTS_FILE" > /dev/null
    echo "已新增 $DOMAIN 到 hosts 檔案"
  fi
}

remove_host_mapping() {
  echo "=== 移除 host mapping ==="
  if grep -qE "^\s*$IP\s+$DOMAIN(\s|$)" "$HOSTS_FILE"; then
    echo "從 $HOSTS_FILE 移除 $DOMAIN (需要 sudo 權限)"
    sudo sed -i.bak "/^[[:space:]]*$IP[[:space:]]*$DOMAIN[[:space:]]*$/d" "$HOSTS_FILE"
    echo "已從 hosts 檔案移除 $DOMAIN"
  else
    echo "$DOMAIN 不存在於 $HOSTS_FILE"
  fi
}

get_current_port() {
  local nginx_conf="$DOMAIN_DIR/nginx.conf"
  if [ -f "$nginx_conf" ]; then
    grep "proxy_pass" "$nginx_conf" | sed 's/.*127\.0\.0\.1:\([0-9]*\).*/\1/' | head -1
  else
    echo ""
  fi
}

get_current_ip() {
  local nginx_conf="$DOMAIN_DIR/nginx.conf"
  if [ -f "$nginx_conf" ]; then
    grep "proxy_pass" "$nginx_conf" | sed 's/.*http:\/\/\([^:]*\):.*/\1/' | head -1
  else
    echo ""
  fi
}

check_host_mapping() {
  if grep -qE "^\s*[0-9.]+\s+$DOMAIN(\s|$)" "$HOSTS_FILE"; then
    echo "存在"
    return 0
  else
    echo "不存在"
    return 1
  fi
}

check_cert() {
  local cert_file="$DOMAIN_DIR/cert.pem"
  local key_file="$DOMAIN_DIR/cert-key.pem"
  
  if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
    echo "存在"
    return 0
  else
    echo "不存在"
    return 1
  fi
}

change_port() {
  local new_port="$1"
  local nginx_conf="$DOMAIN_DIR/nginx.conf"
  
  if [ ! -f "$nginx_conf" ]; then
    echo "錯誤: $nginx_conf 不存在，請先執行 init 命令"
    exit 1
  fi
  
  local current_port=$(get_current_port)
  if [ "$current_port" = "$new_port" ]; then
    echo "端口已經是 $new_port，無需修改"
    return
  fi
  
  echo "=== 變更端口從 $current_port 到 $new_port ==="
  sed -i.bak "s/127\.0\.0\.1:[0-9]*/127.0.0.1:$new_port/g" "$nginx_conf"
  echo "已更新 nginx 配置，新端口: $new_port"
  
  reload_nginx
}

change_ip() {
  local new_ip="$1"
  local nginx_conf="$DOMAIN_DIR/nginx.conf"
  
  if [ ! -f "$nginx_conf" ]; then
    echo "錯誤: $nginx_conf 不存在，請先執行 init 命令"
    exit 1
  fi
  
  local current_ip=$(get_current_ip)
  if [ "$current_ip" = "$new_ip" ]; then
    echo "IP 已經是 $new_ip，無需修改"
    return
  fi
  
  echo "=== 變更 IP 從 $current_ip 到 $new_ip ==="
  sed -i.bak "s/http:\/\/[^:]*:/http:\/\/$new_ip:/g" "$nginx_conf"
  echo "已更新 nginx 配置，新 IP: $new_ip"
  
  reload_nginx
}

generate_nginx_conf() {
  echo "=== 產生 nginx 配置 ==="
  local nginx_conf="$DOMAIN_DIR/nginx.conf"
  
  mkdir -p "$DOMAIN_DIR"
  
  cat > "$nginx_conf" <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate     $DOMAIN_DIR/cert.pem;
    ssl_certificate_key $DOMAIN_DIR/cert-key.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://$IP:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
  echo "已產生 nginx 配置: $nginx_conf"
}

include_nginx_conf() {
  echo "=== 設定 nginx include ==="
  local include_directive="include $SERVERS_DIR/*/nginx.conf;"

  if grep -Fq "$include_directive" "$NGINX_MAIN_CONF"; then
    echo "nginx.conf 已包含 include 設定"
  else
    echo "將 include 加入 $NGINX_MAIN_CONF (需要權限修改 nginx 主配置)"
    if [ -w "$NGINX_MAIN_CONF" ]; then
      sed -i.bak "/http {/a\\
    $include_directive
    " "$NGINX_MAIN_CONF"
    else
      echo "需要 sudo 權限修改 $NGINX_MAIN_CONF"
      sudo sed -i.bak "/http {/a\\
    $include_directive
    " "$NGINX_MAIN_CONF"
    fi
    echo "已更新 nginx 主配置"
  fi
}

reload_nginx() {
  echo "=== 重新載入 nginx (需要 sudo 權限) ==="
  sudo nginx -s reload
  echo "nginx 已重新載入"
}

cmd_init() {
  # 解析 -p 和 -a 參數
  while [[ $# -gt 0 ]]; do
    case $1 in
      -p)
        PORT="$2"
        shift 2
        ;;
      -a)
        IP="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  
  echo "=== 初始化 $DOMAIN (Port: $PORT) ==="
  
  generate_cert
  add_host_mapping
  generate_nginx_conf
  include_nginx_conf
  reload_nginx

  echo "完成！你現在可以用 https://$DOMAIN 連線，並 proxy_pass 到本地 $PORT 端口。"
}

cmd_host_mapping() {
  case "$SUBCOMMAND" in
    add)
      add_host_mapping
      ;;
    remove)
      remove_host_mapping
      ;;
    *)
      echo "錯誤: host-mapping 需要 add 或 remove 參數"
      usage
      ;;
  esac
}

cmd_port() {
  if [ "$SUBCOMMAND" != "change" ]; then
    echo "錯誤: port 命令需要 change 參數"
    usage
  fi
  
  local new_port="$4"
  if [ -z "$new_port" ]; then
    echo "錯誤: 請指定端口號"
    usage
  fi
  
  change_port "$new_port"
}

cmd_ip() {
  if [ "$SUBCOMMAND" != "change" ]; then
    echo "錯誤: ip 命令需要 change 參數"
    usage
  fi
  
  local new_ip="$4"
  if [ -z "$new_ip" ]; then
    echo "錯誤: 請指定 IP 位址"
    usage
  fi
  
  change_ip "$new_ip"
}

cmd_cert() {
  if [ "$SUBCOMMAND" != "regenerate" ]; then
    echo "錯誤: cert 命令需要 regenerate 參數"
    usage
  fi
  
  generate_cert "force"
  reload_nginx
}

cmd_status() {
  echo "=== $DOMAIN 狀態資訊 ==="
  
  local host_mapping_status=$(check_host_mapping)
  echo "Host mapping: $host_mapping_status"
  
  local cert_status=$(check_cert)
  echo "憑證: $cert_status"
  
  local current_ip=$(get_current_ip)
  if [ -n "$current_ip" ]; then
    echo "IP: $current_ip"
  else
    echo "IP: 未設定"
  fi
  
  local current_port=$(get_current_port)
  if [ -n "$current_port" ]; then
    echo "Port: $current_port"
  else
    echo "Port: 未設定"
  fi
  
  echo ""
  
  if [ ! -f "$DOMAIN_DIR/nginx.conf" ]; then
    echo "狀態: 未初始化 (執行 '$0 $DOMAIN init' 進行初始化)"
  elif [ "$host_mapping_status" = "不存在" ] || [ "$cert_status" = "不存在" ]; then
    echo "狀態: 配置不完整"
  else
    echo "狀態: 已配置完成"
  fi
}

main() {
  check_args "$@"
  
  # 如果只有 domain 參數，顯示狀態
  if [ -z "$COMMAND" ]; then
    cmd_status
    return
  fi
  
  case "$COMMAND" in
    init)
      shift 2  # 移除 domain 和 init
      cmd_init "$@"
      ;;
    host-mapping)
      cmd_host_mapping
      ;;
    port)
      cmd_port "$@"
      ;;
    ip)
      cmd_ip "$@"
      ;;
    cert)
      cmd_cert
      ;;
    *)
      echo "錯誤: 未知命令 '$COMMAND'"
      usage
      ;;
  esac
}

main "$@"
