import Foundation

/// 一个 API 端点：服务地址与凭据。演示数据也作为一个端点出现
public struct Endpoint: Codable, Hashable, Sendable, Identifiable {
  public enum Kind: String, Codable, Sendable {
    case demo
    case connected
  }

  public var id: String
  public var name: String?
  public var kind: Kind
  public var service: ServiceKind
  public var server: String
  /// Google Reader 换取令牌用的用户名；Miniflux 为服务返回的用户名
  public var username: String
  /// 是否把凭据保存在钥匙串里；否则只保存在内存，App 退出后移除
  public var remember: Bool
  public var token: String?
  /// Miniflux 配置的公开地址，用于把其中的 /proxy/ 图片映射到当前连接的服务
  public var mediaOrigin: String?

  public init(
    id: String,
    name: String? = nil,
    kind: Kind = .connected,
    service: ServiceKind,
    server: String,
    username: String = "",
    remember: Bool = true,
    token: String? = nil,
    mediaOrigin: String? = nil
  ) {
    self.id = id
    self.name = name
    self.kind = kind
    self.service = service
    self.server = server
    self.username = username
    self.remember = remember
    self.token = token
    self.mediaOrigin = mediaOrigin
  }

  public static let demoID = "demo"

  public static let demo = Endpoint(
    id: demoID,
    kind: .demo,
    service: .miniflux,
    server: DemoContent.server,
    username: "demo",
    remember: true
  )

  public var isDemo: Bool { kind == .demo }

  /// 服务地址去掉协议，保留子路径：同一主机上的多个服务也能区分
  public var host: String {
    guard let url = WebURL(server) else { return server }
    var path = url.path
    while path.hasSuffix("/") { path.removeLast() }
    return url.host + (url.port.map { ":\($0)" } ?? "") + path
  }

  /// 主名称：自定义名称，没有时用地址
  public var label: String {
    if isDemo { return "演示数据" }
    if let name, !name.isEmpty { return name }
    return host
  }

  /// 第二行：服务类型，有自定义名称时再加上地址
  public var detail: String {
    if isDemo { return "本地示例数据" }
    if let name, !name.isEmpty { return "\(service.label) · \(host)" }
    return service.label
  }

  /// 名称的第一个字，作为端点的标记
  public var monogram: String {
    label.first.map { String($0).uppercased() } ?? "?"
  }
}

extension ServiceKind {
  public var label: String {
    switch self {
    case .miniflux: "Miniflux"
    case .greader: "Google Reader"
    }
  }
}
