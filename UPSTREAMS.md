# Upstream components

本仓库是部署编排层，不复制或修改第三方项目源码。上游通过 Git submodule 固定在本次部署使用的源码版本；升级时在 submodule 中单独评估并更新指针。

| 组件 | 上游仓库 | 用途 |
| --- | --- | --- |
| CLIProxyAPI | https://github.com/router-for-me/CLIProxyAPI | OpenAI-compatible API、OAuth 凭证加载、账号池和路由 |
| PProxy | https://github.com/w568w/pproxy | Mihomo 安装、订阅配置、代理启动和 WebUI |
| Management Center | https://github.com/router-for-me/Cli-Proxy-API-Management-Center | CLIProxyAPI 管理界面 |

初始化：

```bash
git submodule update --init --recursive
```

查看上游版本：

```bash
git submodule status
```

升级某个上游前先阅读其 changelog、配置变更和许可证，再执行：

```bash
git -C vendor/CLIProxyAPI fetch --tags
git -C vendor/CLIProxyAPI checkout <经过验证的版本或提交>
git add vendor/CLIProxyAPI
git commit -m "chore: update CLIProxyAPI upstream"
```

不要把 OAuth 认证目录、代理订阅、Mihomo 运行配置或编译产物放进 submodule 的提交或本仓库。
