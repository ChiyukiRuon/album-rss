# apps/ios

Album RSS 的原生 iOS 应用：SwiftUI 界面，查看器的翻页与缩放使用 UIKit。最低支持 iOS 18；在 iOS 26 及以上使用液态玻璃（系统控件自动获得，自定义的浮层按钮、提示与角标使用 `glassEffect`，iOS 18 上退回半透明材质）。

数据、解析与同步不在这里，而在仓库的 Swift Package（[`swift/`](../../swift)）中，App 只链接其中的 `AlbumCore`、`AlbumProviders` 与 `AlbumImages`。

## 运行

1. 用 Xcode 26 或更新版本打开 `AlbumRSS.xcodeproj`（当前在 Xcode 27 上开发）。首次打开时 Xcode 会解析固定版本的依赖：GRDB 7.11.1、Nuke 13.2.0、SwiftSoup 2.14.2。
2. 选择 `AlbumRSS` scheme 与任意 iOS 18 及以上的模拟器，运行即可。连接页可以添加 Miniflux 或 Google Reader 兼容服务，也可以先进入演示数据。
3. 真机运行需要在目标的 Signing & Capabilities 中选择开发团队。Bundle ID 为 `top.chiyukiruon.albumrss`。

命令行构建：

```sh
xcodebuild -project apps/ios/AlbumRSS.xcodeproj -scheme AlbumRSS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## 目录

```text
AlbumRSS.xcodeproj     工程文件（文件夹同步组：新增源文件无需修改工程）
Config/Info.plist      生成的 Info.plist 之外需要的键（允许 HTTP 连接）
AlbumRSS/
  App/                 入口与组装（AppModel）、钥匙串
  Design/              颜色、网点占位、液态玻璃修饰器、标志
  Views/               连接页、页签、瀑布流、各页面、端点表单、查看器
  Assets.xcassets      强调色
  AppIcon.icon         Icon Composer 格式的图标（亮色、深色、着色）
AlbumRSSUITests/       演示数据流程与本地服务连接的界面测试
```

## 设计与行为

- 视觉与 Web 端一致：白纸、墨、网点；唯一的彩色是品红，只用于收藏、未读计数和新内容提示。所有“还不是一张图”的状态都用网点表示。
- 瀑布流规则与 Web 端相同：先测量尺寸再放入卡片，放下后不再移动；只渲染视口附近的卡片；接近底部时读取下一页。
- 列表是快照：在查看器里看过、标记过的图集不会立刻从列表消失；下拉刷新或切换筛选后才更新。回到前台的后台同步只提示新图集数量。
- 查看器从卡片缩放打开，看完一个图集可以继续翻到下一组，关闭时缩回最后看的卡片，背后的列表会跟着滚动。下滑也能关闭。
- 已读与收藏先更新界面，再按“期望值”写回服务。离线或服务暂时不可用时保留改动并稍后重试；凭据失效时暂停写入，提示编辑端点；服务拒绝的改动会恢复原状态并提示。

## 本地数据

| 内容                             | 位置                                                   |
| -------------------------------- | ------------------------------------------------------ |
| 访问令牌                         | 钥匙串（仅此设备，首次解锁后可读）                     |
| 端点列表、设置                   | UserDefaults（不含令牌）                               |
| 订阅、文章、列表进度、待发送改动 | `Application Support/AlbumRSS/Endpoints/<端点>.sqlite` |
| 图片原始数据                     | `Caches/AlbumRSS/Images/<端点>/`                       |

删除端点会同时删除它的令牌、数据库和图片缓存。没有保存凭据的端点不写入数据库，图片缓存在下次启动时清除。

## 测试

单元测试在 Swift Package 中运行：

```sh
swift test --package-path swift
```

界面测试使用演示数据走一遍主要流程（浏览、查看器、订阅、设置、深色模式），每一步都会在结果包中留下截图：

```sh
xcodebuild -project apps/ios/AlbumRSS.xcodeproj -scheme AlbumRSS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

`ConnectionTests` 连接本机的模拟服务，覆盖 Miniflux 与 Google Reader 的连接、浏览与写回，以及凭据错误时的提示。先在另一个终端启动服务，没有运行时这些测试会跳过：

```sh
python3 scripts/stub-rss-server.py
```

模拟器可以直接访问本机的 `127.0.0.1`。手动联调时，Miniflux 填 `http://127.0.0.1:8787` 与 API 密钥 `stub-token`；Google Reader 兼容填 `http://127.0.0.1:8787/api/greader.php`，用户名 `reader`，密码 `secret`。

### 启动参数

| 参数                | 作用                                           |
| ------------------- | ---------------------------------------------- |
| `--reset`           | 启动前清空设置、端点、钥匙串、数据库与图片缓存 |
| `--demo`            | 没有端点时直接进入演示数据                     |
| `--appearance dark` | 强制深色（`light` 为浅色），用于截图           |

## 当前边界

- 只在 iOS 26 与 iOS 27 模拟器上实际运行过；iOS 18 的退回样式只经过编译检查（本机没有 iOS 18 运行时）。
- 尚未在真实的 Miniflux 或 FreshRSS 上验证，联调使用的是本机模拟服务。
- 后台刷新、离线保存整个图集、全文抓取、搜索与动图播放尚未实现。
