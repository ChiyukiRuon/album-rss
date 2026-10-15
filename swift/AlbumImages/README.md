# swift/AlbumImages

图片管线（Nuke）：每个端点一条管线和独立的磁盘缓存目录，缓存只保存原始数据；卡片与查看器按显示尺寸解码缩略图。另含封面尺寸测量（先测量再入列）、演示插画的本地绘制与保存到相册。由 [`swift/Package.swift`](../Package.swift) 构建。
