# swift

Album RSS 的 Swift Package（`AlbumRSSKit`），iOS 应用只链接这里的产物。一个清单，三个库：

| 模块             | 内容                                                                                                            |
| ---------------- | --------------------------------------------------------------------------------------------------------------- |
| `AlbumCore`      | 模型、按浏览器规则解析地址、正文图片提取（SwiftSoup）、瀑布流计算、本地数据库（GRDB）、页面状态与同步、演示数据 |
| `AlbumProviders` | Miniflux 原生 API 与 Google Reader 兼容协议的适配器、请求队列与重试                                             |
| `AlbumImages`    | 按端点隔离的图片管线（Nuke）、尺寸测量、演示插画、保存到相册                                                    |

行为与 Web 端的 `packages/core-ts`、`packages/providers-ts` 与 `apps/web/src/prototype/store.ts` 一一对应；图片提取与 Web 端共用 `contracts/fixtures/media` 中的样例，两端都要通过。依赖版本固定在 `Package.swift`，升级时一并更新 `Package.resolved`。

```sh
swift build --package-path swift
swift test --package-path swift
```

测试可在 macOS 上直接运行，网络请求全部使用假实现，不访问外部服务。
