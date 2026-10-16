# AGENTS.md — xadmin-web（nginx 静态托管与反代镜像）

> 继承工作区根 `../AGENTS.md`（环境、测试门禁、安全禁区、验证口径都在那里）；
> 本文件只写**本仓库特有的约定**。规则优先级：用户当前指令 > 本文件 > 工作区根。
>
> 本仓库产物只有一个：**web 镜像**（前端静态资源 + nginx 反代）。它是生产流量的唯一入口，
> 配置改错的代价是线上白屏 / 502 / 安全头丢失，改动必须过「语法 + 实机响应」双验证。

## 一、仓库地图

| 路径 | 内容 |
|------|------|
| `Dockerfile` | 多阶段：`FROM nineaiyu/xadmin-client:${VERSION}` 取构建产物（`/usr/share/nginx/html`）→ 落 nginx:alpine 的 `/opt/xadmin-client` |
| `default.conf` | SPA 文档层 server（内网 51980）：安全头 / **CSP 强制头** / 静态缓存策略 / `/api` `/ws` `/media` 转发 / `/web/health/` |
| `xadmin-api-conf` | 反代片段（被 `default.conf` 的 location `include`）：`/api` `/ws` 等转发 `server:8896` |
| `http_server.conf` | 对外 80 端口 server → 转发 `localhost:51980`（`init.sh` 按环境变量改写） |
| `nginx.conf` | 主配置：`stream`（四层 TCP 转发，供安装器 LB 形态）+ `http` 基础项 + 日志格式 |
| `init.sh` | 容器入口脚本（装到 `/docker-entrypoint.d/40-init-config.sh`）：`HTTP_PORT` / `SERVER_NAME` / `CLIENT_MAX_BODY_SIZE` / `USE_LB` / `GZIP` / HTTPS 证书等环境变量改写配置 |
| `.github/` | `build-image.yml`（tag 触发构建推送镜像）+ `release-drafter.yml` + `release-config.yml`（发布说明模板） |

## 二、改动红线

1. **CSP 三处同源**：`default.conf` 的 CSP 策略串必须与 `xadmin-server/server/settings/base.py`
   的 `_CSP_DIRECTIVES`、`xadmin-client/scripts/csp-page-server.mjs` 的 `CSP` 完全一致；
   漂移由服务端单测 `tests/unit/common/test_csp.py::TestCSPPolicySync` 拦截（需要三仓齐全才生效，
   单仓检出会自动 skip——改策略时**必须三仓一起改**）。
2. **安全头只在 server 级声明**：nginx `add_header` 的继承规则是「子级一旦声明即整体不继承」——
   新增响应头一律加在 `default.conf` 的 server 块顶部，不得散落到 location
   （例外仅限有意独立声明的缓存头，且注释已说明可接受）。
3. **后端地址必须运行期解析**：`xadmin-api-conf` 用 `resolver 127.0.0.11 valid=10s` + 变量 `proxy_pass`，
   **勿改回**静态 `proxy_pass http://server:8896;`——静态写法在 nginx 配置加载期解析域名，
   容器启动顺序（web 早于 server）会 `[emerg] host not found` 且 server 重建换 IP 后必须手工 restart。
4. **`/media/` 走应用鉴权**：媒体文件一律转发后端（Cookie JWT 校验后返回，或按
   `MEDIA_X_ACCEL_PREFIX` 走 `X-Accel-Redirect` 内转到 `/_protected_media/`），
   不要恢复匿名直链 `alias`。
5. **SPA 缓存策略保持现状**：`/static/`（带内容哈希）一年 `immutable` 长缓存；
   `index.html` / `platform-config.json` 禁缓存（`expires -1`，**不要换成 add_header**——
   会让 index.html 丢掉 server 级 CSP）；新增 location 时先想清楚这两条。
6. **镜像 tag 由构建参数 `VERSION` 决定**：基础镜像 `xadmin-client:${VERSION}` 与自身 tag 必须同版本；
   不要在配置文件里写死版本号，发布说明文案只改 `.github/release-config.yml`。
7. **`init.sh` 的环境变量是安装器契约**：`HTTP_PORT` / `USE_LB` / `SSL_CERTIFICATE` 等被
   `xadmin-installer` 依赖，改名 / 改语义要两侧同步（`xadmin-installer/AGENTS.md` §二）。

## 三、验证（改配置后必做）

```bash
# ① 镜像构建（tag 与 xadmin-client 同版本；工作流内置「等待 nineaiyu/xadmin-client:${VERSION}
#    出现」的有界轮询，因此 client 镜像未构建完时不会以 not found 失败）
VERSION=dev docker buildx build -t nineaiyu/xadmin-web:dev . --load

# ② 起容器实测（需同网络里有名为 server 的后端容器，否则 /api 转发会 502——可先只验静态面）
docker run --rm -p 8899:80 nineaiyu/xadmin-web:dev
curl -sI http://127.0.0.1:8899/ | grep -Ei "content-security-policy|x-content-type|referrer"
curl -s  http://127.0.0.1:8899/web/health/        # {"status": "ok"}

# ③ CSP 页面护栏回归（在 xadmin-client 仓跑：构建产物 + 强制头 + 真实浏览器零违规）
cd ../xadmin-client && pnpm test:e2e:csp
```

- 改 `default.conf` / `xadmin-api-conf` 后必须复验：响应头（`curl -I`）+ 登录页可打开（`/api` 转发通）；
- CSP 策略变更按「先在隔离 harness 验证（`test:e2e:csp`）→ 再切强制」口径走，
  历史执行记录见 `xadmin-server/docs/ops/release-checklist.md` §1；
- 本仓库无单元测试：**验证 = 镜像构建 + 容器实测 + 跨仓 CSP 门禁**，三样都跑过才算完成。
