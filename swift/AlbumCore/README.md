# swift/AlbumCore

模型、正文解析、瀑布流计算、本地数据库（SQLite + GRDB）与同步。由 [`swift/Package.swift`](../Package.swift) 构建。

- `Model/`：订阅、文章、图片、端点、设置与列表进度。
- `Parsing/`：按 WHATWG 规则解析 http(s) 地址（与浏览器的 `new URL` 一致），以及正文图片与段落提取。
- `Layout/`、`Format/`：瀑布流计算与时间、地址的显示格式。
- `Storage/`：每个端点一个数据库文件：订阅、文章、列表进度、待发送改动、图片尺寸。
- `Store/`：页面状态与服务操作（`AlbumStore`），以及已读、收藏的待发送队列。
- `Demo/`：与 Web 端相同的演示数据，以演示服务（`DemoProvider`）的形式提供。
