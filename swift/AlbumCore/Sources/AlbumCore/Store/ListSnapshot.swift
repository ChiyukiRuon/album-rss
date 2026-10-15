import Foundation

/// 列表快照，对应 Web 端的 useScopeList：只在筛选条件变化、所属列表被重新读取（token 变化）
/// 或显式要求重排（listVersion）时重新取数；读到下一页时只在末尾追加。
/// 在查看器里标为已读或取消收藏的文章不会立刻从列表消失，列表也就不会跳动。
public struct ListSnapshot: Equatable, Sendable {
  struct ResetKey: Equatable, Sendable {
    var query: ListQuery
    var showImageless: Bool
    var listVersion: Int
    var token: Int?
  }

  var resetKey: ResetKey
  /// 上次读取时列表在服务端的长度；变长说明读到了下一页
  var sourceCount: Int
  public private(set) var ids: [String]
  /// 换了一份列表才变化；追加下一页时不变，瀑布流据此保留已放下的卡片
  public private(set) var layoutID: Int

  private static let counter = LayoutCounter()

  @MainActor
  static func make(query: ListQuery, store: AlbumStore, previous: ListSnapshot?) -> ListSnapshot {
    let scope = store.scopes[query]
    let showImageless = store.settings.showImageless
    let key = ResetKey(query: query, showImageless: showImageless, listVersion: store.listVersion, token: scope?.token)
    let visible = { (id: String) in Selectors.isVisible(store.entries[id], in: query, showImageless: showImageless) }
    guard let previous, previous.resetKey == key else {
      return ListSnapshot(
        resetKey: key,
        sourceCount: scope?.ids.count ?? 0,
        ids: (scope?.ids ?? []).filter(visible),
        layoutID: counter.next()
      )
    }
    guard let scope, scope.ids.count != previous.sourceCount else { return previous }
    // 读到了下一页：已有的保持原样，只在末尾补上新文章
    var next = previous
    let have = Set(previous.ids)
    let added = scope.ids.dropFirst(min(previous.sourceCount, scope.ids.count)).filter { !have.contains($0) && visible($0) }
    next.sourceCount = scope.ids.count
    if !added.isEmpty { next.ids += added }
    return next
  }
}

private final class LayoutCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.withLock {
      value += 1
      return value
    }
  }
}

extension AlbumStore {
  /// 列表的当前快照；previous 为上一次的结果（由视图保存）
  public func snapshot(for query: ListQuery, previous: ListSnapshot?) -> ListSnapshot {
    ListSnapshot.make(query: query, store: self, previous: previous)
  }
}
