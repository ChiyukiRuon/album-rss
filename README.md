# Album RSS

以图片浏览为主的 RSS 客户端，把订阅文章中的图片整理成图集和瀑布流。

Web 端与原生 iOS 应用都直接连接你的 Miniflux 或 Google Reader 兼容服务，读取订阅、浏览图片，并将已读和收藏状态同步回服务端。两端都不需要部署额外的业务后端。

Web 端是纯静态前端；iOS 应用（iOS 18 及以上，适配 iOS 26 的液态玻璃）另外提供本地缓存、离线浏览、离线标记与保存到相册，见下文“iOS 应用”。

## 功能

- **图集与图片流**：按文章浏览图集，或展开为图片流；支持瀑布流布局和三档卡片大小。
- **订阅与筛选**：查看全部或未读文章，按订阅源、分类浏览，文章随浏览按需分页加载。
- **图片查看器**：翻阅图集、连续进入相邻图集、查看文章信息，以及打开原图或原文。
- **已读与收藏**：同步到当前 RSS 服务；可设置图片显示成功后、下载成功后自动标为已读。
- **视频播放**：Web 和 iOS 均支持正文中的 `video` / `source` 及 `video/*` 附件，与图片一起展示和翻页；使用封面图或播放占位，播放结束后可选择“循环播放”（单个视频循环）、“播完暂停”（默认）或“播完切换”（跳到下一组第一项，无下一组时停止）；默认手动播放；设置中可开启“打开视频时自动播放”，开启后显示“使用数据流量时自动播放”。关闭流量自动播放时，iOS 在蜂窝网络或个人热点下保留手动播放，Web 仅在能确认 Wi-Fi / 有线网络时自动播放；浏览器也可能拦截自动播放。格式支持取决于浏览器或系统，不解析 iframe 嵌入播放器；播放失败时可打开媒体链接或原文。保存图集仅保存其中的图片。
- **图片保存**：支持保存单张图片或图集内的图片，下载能力取决于图源的跨域策略。
- **多个 API 端点**：添加、编辑、切换和删除连接，每个端点独立设置是否保存凭据。
- **外观与演示**：适配桌面和移动端，支持浅色、深色及跟随系统主题；无需连接服务即可进入本地演示。

## 快速开始

准备 Node.js（版本满足 `^22.13.0 || >=24`）和 pnpm 9.9.0，在仓库根目录运行：

```sh
pnpm install
pnpm dev
```

打开 <http://localhost:5173>，添加 RSS 服务连接，或选择演示入口体验界面。演示使用本地生成的数据，不会连接 RSS 服务器。

## 连接 RSS 服务

| 服务类型           | 服务地址示例                              | 认证方式                                  |
| ------------------ | ----------------------------------------- | ----------------------------------------- |
| Miniflux           | `https://rss.example.com`                 | 在 Miniflux 的“设置 → API 密钥”中创建密钥 |
| Google Reader 兼容 | `https://rss.example.com/api/greader.php` | 使用兼容接口的用户名和密码换取访问令牌    |

Google Reader 兼容服务的地址需要包含实际 API 路径，具体以所用服务的配置为准。兼容程度取决于服务端实现。

连接后，可以通过端点切换器或设置页管理多个连接。每次浏览当前选中的端点，各端点的数据分别加载。

### 凭据与本地设置

默认只在内存中保留连接凭据，刷新页面后该端点会被移除。勾选“在此浏览器保存凭据”后，端点及其 API 密钥或访问令牌会写入浏览器的 `localStorage`；删除端点时会清除对应记录。Google Reader 登录密码只用于换取令牌，不会保存。

主题、浏览偏好等设置只保存在当前浏览器中；真实服务的已读和收藏状态通过 API 同步。

### 连接与图片限制

- **跨域访问**：浏览器直接请求 RSS API，服务或反向代理需要允许应用来源的 CORS 请求，包括认证请求头和写入操作。
- **协议与证书**：HTTPS 页面连接 HTTP 服务可能被浏览器拦截；服务地址也需要具有浏览器信任的证书。
- **图片加载与下载**：能显示的图片不一定允许脚本读取。图源禁止跨域读取时，需要打开原图后右键或长按保存；当前不提供独立的图片代理后端。
- **Miniflux 图片代理**：若通过本机地址连接，而文章中的 `/proxy/` 图片使用另一公开地址，可在连接表单的“服务公开地址”中填写该地址，将图片请求映射到当前服务。

## iOS 应用

工程位于 `apps/ios/AlbumRSS.xcodeproj`，界面使用 SwiftUI，查看器的翻页与缩放使用 UIKit；模型、解析、同步与服务适配放在 `swift/` 下的 Swift Package 中，与 Web 端共用同一组图片提取样例（`contracts/fixtures/media`）。

需要 Xcode 26 或更新版本（当前在 Xcode 27 上开发）。用 Xcode 打开工程，选择 `AlbumRSS` scheme 和任意 iOS 18 及以上的模拟器运行即可；真机运行需要在 Xcode 中为目标选择签名团队。首次打开时 Xcode 会解析固定版本的依赖（GRDB、Nuke、SwiftSoup）。

与 Web 端的不同：

- **凭据**：默认保存在本机钥匙串（仅此设备）；也可以选择只保存在内存中，App 退出后移除。
- **本地数据**：每个端点的订阅、最近几页文章和待发送的已读、收藏改动保存在本机数据库，启动时先显示本地内容再同步；离线时的标记会在网络恢复后写回服务。
- **图片**：浏览过的原图缓存在本机（容量上限可在设置中调整），离线时也能查看；下载按钮会把图片保存到相册，不受图源跨域策略限制。
- **网络**：允许连接 HTTP 和局域网地址；连接局域网服务时，系统会请求“本地网络”权限。

更多说明见 [apps/ios/README.md](apps/ios/README.md)。

## 开发与验证

项目使用 pnpm workspace，Web 端基于 React、TypeScript 和 Vite，测试使用 Vitest。

在仓库根目录执行：

| 命令                                   | 用途                           |
| -------------------------------------- | ------------------------------ |
| `pnpm dev`                             | 启动 Web 开发服务器            |
| `pnpm build`                           | 构建工作区中提供构建脚本的项目 |
| `pnpm test`                            | 运行各工作区的测试             |
| `pnpm typecheck`                       | 检查各工作区的 TypeScript 类型 |
| `pnpm lint`                            | 运行 ESLint 检查               |
| `pnpm format:check`                    | 检查代码和文档格式             |
| `pnpm format`                          | 自动格式化代码和文档           |
| `pnpm --filter @album-rss/web preview` | 本地预览已构建的 Web 应用      |

Swift 与 iOS 部分：

| 命令                                                                                                                              | 用途                               |
| --------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------- |
| `swift test --package-path swift`                                                                                                 | 运行 Swift 模块的单元测试          |
| `xcodebuild -project apps/ios/AlbumRSS.xcodeproj -scheme AlbumRSS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` | 构建 iOS 应用                      |
| `xcodebuild -project apps/ios/AlbumRSS.xcodeproj -scheme AlbumRSS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test`  | 运行界面测试（演示数据与本地服务） |
| `python3 scripts/stub-rss-server.py`                                                                                              | 启动本机的模拟 RSS 服务            |

`scripts/` 中还提供本地 Miniflux 连通性和浏览器验证工具。这些脚本可能依赖特定机器、服务或路径，运行前请先检查配置。`stub-rss-server.py` 只使用 Python 标准库，在 `127.0.0.1:8787` 提供 Miniflux 与 Google Reader 兼容接口和生成的图片，供两端联调与 iOS 界面测试使用，不连接外部网络。

## 构建与部署

```sh
pnpm build
pnpm --filter @album-rss/web preview
```

Web 构建产物位于 `apps/web/dist/`，可部署到静态托管服务。应用使用浏览器历史路由，托管服务需要将应用路由（如 `/feeds`、`/settings`）回退到 `index.html`，以支持直接访问和刷新。

部署后，RSS 服务仍需允许部署域名的跨域请求，且访问者的浏览器必须能够直接访问 RSS 服务和图片来源。

## 项目结构

```text
apps/
  web/                   React + Vite Web 应用
  ios/                   iOS 应用（SwiftUI，Xcode 工程与界面测试）
packages/
  core-ts/               共享文章、订阅和图片模型
  providers-ts/          Miniflux 与 Google Reader 兼容适配器
contracts/               跨平台样例：图片提取的 golden fixtures
swift/                   Swift Package
  AlbumCore/             模型、正文解析、瀑布流计算、本地数据库与同步
  AlbumProviders/        Miniflux 与 Google Reader 兼容适配器
  AlbumImages/           图片管线、尺寸测量、演示插画与保存到相册
scripts/                 本地连接验证工具与模拟 RSS 服务
```

## 许可证

[MIT](LICENSE)
