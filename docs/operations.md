# 运维速查

## 服务状态

```bash
systemctl status cliproxy-backend.service --no-pager
systemctl is-active cliproxy-backend.service
systemctl status pproxy-mihomo.service --no-pager
systemctl status nginx.service --no-pager
```

PProxy 尚未迁移到 systemd 时：

```bash
cd /home/ubuntu/pproxy
bash proxy.sh status
```

## 日志

```bash
journalctl -u cliproxy-backend.service -f
journalctl -u cliproxy-backend.service -n 200 --no-pager
journalctl -u pproxy-mihomo.service -f
tail -f /home/ubuntu/pproxy/proxy-data/mihomo.log
```

## 端口

```bash
ss -ltnp | grep -E ':(7890|8317|5173|1455|9090)\b'
```

推荐状态：

```text
127.0.0.1:8317  CLIProxyAPI
127.0.0.1:5173  管理前端
127.0.0.1:7890  Mihomo 代理
127.0.0.1:9090  Mihomo 控制端
```

## 后端更新

```bash
cd /home/ubuntu/CLIProxyAPI
cp -a config.yaml "config.yaml.bak-$(date +%Y%m%d-%H%M%S)"
git pull --ff-only
go build -o cli-proxy-api.new ./cmd/server
mv cli-proxy-api.new cli-proxy-api
sudo systemctl restart cliproxy-backend.service
```

更新后必须执行一次真实 `/v1/responses` 请求；仅 `/v1/models` 返回成功不能证明上游推理链路正常。

## 账号池

认证文件目录：

```text
/home/ubuntu/.cli-proxy-api
```

通过管理页面添加 OAuth 账号后，确认账号状态为 active。配置：

```yaml
routing:
  strategy: "round-robin"
```

## 代理排障

```bash
curl -x http://127.0.0.1:7890 --connect-timeout 10 -I https://chatgpt.com/
systemctl show cliproxy-backend.service -p EnvironmentFiles -p Environment
journalctl -u cliproxy-backend.service -n 100 --no-pager
```

如果 shell 中 `curl` 能通过代理，但 CLIProxyAPI 仍然直连超时，检查 `/home/ubuntu/CLIProxyAPI/config.yaml` 是否有：

```yaml
proxy-url: "http://127.0.0.1:7890"
```

这是 CLIProxyAPI Codex uTLS 推理链路需要的显式配置。

## SSH 隧道

本地使用仓库提供的示例：

```bash
cp scripts/ssh-tunnel.example.sh scripts/ssh-tunnel.local.sh
chmod 700 scripts/ssh-tunnel.local.sh
```

将真实 IP 和私钥只写入未跟踪的 `.local.sh`，不要提交。关闭时精确匹配 SSH 主机别名：

```bash
pgrep -af 'ssh.*cliproxy-server'
pkill -f 'ssh.*cliproxy-server'
```
