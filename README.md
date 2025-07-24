# Local Domain Manager

Local Domain Manager 是一個用於在本地開發環境中管理自訂域名的工具。它能自動設定 HTTPS 憑證、Nginx 反向代理，以及 hosts 檔案對應，讓你輕鬆在本地使用自訂域名進行開發。

## 功能特色

- 🔐 自動生成本地 HTTPS 憑證（使用 mkcert）
- 🌐 自動管理 `/etc/hosts` 檔案對應
- 🔄 Nginx 反向代理設定
- 🛠️ 支援動態端口變更
- 🌍 支援動態 IP 變更
- 📝 自動產生和管理 Nginx 配置檔
- 🔄 WebSocket 支援

## 系統需求

確認以下軟體已安裝：

- **nginx** - 用於反向代理
- **mkcert** - 用於生成本地 HTTPS 憑證

### 安裝依賴（macOS）

```bash
# 使用 Homebrew 安裝
brew install nginx mkcert

# 初始化 mkcert
mkcert -install
```

## 使用方式

### 初始化新域名

為新域名設定完整的本地開發環境：

```bash
./local-domain.sh <domain> init [-p <port>] [-a <ip>]
```

範例：
```bash
# 使用預設 IP (127.0.0.1)
./local-domain.sh example.com init -p 3000

# 指定自訂 IP 位址
./local-domain.sh example.com init -p 3000 -a 192.168.1.100
```

這會執行以下操作：
1. 生成 SSL 憑證
2. 新增 hosts 檔案對應
3. 生成 Nginx 配置檔
4. 更新 Nginx 主配置檔
5. 重載 Nginx

### 管理 hosts 檔案對應

```bash
# 新增域名到 hosts 檔案（需要 sudo）
./local-domain.sh <domain> host-mapping add

# 從 hosts 檔案移除域名（需要 sudo）
./local-domain.sh <domain> host-mapping remove
```

### 變更端口

動態變更反向代理的目標端口：

```bash
./local-domain.sh <domain> port change <new-port>
```

範例：
```bash
./local-domain.sh example.com port change 8080
```

### 變更 IP 位址

動態變更反向代理的目標 IP 位址：

```bash
./local-domain.sh <domain> ip change <new-ip>
```

範例：
```bash
# 變更到其他機器的 IP
./local-domain.sh example.com ip change 192.168.1.100

# 變更回本機
./local-domain.sh example.com ip change 127.0.0.1
```

### 重新生成憑證

當憑證過期或需要更新時：

```bash
./local-domain.sh <domain> cert regenerate
```

## 目錄結構

```
Servers/
├── README.md
├── local-domain.sh              # 主要腳本
└── <domain>/                    # 每個域名的配置目錄
    ├── cert.pem                 # SSL 憑證
    ├── cert-key.pem             # SSL 私鑰
    └── nginx.conf               # Nginx 配置檔
```

## Nginx 配置說明

腳本會自動生成包含以下功能的 Nginx 配置：

- HTTP 到 HTTPS 重導向
- SSL/TLS 配置（支援 TLS 1.2 和 1.3）
- 反向代理到指定端口
- WebSocket 支援
- 正確的 Header 轉發

## 常見問題

### 權限問題

某些操作需要 sudo 權限：
- 修改 `/etc/hosts` 檔案
- 修改 Nginx 主配置檔（如果沒有寫入權限）
- 重載 Nginx

### Nginx 主配置位置

腳本預設使用 `/opt/homebrew/etc/nginx/nginx.conf`（Homebrew 安裝的 Nginx）。
如果你的 Nginx 安裝在其他位置，請修改腳本中的 `NGINX_MAIN_CONF` 變數。

### 憑證問題

如果遇到憑證相關問題，可以：
1. 確認 mkcert 已正確安裝和初始化
2. 使用 `cert regenerate` 重新生成憑證
3. 檢查瀏覽器是否信任 mkcert 根憑證

## 使用範例

完整的使用流程：

```bash
# 1. 初始化域名（會自動完成所有設定）
./local-domain.sh my-app.local init -p 3000

# 2. 啟動你的應用程式在 port 3000
npm start

# 3. 在瀏覽器中訪問 https://my-app.local

# 4. 如果需要變更端口
./local-domain.sh my-app.local port change 8080

# 5. 如果需要代理到其他機器
./local-domain.sh my-app.local ip change 192.168.1.100

# 6. 如果不再需要該域名
./local-domain.sh my-app.local host-mapping remove
```

## 注意事項

- 域名預設會指向 `127.0.0.1`，但可透過 `-a` 參數或 `ip change` 命令變更
- IP 變更只會影響 Nginx 反向代理設定，不會修改 hosts 檔案
- 憑證由 mkcert 生成，僅在安裝了相同根憑證的機器上有效
- 變更配置後會自動重載 Nginx
- 建議在移除域名前先停止相關服務
