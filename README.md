# CLIProxyAPI Codex Pool Deployment

一套用于 Ubuntu 云服务器的 CLIProxyAPI + PProxy/Mihomo + Codex OAuth 账号池部署编排。

目标是让多台本地电脑通过 SSH 隧道访问同一个服务器 provider，由服务器上的 CLIProxyAPI 统一管理多个 Codex OAuth 账号，并通过 PProxy/Mihomo 代理链路访问 OpenAI 上游。

```text
本地 Codex / 浏览器
        │
        │ SSH / autossh
        ▼
服务器 127.0.0.1:8317  CLIProxyAPI
        │
        │ proxy-url: http://127.0.0.1:7890
        ▼
服务器 127.0.0.1:7890  PProxy / Mihomo
        │
        ▼
OpenAI / ChatGPT Codex
```

## 仓库内容

```text
config/       CLIProxyAPI 和代理环境变量模板
docs/         完整部署、配置、验证和排障文档
nginx/        管理中心反向代理模板
scripts/      检查与常用维护脚本
systemd/      CLIProxyAPI、PProxy 的 systemd 模板
vendor/       上游项目 Git submodule
```

上游项目通过 submodule 管理，避免把第三方源码和本项目的部署配置混在一起：

- [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)
- [PProxy](https://github.com/w568w/pproxy)
- [CLI Proxy API Management Center](https://github.com/router-for-me/Cli-Proxy-API-Management-Center)

## 快速开始

### 1. 克隆本仓库和上游组件

```bash
git clone --recurse-submodules <本仓库地址>
cd cliproxy-codex-pool-deployment
```

如果已经普通克隆：

```bash
git submodule update --init --recursive
```

### 2. 先建立服务器代理

在服务器上安装 PProxy，并导入代理订阅：

```bash
cd /home/ubuntu
git clone https://github.com/w568w/pproxy.git
cd /home/ubuntu/pproxy
bash proxy.sh "<订阅URL>"
bash proxy.sh status
```

不要把真实订阅 URL 提交到 Git；订阅 URL 通常包含访问凭证。

### 3. 编译 CLIProxyAPI

```bash
cd /home/ubuntu
git clone https://github.com/router-for-me/CLIProxyAPI.git
cd /home/ubuntu/CLIProxyAPI
go build -o cli-proxy-api ./cmd/server
```

### 4. 写入配置

以本仓库的模板为基础生成服务器配置：

```bash
cp config/cliproxy.config.example.yaml /home/ubuntu/CLIProxyAPI/config.yaml
nano /home/ubuntu/CLIProxyAPI/config.yaml
```

至少填写真实的管理密钥和 API 密钥，并保留：

```yaml
host: "127.0.0.1"
port: 8317
proxy-url: "http://127.0.0.1:7890"
routing:
  strategy: "round-robin"
```

`proxy-url` 是关键配置。仅在 `.bashrc` 中设置 `http_proxy` 不足以覆盖 CLIProxyAPI 的 Codex uTLS 推理链路。

### 5. 启动后端

```bash
sudo install -m 644 systemd/cliproxy-backend.service \
  /etc/systemd/system/cliproxy-backend.service
sudo install -d -m 755 /etc/systemd/system/cliproxy-backend.service.d
sudo install -m 644 systemd/cliproxy-backend-proxy.conf \
  /etc/systemd/system/cliproxy-backend.service.d/proxy.conf
sudo install -m 600 config/cliproxy-backend-proxy.env.example \
  /etc/cliproxy-backend-proxy.env

sudo systemctl daemon-reload
sudo systemctl enable --now cliproxy-backend.service
```

部署前请检查 systemd 模板中的路径和用户是否符合服务器环境。

### 6. 验证真实模型请求

```bash
curl -x http://127.0.0.1:7890 --connect-timeout 10 -I https://chatgpt.com/

curl -H 'Authorization: Bearer <API密钥>' \
  http://127.0.0.1:8317/v1/models

curl --max-time 120 \
  -H 'Authorization: Bearer <API密钥>' \
  -H 'Content-Type: application/json' \
  -d '{"model":"gpt-5.4","input":"Reply with exactly OK.","max_output_tokens":32,"stream":false}' \
  http://127.0.0.1:8317/v1/responses
```

最终以真实 `/v1/responses` 返回 HTTP 200 和 `completed` 为准。

## 重要安全规则

- 本仓库不保存真实 API 密钥、管理密钥、OAuth JSON、代理订阅 URL 或代理节点配置。
- CLIProxyAPI、管理页面和代理控制端口推荐只监听 `127.0.0.1`，通过 SSH 隧道访问。
- 不要把 `/home/ubuntu/.cli-proxy-api` 上传到 GitHub，即使仓库是 private。
- 部署后立即更换临时密钥，并限制 GitHub 仓库成员权限。
- 多台电脑共用一个 provider 时，实际消耗同一服务器账号池的额度，请保护 API 密钥。

## 完整文档

请阅读 [docs/deployment.md](docs/deployment.md)。其中包含：

- Go、Node、CLIProxyAPI 和 PProxy 的安装
- 配置文件和 systemd 单元
- Nginx 管理前端
- autossh 端口转发
- OAuth 回调 1455 端口
- Codex 多账号池和 round-robin
- 日志、端口冲突、代理不生效的排障
- 备份、升级和安全加固

## 当前已验证结果

本部署方案已经在目标服务器完成验证：

- CLIProxyAPI 源码编译并由 `cliproxy-backend.service` 管理
- PProxy/Mihomo 监听代理端口 `7890`
- 两个 Codex OAuth 账号加载为 active
- CLIProxyAPI 的全局 `proxy-url` 指向 `http://127.0.0.1:7890`
- 真实 `/v1/responses` 请求返回 HTTP 200、状态 `completed`

## 许可证

本仓库的部署文档和模板属于本项目内容。上游组件仍遵循各自仓库中的许可证，使用 submodule 时请同时遵守上游项目的许可和服务条款。
