# CLIProxyAPI + PProxy + Codex 账号池部署手册

本文记录一套已经验证可用的部署方式：在 Ubuntu 云服务器上运行 CLIProxyAPI，通过 PProxy/Mihomo 访问 OpenAI，并把多个 Codex OAuth 账号组成统一账号池。本地电脑只通过 SSH 隧道访问管理中心和 API，不把管理端口直接暴露到公网。

## 1. 最终架构

```text
本地 Codex CLI / 管理浏览器
          │
          │ SSH 本地端口转发
          ▼
服务器 127.0.0.1:8317  CLIProxyAPI
          │
          │ proxy-url: http://127.0.0.1:7890
          ▼
服务器 127.0.0.1:7890  PProxy / Mihomo
          │
          ▼
OpenAI / ChatGPT Codex 上游
```

本次实例使用的端口如下。表中的服务器监听地址是推荐的安全目标：

| 服务 | 服务器监听地址 | 建议的本地入口 | 用途 |
| --- | --- | --- | --- |
| CLIProxyAPI | `127.0.0.1:8317` | `127.0.0.1:18317` | `/v1` 模型 API 和 `/v0/management` 管理 API |
| 管理前端 | `127.0.0.1:5173` | `127.0.0.1:5173` | 独立管理页面 |
| OAuth 回调 | `127.0.0.1:1455` | `127.0.0.1:1455` | 添加 Codex OAuth 账号时临时使用 |
| PProxy/Mihomo | `127.0.0.1:7890` | 通常不转发 | CLIProxyAPI 的 HTTP/SOCKS 混合代理出口 |

> 安全原则：8317、5173、1455、7890 和代理控制端口都应只在回环地址监听，或至少由云安全组严格限制。不要把管理密钥、API 密钥、OAuth 文件或代理节点暴露到公网。

## 2. 准备服务器

以下命令以 Ubuntu 用户执行：

```bash
sudo apt update
sudo apt install -y git curl wget ca-certificates build-essential nginx
```

确认系统架构：

```bash
uname -m
```

当前项目的 `go.mod` 要求 Go 1.26。安装时应以仓库实际要求为准。下面以 Linux AMD64 和 Go 1.26.4 为例：

```bash
cd /tmp
wget https://go.dev/dl/go1.26.4.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.26.4.linux-amd64.tar.gz
sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
sudo ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
go version
```

如果 `/usr/local/go` 已存在，先确认它是否属于旧版 Go，再决定是否替换；不要盲目覆盖系统中的其他安装。

## 3. 部署 CLIProxyAPI 后端

### 3.1 克隆并编译

```bash
cd /home/ubuntu
git clone https://github.com/router-for-me/CLIProxyAPI.git
cd /home/ubuntu/CLIProxyAPI
go build -o cli-proxy-api ./cmd/server
./cli-proxy-api --help
```

后续更新源码时：

```bash
cd /home/ubuntu/CLIProxyAPI
git pull --ff-only
go build -o cli-proxy-api.new ./cmd/server
mv cli-proxy-api.new cli-proxy-api
sudo systemctl restart cliproxy-backend.service
```

更新前建议先备份 `config.yaml` 和认证目录。

### 3.2 创建配置文件

```bash
cd /home/ubuntu/CLIProxyAPI
cp config.example.yaml config.yaml
nano config.yaml
```

至少修改这些项目：

```yaml
host: "127.0.0.1"
port: 8317

remote-management:
  allow-remote: false
  secret-key: "<强随机管理密钥>"
  disable-control-panel: false

auth-dir: "~/.cli-proxy-api"

api-keys:
  - "<强随机API密钥>"

# CLIProxyAPI 所有上游请求使用的代理。
proxy-url: "http://127.0.0.1:7890"

quota-exceeded:
  switch-project: true
  switch-preview-model: true

routing:
  strategy: "round-robin"
```

生成随机密钥的示例：

```bash
openssl rand -hex 32
```

两个密钥用途不同：

- 管理密钥用于管理页面和 `/v0/management`。
- API 密钥用于 Codex CLI 和 `/v1`。
- Codex OAuth 凭证保存在 `/home/ubuntu/.cli-proxy-api`，不要提交到 Git。

### 3.3 用 systemd 管理后端

创建 `/etc/systemd/system/cliproxy-backend.service`：

```ini
[Unit]
Description=CLIProxyAPI backend (source checkout)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/CLIProxyAPI
ExecStartPre=/usr/bin/test -x /home/ubuntu/CLIProxyAPI/cli-proxy-api
ExecStartPre=/usr/bin/test -r /home/ubuntu/CLIProxyAPI/config.yaml
ExecStart=/home/ubuntu/CLIProxyAPI/cli-proxy-api --config /home/ubuntu/CLIProxyAPI/config.yaml
Restart=on-failure
RestartSec=5
Environment=HOME=/home/ubuntu
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

加载并启动：

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cliproxy-backend.service
systemctl status cliproxy-backend.service --no-pager
```

常用管理命令：

```bash
sudo systemctl restart cliproxy-backend.service
sudo systemctl stop cliproxy-backend.service
systemctl is-active cliproxy-backend.service
journalctl -u cliproxy-backend.service -f
journalctl -u cliproxy-backend.service -n 100 --no-pager
```

## 4. 部署 PProxy/Mihomo 代理

PProxy 是 Mihomo 的安装和启动脚本。它会在当前目录下创建 `proxy-data`，其中包含 Mihomo、订阅配置、WebUI、代理开关脚本和日志。

### 4.1 安装并导入订阅

```bash
cd /home/ubuntu
git clone https://github.com/w568w/pproxy.git
cd /home/ubuntu/pproxy
bash proxy.sh "<订阅URL>"
```

订阅地址含有访问凭证，不要写入公开文档、Git 仓库或命令截图。

检查、停止和重新启动：

```bash
cd /home/ubuntu/pproxy
bash proxy.sh status
bash proxy.sh stop
bash proxy.sh
```

### 4.2 终端代理开关

PProxy 会生成：

```bash
source /home/ubuntu/pproxy/proxy-data/on
source /home/ubuntu/pproxy/proxy-data/off
```

`on` 会给当前 shell 设置 `http_proxy`、`https_proxy`、`all_proxy` 及其大写形式。需要每次登录自动启用时，可以在 `~/.bashrc` 中加入：

```bash
source ~/pproxy/proxy-data/on
```

注意：这只改变交互式 shell。systemd 不读取用户的 `.bashrc`，CLIProxyAPI 的 Codex uTLS 请求也不能只依赖这些变量。

### 4.3 限制监听地址

检查 `/home/ubuntu/pproxy/proxy-data/config/config.yaml`，确保至少包含或等价于：

```yaml
mixed-port: 7890
allow-lan: false
bind-address: 127.0.0.1
external-controller: 127.0.0.1:9090
```

订阅更新可能覆盖该文件，因此更新后要重新检查监听地址：

```bash
sudo ss -ltnp | grep -E ':(7890|9090)\b'
```

如果显示 `0.0.0.0:7890`、`*:7890`、`0.0.0.0:9090` 或 `*:9090`，说明操作系统层面允许外部连接。此时必须修改绑定地址，并确认云安全组没有放行这些端口。

### 4.4 可选：把 Mihomo 交给 systemd

PProxy 默认把 Mihomo 放到后台运行，但不等于由 systemd 托管。若希望重启服务器后自动恢复，可创建 `/etc/systemd/system/pproxy-mihomo.service`：

```ini
[Unit]
Description=PProxy Mihomo outbound proxy
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu/pproxy
ExecStart=/home/ubuntu/pproxy/proxy-data/mihomo -d /home/ubuntu/pproxy/proxy-data/config -ext-ctl 127.0.0.1:9090 -ext-ui /home/ubuntu/pproxy/proxy-data/metacubexd
Restart=always
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

首次切换到 systemd 前，先停止脚本启动的旧进程，避免端口冲突：

```bash
cd /home/ubuntu/pproxy
bash proxy.sh stop
sudo systemctl daemon-reload
sudo systemctl enable --now pproxy-mihomo.service
systemctl status pproxy-mihomo.service --no-pager
```

还可以给 CLIProxyAPI 增加依赖 `/etc/systemd/system/cliproxy-backend.service.d/pproxy.conf`：

```ini
[Unit]
After=pproxy-mihomo.service
Wants=pproxy-mihomo.service
```

然后执行：

```bash
sudo systemctl daemon-reload
sudo systemctl restart cliproxy-backend.service
```

## 5. 让 CLIProxyAPI 全局使用 PProxy

这是整个部署中最关键的一步。

### 5.1 必须配置 `proxy-url`

在 `/home/ubuntu/CLIProxyAPI/config.yaml` 中设置：

```yaml
proxy-url: "http://127.0.0.1:7890"
```

然后重启：

```bash
sudo systemctl restart cliproxy-backend.service
systemctl is-active cliproxy-backend.service
```

只在 `.bashrc` 中设置代理不够。CLIProxyAPI 的 Codex 推理链路使用专门的 uTLS HTTP 客户端，它优先读取账号级 `ProxyURL`，其次读取全局 `proxy-url`；未配置时可能直接连接 `chatgpt.com`，最终出现连接超时或地区限制。

### 5.2 建议同时配置 systemd 环境变量

全局 `proxy-url` 负责核心 Codex 推理链路；环境变量可以覆盖使用标准 HTTP Transport 的更新、OAuth 等辅助请求。

创建 `/etc/cliproxy-backend-proxy.env`：

```bash
http_proxy=http://127.0.0.1:7890
https_proxy=http://127.0.0.1:7890
all_proxy=http://127.0.0.1:7890
HTTP_PROXY=http://127.0.0.1:7890
HTTPS_PROXY=http://127.0.0.1:7890
ALL_PROXY=http://127.0.0.1:7890
no_proxy=127.0.0.1,localhost
NO_PROXY=127.0.0.1,localhost
```

创建 `/etc/systemd/system/cliproxy-backend.service.d/proxy.conf`：

```ini
[Service]
EnvironmentFile=/etc/cliproxy-backend-proxy.env
```

应用配置：

```bash
sudo systemctl daemon-reload
sudo systemctl restart cliproxy-backend.service
systemctl show cliproxy-backend.service -p EnvironmentFiles
```

环境变量是补充，不能替代 `config.yaml` 中的 `proxy-url`。

## 6. 部署管理前端

CLIProxyAPI 自带管理面板能力，也可以单独部署管理中心源码。下面是独立前端加 Nginx 的方式。

### 6.1 构建前端

先安装 Node.js 20 或更高版本，然后：

```bash
cd /home/ubuntu
git clone https://github.com/router-for-me/Cli-Proxy-API-Management-Center.git
cd /home/ubuntu/Cli-Proxy-API-Management-Center
npm install
npm run build

sudo install -d -m 755 /var/www/cliproxy-ui
sudo cp -a dist/. /var/www/cliproxy-ui/
```

### 6.2 配置 Nginx

创建 `/etc/nginx/conf.d/cliproxy.conf`：

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 127.0.0.1:5173;
    server_name _;

    root /var/www/cliproxy-ui;
    index index.html;
    client_max_body_size 100m;

    location /v1/ {
        proxy_pass http://127.0.0.1:8317;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location /v0/ {
        proxy_pass http://127.0.0.1:8317;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Authorization $http_authorization;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

检查并重载：

```bash
sudo nginx -t
sudo systemctl enable --now nginx
sudo systemctl reload nginx
```

## 7. 建立本地 SSH 隧道

将以下内容放入本地 `~/.ssh/config`：

```sshconfig
Host cliproxy-server
    HostName <服务器IP>
    User ubuntu
    IdentityFile ~/.ssh/<私钥文件>
    ServerAliveInterval 30
    ServerAliveCountMax 3
    ExitOnForwardFailure yes
    LocalForward 127.0.0.1:5173 127.0.0.1:5173
    LocalForward 127.0.0.1:18317 127.0.0.1:8317
    LocalForward 127.0.0.1:1455 127.0.0.1:1455
```

使用 autossh 后台启动：

```bash
autossh -M 0 -fN -T cliproxy-server
```

建立后可访问：

- 管理中心：`http://127.0.0.1:5173/`
- 后端 API：`http://127.0.0.1:18317/`
- OAuth 回调：浏览器访问 `localhost:1455` 时会转发到服务器的临时回调监听器。

检查转发：

```bash
lsof -nP -iTCP:5173 -sTCP:LISTEN
lsof -nP -iTCP:18317 -sTCP:LISTEN
lsof -nP -iTCP:1455 -sTCP:LISTEN
```

关闭对应后台 SSH 隧道前，应先按 SSH 主机别名精确查找进程，避免误杀其他 SSH 会话：

```bash
pgrep -af 'ssh.*cliproxy-server'
pkill -f 'ssh.*cliproxy-server'
```

## 8. 添加 Codex OAuth 账号并形成账号池

1. 启动 SSH 隧道。
2. 打开 `http://127.0.0.1:5173/`。
3. API 地址填写 `http://127.0.0.1:5173`；如果直接使用后端管理页，则使用 `http://127.0.0.1:18317`。
4. 输入管理密钥，而不是 `/v1` API 密钥。
5. 进入“OAuth 登录”，选择 Codex OAuth 并开始授权。
6. 浏览器跳转到 `http://localhost:1455/auth/callback?...` 时，1455 隧道会把回调交给服务器。
7. 如果页面提供“远程浏览器模式”，也可以复制完整回调 URL，粘贴到管理页面的“回调 URL”输入框提交。
8. 使用不同浏览器配置文件或无痕窗口重复授权其他 ChatGPT/Codex 账号，避免浏览器自动复用同一账号。
9. 在“认证文件”页面确认多个 Codex JSON 文件均为 `active`。

账号文件默认保存在：

```text
/home/ubuntu/.cli-proxy-api/
```

CLIProxyAPI 会监控认证目录；新增账号通常不需要重启服务。当前配置使用 `round-robin`，多个可用账号会轮询；某个账号不可用或超出额度时，会自动尝试其他账号。

## 9. 配置本地 Codex CLI

编辑本地 `~/.codex/config.toml`，把 provider 指向 SSH 转发后的 18317：

```toml
model = "gpt-5.4"
model_provider = "cliproxyapi"
model_reasoning_effort = "high"

[model_providers.cliproxyapi]
base_url = "http://127.0.0.1:18317/v1"
experimental_bearer_token = "<CLIProxyAPI的API密钥>"
name = "OpenAI"
wire_api = "responses"
requires_openai_auth = true
supports_websockets = true
```

先查询服务器实际提供的模型：

```bash
curl -H 'Authorization: Bearer <API密钥>' \
  http://127.0.0.1:18317/v1/models
```

多台电脑可以共用同一个服务器账号池。每台电脑分别建立 SSH 隧道，并使用同一个 provider 配置和 API 密钥即可。所有请求最终消耗账号池内账号的额度，因此要控制客户端数量、保护 API 密钥并留意服务条款和账号风控。

## 10. 完整验证流程

### 10.1 检查 PProxy

```bash
cd /home/ubuntu/pproxy
bash proxy.sh status
ss -ltnp | grep ':7890'
```

直接测试代理出口：

```bash
curl -x http://127.0.0.1:7890 \
  --connect-timeout 10 \
  -I https://chatgpt.com/
```

能快速建立 TLS 连接并收到 HTTP 响应，即说明代理出口可达；HTTP 状态码不一定必须为 200。

### 10.2 检查 CLIProxyAPI

```bash
systemctl is-active cliproxy-backend.service
ss -ltnp | grep ':8317'

curl -H 'Authorization: Bearer <API密钥>' \
  http://127.0.0.1:8317/v1/models
```

### 10.3 发起真实 Responses 请求

`/v1/models` 主要证明本地 API 可用，不能完全证明模型推理已访问上游。最终应执行一次真实请求：

```bash
curl --max-time 120 \
  -H 'Authorization: Bearer <API密钥>' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gpt-5.4",
    "input": "Reply with exactly OK.",
    "max_output_tokens": 32,
    "stream": false
  }' \
  http://127.0.0.1:8317/v1/responses
```

成功标准：HTTP 200，响应对象状态为 `completed`，并产生模型输出。

本次部署的实际验证结果为：

- CLIProxyAPI 服务为 `active`。
- 两个 Codex OAuth 账号均为 `active` 且 `unavailable: false`。
- `/v1/responses` 返回 HTTP 200。
- 响应状态为 `completed`，测试输出为 `OK`。
- 这证明 Codex 请求已经通过服务器 CLIProxyAPI 和 PProxy 到达 OpenAI 上游。

## 11. 常见问题与排障

### 11.1 `.bashrc` 已启用代理，但 CLIProxyAPI 仍然超时

原因：systemd 不读取 `.bashrc`，而且 Codex uTLS 链路需要显式的 `proxy-url`。

修复：

```yaml
proxy-url: "http://127.0.0.1:7890"
```

然后重启 `cliproxy-backend.service`。

### 11.2 OAuth 成功，但模型请求失败

OAuth 交换令牌与模型推理可能使用不同的 HTTP 客户端。OAuth 能成功不代表推理链路一定使用代理。必须用真实 `/v1/responses` 请求验证。

### 11.3 出现 `unsupported_country_region_territory`

通常说明令牌交换或上游请求使用了不受支持的出口地区。检查：

```bash
curl -x http://127.0.0.1:7890 https://ifconfig.me
journalctl -u cliproxy-backend.service -n 100 --no-pager
```

确认 systemd 环境变量和 `proxy-url` 都已设置，并检查代理节点的实际出口地区。

### 11.4 出现 `bind: address already in use`

说明同一端口已有进程：

```bash
sudo ss -ltnp | grep -E ':(8317|7890|5173|1455)\b'
sudo lsof -nP -iTCP:8317 -sTCP:LISTEN
```

不要同时手工运行 `./cli-proxy-api` 和 systemd 服务。后端由 systemd 管理时，只使用 `systemctl restart cliproxy-backend.service`。

### 11.5 OAuth 回调为什么访问 localhost:1455

这是 OAuth 流程预先注册的本地回调地址。浏览器中的 `localhost` 指浏览器所在电脑，因此远程部署时需要把本地 1455 转发到服务器 1455，或者使用管理页面提供的“提交回调 URL”模式。

### 11.6 查看所有关键状态

```bash
systemctl status cliproxy-backend.service --no-pager
journalctl -u cliproxy-backend.service -f

cd /home/ubuntu/pproxy
bash proxy.sh status
tail -f proxy-data/mihomo.log

sudo ss -ltnp | grep -E ':(7890|8317|5173|1455|9090)\b'
```

## 12. 备份与安全建议

需要备份：

```text
/home/ubuntu/CLIProxyAPI/config.yaml
/home/ubuntu/.cli-proxy-api/
/home/ubuntu/pproxy/proxy-data/config/
/etc/systemd/system/cliproxy-backend.service
/etc/systemd/system/cliproxy-backend.service.d/
/etc/cliproxy-backend-proxy.env
/etc/nginx/conf.d/cliproxy.conf
```

建议：

- 使用至少 32 字节随机管理密钥和 API 密钥，不使用 `123`、`321` 等临时密钥。
- CLIProxyAPI 和管理前端保持监听 `127.0.0.1`，通过 SSH 隧道访问。
- PProxy 的 7890 和控制端口不要向公网放行。
- OAuth 认证文件权限设为仅服务器用户可读，并纳入加密备份。
- 定期查看账号状态、额度、失败日志和代理出口。
- 更新源码、Go、Node、Mihomo 或订阅前先做备份，更新后重新执行真实 Responses 请求。

## 13. 当前服务器部署快照

截至本文整理时，服务器实际状态为：

```text
CLIProxyAPI 源码：/home/ubuntu/CLIProxyAPI
CLIProxyAPI 配置：/home/ubuntu/CLIProxyAPI/config.yaml
CLIProxyAPI 服务：cliproxy-backend.service
CLIProxyAPI 地址：127.0.0.1:8317
认证目录：/home/ubuntu/.cli-proxy-api
全局代理：http://127.0.0.1:7890

PProxy 目录：/home/ubuntu/pproxy
Mihomo 目标地址：127.0.0.1:7890
Mihomo 当前实际监听：*:7890
Mihomo 控制端当前实际监听：*:9090
主机 UFW 当前状态：inactive
PProxy 当前方式：proxy.sh 启动的后台进程，尚未改为 systemd

管理前端目录：/home/ubuntu/Cli-Proxy-API-Management-Center
管理前端发布目录：/var/www/cliproxy-ui
管理前端地址：127.0.0.1:5173
管理前端承载：nginx

账号池：2 个 Codex OAuth 账号
路由策略：round-robin
真实模型请求：已验证 HTTP 200 / completed
```

当前需要优先完成的加固事项：更换临时管理/API 密钥，将 Mihomo 的 7890 和控制端口改为仅监听 `127.0.0.1`，并确认云安全组未放行这些端口。虽然当前代理链路已经工作，但 `*:7890` 和 `*:9090` 表示它们在操作系统层面监听所有网卡；不能把这一状态视为安全配置。如果需要服务器重启后自动恢复代理，再按第 4.4 节将 Mihomo 迁移到 systemd。
