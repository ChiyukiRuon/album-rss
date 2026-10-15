# 本地 Miniflux 连接验证

日期：2026-10-15。所有 Miniflux API 请求都访问 `http://localhost:8880`，没有访问在线 Miniflux 实例。测试 RSS 的获取由本地 Miniflux 执行。唯一的对外请求是图片样例中指向第三方图片站点的直接请求。

## 结论

本地 Miniflux 原生 API 的认证、数据读取、跨域预检和状态回写通过，可以作为纯前端客户端的首个接入目标。已在真实无头浏览器中完成端到端验证：图片能通过 `img` 显示，但无法用 JS 读取，因此 Web 端可以做展示与打开原图，不能承诺可靠的手动下载或离线缓存。当前 Google Reader API 不具备跨域浏览器直连所需的响应。

## 已验证项目

以下结果由 `python scripts/check-local-cors.py --allow-write --markdown` 直接生成，不再手工誊抄。

| 项目 | 结果 |
| --- | --- |
| 健康检查 | 通过（200，body 为 OK，且不带 CORS 头） |
| Basic 认证 | 通过（Basic 认证 /v1/me 返回 200） |
| API Key 认证 | 通过（创建临时 Key 返回 201；X-Auth-Token 请求 /v1/me 返回 200；删除临时 Key 返回 204；已删除的 Key 请求返回 401） |
| 原生 API GET 预检 | 通过（OPTIONS 返回 200，允许 X-Auth-Token、Authorization） |
| 原生 API PUT 预检 | 通过（OPTIONS 返回 200，允许 PUT、X-Auth-Token、Content-Type，未发送 PUT） |
| Google Reader 预检 | 已确认跨域不可用（OPTIONS 返回 405，且无 CORS 允许头） |
| Google Reader 无效 token 请求 | 已确认跨域不可用（返回 401，无 CORS 允许头，未验证有效凭据） |
| 状态回写（--allow-write） | 通过（文章 1 已读状态翻转并恢复到原值，starred 未变；changed_at 已前移） |

跨域测试 Origin 为 `http://localhost:5173`。

### 两条预检结论的限定条件

预检本身**只证明 CORS 策略，不证明路由存在**。实测 `OPTIONS /v1/definitely-not-a-real-route` 同样返回 200 和完整 CORS 头，因为中间件在路由匹配之前就短路了。因此上表另有一条 `GET /v1/entries` 返回 200 的检查来证明写目标路径确实存在。此外预检状态码随版本变化：2.2.16 返回 200，上游 `main` 已改为 204，而 Compose 使用的是 `miniflux/miniflux:latest`。

"CORS 头来自 Miniflux 的 `/v1` 路由"这一点由健康检查一行的"不带 CORS 头"证实：`/healthcheck` 注册在 `/v1` 之外。也核对了 Nginx 入口配置（`nginx/conf.d/default.conf`），它把请求转发给 Miniflux（另外注入代理认证头），**没有添加任何 CORS 头**。所以 Google Reader 与媒体路径上缺失 CORS 是服务端真实属性，不是网关假象。

## 浏览器实测结果

无头 Edge（`msedge.exe`，标准旗标集，无需降低隔离级别）在约 2 秒内完成，页面通过 POST 回传结果：

| 项目 | 结果 |
| --- | --- |
| 页面 Origin | `http://localhost:5173` |
| 浏览器内认证方式 | API Key |
| 原生 API 认证 | 通过 |
| 读取订阅与文章 | 6 个订阅、113 篇文章 |
| 提取到的图片候选 | 153 |
| 抽样图片 `img` 显示 | 3/3 成功，已解码为真实尺寸（3899×5464、2560×1440、1500×2202） |
| 抽样图片 JS fetch 读取 | 3/3 失败（无可读 CORS 响应） |
| Google Reader 请求 | fetch 以 `TypeError` 被拒（CORS 拦截） |

"能显示但不能读取"这一组结果正是 Web 端能力分界的直接证据：`img` 展示不受 CORS 限制，而 JS 下载、canvas 处理和可靠离线缓存受限制。注意浏览器在 CORS 拦截下**看不到** 405/401 状态码，只能观测到请求被拒，脚本据此报告"被拦截"而不是伪造状态码。

早期记录称无头浏览器遇到权限及 GPU 子进程启动问题、未取得有效页面结果。改造后在同一环境下可稳定复现上表结果（连续多次运行一致），因此原归因不再成立。本次改动的相关部分是：同时绑定 `127.0.0.1` 与 `::1`（Win11 上 `localhost` 常先解析到 `::1`，仅绑 IPv4 时表现为页面空白）、改用页面 POST 回传而不依赖 `--dump-dom` 与 `--virtual-time-budget`（虚拟时间下 `setTimeout` 几乎立即到期，会把正常加载的图片误报为失败），以及超时后结束整个进程树并清理 profile 目录。未逐一隔离验证其中哪一项是主因。

## 测试数据

初始实例没有订阅和文章，因此添加了用户提供的六个测试订阅。

| 订阅 | 文章数 |
| --- | --- |
| Twitter / yokaikasa | 14 |
| Twitter / __Nailis__ | 14 |
| Pixiv / 77632588 | 30 |
| Pixiv / 65407506 | 30 |
| Bilibili / 436197902 | 13 |
| Bilibili / 2119892830 | 12 |

核对时共有 113 篇文章、112 篇含 img 标签、167 个 img 标签、16 篇多图文章；113 篇**全部为未读、已读为 0**（这也是回写测试选择"从未读改为已读再改回"方向的原因）。img 数量不是去重或过滤后的最终图库数量。六个订阅的 parsing_error_count 都是 0。

两次 Twitter 创建请求经过 Nginx 返回了 504，但再次查询确认订阅已经创建且文章抓取成功。504 不能直接当成创建失败而重复提交；应先查询确认。

## 图片访问与部署地址

- Bilibili 样例中的图片代理 URL 指向 Compose 的 BASE_URL（在线域名）。测试只保留路径及查询参数，将该服务的 origin 替换为本地入口，没有访问在线 Miniflux。改写限定在主机名相同**且**路径以 `/proxy/` 开头时进行：真实的媒体代理路由是 `/proxy/{digest}/{encoded}`，同主机的其他路径属于别的服务，不做改写；这类 URL 会被跳过并在输出中标记，而不是发出去。
- 两个 Bilibili 订阅各抽样一张图片，本地代理返回 206、image/jpeg，可读取前 64 KiB，并已在浏览器中完整解码显示。这些图片响应没有 Access-Control-Allow-Origin，因此浏览器可以显示但不能用 JS 读取 —— 原生 API 的 CORS 支持不会自动覆盖媒体代理。
- Pixiv 与 Twitter 各订阅抽样一张图片，源站分别为 pixiv.chiyukiruon.com 和 pbs.twimg.com。当前执行环境的结果是：Pixiv 源站返回 **403**，`pbs.twimg.com` 请求**超时**（`TimeoutError`）。这属于外部原因（源站防盗链、网络可达性），与早期记录的 `PermissionError / WinError 10013` 不同，原因已变化但结论方向一致：同样不能据此认定源站或图片不可用。

开发客户端可以提供明确的"服务公开地址 → 当前连接地址"映射，仅改写经过识别的同一 Miniflux 服务代理地址，不替换任意第三方图片 URL。另一种部署选择是调整用户已有环境的 BASE_URL，但本次未修改 Docker 或 Nginx 配置。

纯前端仍可保留图片展示与打开原图；图片 JS 下载和可靠离线缓存按实际可读性提供。如果以后需要完整支持本地媒体下载，可选择与 Miniflux 同源部署静态文件，或在用户已有入口配置媒体 CORS。它们都不要求开发客户端自己的后端。

## 边界与未验证项

以下仍未验证，不应据本文档推断为可用：

- iOS 尚未进行模拟器或真机测试，其协议认证也未验证；iOS 真机需要可达的局域网地址或域名。
- HTTPS 页面连接 HTTP 本机入口的混合内容行为未实测。
- 有效 Google Reader 凭据未验证（仅测了无效 token 的拒绝行为）。
- 端口绑定失败（`bind_failed`）分支在 Windows 上难以触发：`SO_REUSEADDR` 允许两个套接字绑定同一端口，构造占用端口后脚本仍能正常完成，因此该分支未被实际验证。

## 重复验证

- `python scripts/check-local-cors.py`：健康检查、Basic 与 API Key 认证、原生 API 与 Google Reader 的 CORS 预检。**默认不修改任何文章状态**，唯二的写请求是临时 API Key 的创建与删除；输出中的 `read_only_guarantee.state_changing_requests` 会列出本次实际发出的全部写请求供核对。退出码 0 通过、1 失败。
- `python scripts/check-local-cors.py --allow-write --markdown`：额外执行状态回写往返 —— 选中最旧的一篇未读文章，标记为已读、回读校验、改回未读、再次回读校验，并断言 starred 未变。**这会修改真实数据**：只涉及一篇文章，且会前移该文章的 `changed_at`，依赖 `changed_after` 的增量同步可能重新拉取这一篇。正常路径与异常路径都会尝试恢复；恢复失败时会打印文章 ID 与可粘贴的手动修复命令，并以退出码 **3** 结束。`--markdown` 额外输出可直接粘贴到本文档表格的行。
- `python scripts/check-local-miniflux.py`：只读获取本地版本、订阅、文章和各订阅的图片 HTTP 样例，不输出凭据。
- `python scripts/seed-local-miniflux.py`：添加用户给定的测试订阅，已存在则跳过；此脚本会修改订阅列表。
- `python scripts/check-local-browser.py`：创建临时 API Key，启动本机 5173 测试页面与无头 Edge，页面把结果 POST 回本地服务器；结束后删除临时 Key。测试页面与凭据只在内存中，浏览器 profile 使用项目内临时目录并在结束后清理。失败时输出 `stage` 与可操作提示，而不是笼统的 incomplete。

脚本从现有 Compose 文件读取测试账号，适用于当前环境。若改动入口地址可用 `--base`（CORS 脚本）与 `--port`（浏览器脚本）覆盖，但文档记录的 Origin 与结果随之失效。

## 依赖与来源

项目为 Python 3 标准库，无第三方依赖。脚本读取 `D:\CodeProject\Develop Environment\miniflux\docker-compose.yaml` 获取账号与 BASE_URL。

表中行为依据 Miniflux 2.2.16 源码，做法与 `design.md` 的引用惯例一致：

- [`internal/api/api.go`](https://github.com/miniflux/v2/blob/2.2.16/internal/api/api.go)：`PUT /v1/entries`（第 68 行）写状态，`PUT /v1/entries/{entryID}`（第 70 行）只改标题与正文。
- [`internal/model/entry.go`](https://github.com/miniflux/v2/blob/2.2.16/internal/model/entry.go)：`EntriesStatusUpdateRequest{entry_ids, status}`（第 73 行）与 `EntryUpdateRequest{title, content}`（第 79 行）；状态取值为 `unread` / `read` / `removed`。
- [`internal/storage/entry.go`](https://github.com/miniflux/v2/blob/2.2.16/internal/storage/entry.go)：`SetEntriesStatus`（第 490 行）写入 `changed_at=now()`，并以 `status!=$4` 跳过已处于目标状态的行 —— 所以同值写入匹配 0 行却仍返回 204，校验必须回读而不能信任状态码；该守卫也使 `removed` 成为单向门，测试中不使用。
- [`internal/ui/ui.go`](https://github.com/miniflux/v2/blob/2.2.16/internal/ui/ui.go)（第 107 行）：媒体代理路由为 `/proxy/{digest}/{encoded}`。
- [`internal/http/server/httpd.go`](https://github.com/miniflux/v2/blob/2.2.16/internal/http/server/httpd.go)（第 251 行）：`/healthcheck` 注册在 `/v1` 之外，因此不带 CORS 头。

测试未修改文章收藏状态，没有重建容器、升级镜像或改动既有部署文件。默认运行不修改阅读状态；`--allow-write` 会按上文所述改动并恢复一篇文章的已读状态。
