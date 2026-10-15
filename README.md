# Album RSS

以图片浏览为主的 RSS 客户端：纯静态 Web 与原生 iOS，直接连接已有的 RSS 服务（Miniflux、Google Reader 兼容服务），没有自建后端。设计见 [docs/design.md](docs/design.md)。

## 当前状态

- `apps/web`：已接入真实 RSS API，支持登录、同步、图集浏览、已读、收藏和图片保存，也保留演示入口。连接说明与当前限制见 [docs/web-api.md](docs/web-api.md)。设计与交互约定见 [docs/ui-prototype.md](docs/ui-prototype.md)。
- `packages/core-ts`：共享文章、订阅和图片模型；`packages/providers-ts`：Miniflux 原生与 Google Reader 兼容适配器。`contracts/` 的跨端样例仍待补齐。
- `apps/ios`、`swift/`：只有说明，需要在 macOS 上初始化。
- `scripts/`：本地 Miniflux 连接验证脚本，见 [docs/local-connectivity.md](docs/local-connectivity.md)。

## 开发

需要 Node 22.13+ 或 24，以及 pnpm 9。

```sh
pnpm install
pnpm dev            # http://localhost:5173，连接 RSS 服务或进入演示
pnpm test
pnpm typecheck
pnpm lint
pnpm format:check
pnpm --filter @album-rss/web build
```
