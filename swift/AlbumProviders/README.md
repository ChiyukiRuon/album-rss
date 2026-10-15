# swift/AlbumProviders

服务适配器：Miniflux 原生 API（API 密钥）与 Google Reader 兼容协议（ClientLogin 令牌）。由 [`swift/Package.swift`](../Package.swift) 构建。

请求不带 cookie、不跟随重定向、30 秒超时；同一端点的请求排队（最多同时 2 个、间隔 150 毫秒），遇到 429、502、503、504 时按 Retry-After 暂停整个队列后重试。行为与 `packages/providers-ts` 相同，测试同样覆盖分页游标、计数、批量写入与错误提示。
