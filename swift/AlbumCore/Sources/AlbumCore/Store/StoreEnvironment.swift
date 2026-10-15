import Foundation

/// 访问令牌的保存位置（App 里是钥匙串，测试里是内存）
public protocol CredentialStore: Sendable {
  func token(for endpointID: String) -> String?
  func setToken(_ token: String?, for endpointID: String)
  /// 删除所有已保存的令牌（首次安装时清理上一次安装遗留的钥匙串项）
  func removeAll()
}

/// 小型设置的保存位置（App 里是 UserDefaults）
public protocol KeyValueStore: Sendable {
  func data(forKey key: String) -> Data?
  func setData(_ data: Data?, forKey key: String)
}

/// 把图片存到设备（App 里是相册）。progress 每存完一张调用一次
public protocol ImageSaver: Sendable {
  func save(_ images: [ImageAsset], endpoint: Endpoint, progress: @escaping @Sendable (Int) -> Void) async throws
}

public final class MemoryCredentialStore: CredentialStore, @unchecked Sendable {
  private let lock = NSLock()
  private var tokens: [String: String] = [:]

  public init() {}

  public func token(for endpointID: String) -> String? {
    lock.withLock { tokens[endpointID] }
  }

  public func setToken(_ token: String?, for endpointID: String) {
    lock.withLock { tokens[endpointID] = token }
  }

  public func removeAll() {
    lock.withLock { tokens = [:] }
  }
}

public final class MemoryKeyValueStore: KeyValueStore, @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String: Data] = [:]

  public init() {}

  public func data(forKey key: String) -> Data? {
    lock.withLock { values[key] }
  }

  public func setData(_ data: Data?, forKey key: String) {
    lock.withLock { values[key] = data }
  }
}

/// UserDefaults 是线程安全的，这里只做一层包装
public struct UserDefaultsStore: KeyValueStore, @unchecked Sendable {
  private let defaults: UserDefaults

  public init(_ defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  public func data(forKey key: String) -> Data? {
    defaults.data(forKey: key)
  }

  public func setData(_ data: Data?, forKey key: String) {
    if let data { defaults.set(data, forKey: key) } else { defaults.removeObject(forKey: key) }
  }
}

/// 一次连接的输入：添加或编辑端点
public struct ConnectInput: Sendable {
  public var id: String?
  public var name: String?
  /// Google Reader：沿用已保存的令牌（地址和用户名不变、没填新密码时）
  public var token: String?
  public var service: ServiceKind
  public var server: String
  public var username: String
  public var remember: Bool
  public var apiKey: String
  public var password: String
  public var mediaOrigin: String?

  public init(
    id: String? = nil,
    name: String? = nil,
    token: String? = nil,
    service: ServiceKind,
    server: String,
    username: String = "",
    remember: Bool = true,
    apiKey: String = "",
    password: String = "",
    mediaOrigin: String? = nil
  ) {
    self.id = id
    self.name = name
    self.token = token
    self.service = service
    self.server = server
    self.username = username
    self.remember = remember
    self.apiKey = apiKey
    self.password = password
    self.mediaOrigin = mediaOrigin
  }
}

/// Store 依赖的外部能力。App 与测试分别组装
public struct StoreEnvironment: Sendable {
  /// 为端点创建适配器；同一端点的请求应共用一个队列
  public var makeProvider: @Sendable (Endpoint) throws -> any RSSProvider
  /// Google Reader：用户名和密码换取访问令牌
  public var login: @Sendable (_ server: String, _ username: String, _ password: String) async throws -> String
  public var credentials: any CredentialStore
  public var defaults: any KeyValueStore
  public var database: AlbumDatabase?
  public var imageSaver: any ImageSaver
  public var now: @Sendable () -> Date
  public var sleep: @Sendable (Duration) async throws -> Void
  /// 端点被删除：App 借此清理它的图片缓存
  public var didRemoveEndpoint: @Sendable (String) -> Void
  /// 演示数据的网络延迟；测试里设为零
  public var demoLatency: Duration

  public init(
    makeProvider: @escaping @Sendable (Endpoint) throws -> any RSSProvider,
    login: @escaping @Sendable (String, String, String) async throws -> String,
    credentials: any CredentialStore = MemoryCredentialStore(),
    defaults: any KeyValueStore = MemoryKeyValueStore(),
    database: AlbumDatabase? = nil,
    imageSaver: any ImageSaver,
    now: @escaping @Sendable () -> Date = { Date() },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    didRemoveEndpoint: @escaping @Sendable (String) -> Void = { _ in },
    demoLatency: Duration = .milliseconds(350)
  ) {
    self.makeProvider = makeProvider
    self.login = login
    self.credentials = credentials
    self.defaults = defaults
    self.database = database
    self.imageSaver = imageSaver
    self.now = now
    self.sleep = sleep
    self.didRemoveEndpoint = didRemoveEndpoint
    self.demoLatency = demoLatency
  }
}
