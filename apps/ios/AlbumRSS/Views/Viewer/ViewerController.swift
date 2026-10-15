import AlbumCore
import Foundation
import Observation

/// 查看器的状态：翻页顺序取自打开它的那个列表，背后的列表据此跟随滚动
@MainActor @Observable
final class ViewerController {
  struct Session: Identifiable {
    let id = UUID()
    /// 打开查看器的列表
    let source: UUID
    let mode: WallMode
    var sequence: [String]
    var entryID: String
    var index: Int
  }

  /// 顶部的短暂提示：在图集首尾预告上一组 / 下一组
  struct Notice: Equatable, Identifiable {
    enum Kind {
      case next
      case previous
    }

    let id = UUID()
    var kind: Kind
    var entryID: String
  }

  var session: Session?
  var notice: Notice?

  func open(entryID: String, index: Int, sequence: [String], source: UUID, mode: WallMode) {
    notice = nil
    session = Session(source: source, mode: mode, sequence: sequence, entryID: entryID, index: index)
  }

  func go(entryID: String, index: Int) {
    guard var session else { return }
    session.entryID = entryID
    session.index = index
    self.session = session
  }

  func close() {
    session = nil
    notice = nil
  }

  /// 查看器打开期间读到了下一页：把新文章接到翻页顺序后面（只在旧顺序是新顺序的前缀时）
  func extend(_ sequence: [String], source: UUID) {
    guard var session, session.source == source, sequence.count > session.sequence.count,
      Array(sequence.prefix(session.sequence.count)) == session.sequence
    else { return }
    session.sequence = sequence
    self.session = session
  }

  /// 当前图片对应的卡片：图集模式是文章，图片流里是“文章:序号”
  var cardKey: String? {
    session.map { WallItem.key(entryID: $0.entryID, index: $0.mode == .albums ? nil : $0.index) }
  }

  /// 这个列表打开的查看器正停在哪张卡片上
  func focusKey(for source: UUID) -> String? {
    guard let session, session.source == source else { return nil }
    return cardKey
  }
}
