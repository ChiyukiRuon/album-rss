import AlbumCore
import Foundation
import Nuke
import SwiftUI

/// 每个端点一条图片管线和独立的磁盘缓存目录：不同端点的缓存互不混用，删除端点时一起清除。
/// 缓存只保存原始数据，解码后的图片放在内存缓存里。
@MainActor
public final class ImageService {
  public let latency = LatencySwitch()
  private let root: URL
  private var pipelines: [String: ImagePipeline] = [:]
  private var caches: [String: DataCache] = [:]

  /// 全部端点合计的磁盘缓存上限（字节），平均分给各端点
  public var limit: Int {
    didSet { applyLimit() }
  }

  public static var defaultRoot: URL {
    URL.cachesDirectory.appending(path: "AlbumRSS/Images", directoryHint: .isDirectory)
  }

  public init(root: URL = ImageService.defaultRoot, limit: Int) {
    self.root = root
    self.limit = limit
  }

  /// 端点的图片管线；没有端点时用一条不落盘的管线
  public func pipeline(for endpoint: Endpoint?) -> ImagePipeline {
    let key = endpoint.map(cacheKey) ?? "none"
    if let pipeline = pipelines[key] { return pipeline }
    var configuration = ImagePipeline.Configuration(dataLoader: AlbumDataLoader(latency: latency))
    configuration.imageCache = ImageCache.shared
    configuration.dataCachePolicy = .storeOriginalData
    configuration.isProgressiveDecodingEnabled = false
    if endpoint != nil, let cache = try? DataCache(path: root.appending(path: key, directoryHint: .isDirectory)) {
      caches[key] = cache
      configuration.dataCache = cache
    }
    let pipeline = ImagePipeline(configuration: configuration)
    pipelines[key] = pipeline
    applyLimit()
    return pipeline
  }

  /// 没有保存凭据的端点用单独的目录，下次启动时清掉
  private func cacheKey(_ endpoint: Endpoint) -> String {
    let safe = endpoint.id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" ? String($0) : "_" }
      .joined()
    return endpoint.isDemo || endpoint.remember ? safe : "session-\(safe)"
  }

  private func applyLimit() {
    guard !caches.isEmpty else { return }
    let share = max(32 * 1024 * 1024, limit / caches.count)
    for cache in caches.values { cache.sizeLimit = share }
  }

  /// 删除端点的图片缓存
  public func removeCache(endpointID: String) {
    for key in [endpointID, "session-\(endpointID)"] {
      pipelines.removeValue(forKey: key)?.invalidate()
      caches.removeValue(forKey: key)?.removeAll()
      try? FileManager.default.removeItem(at: root.appending(path: key, directoryHint: .isDirectory))
    }
    applyLimit()
  }

  /// 清掉不属于任何端点的缓存目录（以及上次未保存凭据的端点留下的）
  public func removeUnknownCaches(keeping ids: Set<String>) {
    guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else {
      return
    }
    let keep = ids.union([Endpoint.demoID])
    for folder in folders where !keep.contains(folder.lastPathComponent) && caches[folder.lastPathComponent] == nil {
      try? FileManager.default.removeItem(at: folder)
    }
  }

  /// 清除全部图片缓存（磁盘与内存）
  public func clearAll() async {
    ImageCache.shared.removeAll()
    for cache in caches.values { cache.removeAll() }
    let root = root
    await Task.detached {
      if let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
        for folder in folders {
          // 正在使用的目录只清空内容，DataCache 之后还会写入
          for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: file)
          }
        }
      }
    }.value
  }

  /// 磁盘上的缓存总量（字节）
  public func diskUsage() async -> Int {
    for cache in caches.values { cache.flush() }
    let root = root
    return await Task.detached { Self.allocatedSize(of: root) }.value
  }

  private nonisolated static func allocatedSize(of root: URL) -> Int {
    guard
      let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
    else { return 0 }
    var total = 0
    for case let file as URL in enumerator {
      let values = try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey])
      if values?.isRegularFile == true { total += values?.totalFileAllocatedSize ?? 0 }
    }
    return total
  }
}

extension EnvironmentValues {
  /// 当前端点的图片管线
  @Entry public var imagePipeline: ImagePipeline = .shared
}
