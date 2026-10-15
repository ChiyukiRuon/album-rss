import AlbumCore
import SwiftUI

/// 收藏：收藏会同步到 RSS 服务，其他设备上也能看到
struct StarredView: View {
  @Environment(AppModel.self) private var app
  @State private var mode: WallMode = .albums

  var body: some View {
    let store = app.store
    let query = ListQuery(status: .starred)
    let scope = store.scopes[query]
    let count = scope?.ids.count { store.entries[$0]?.starred == true && store.entries[$0]?.hasImages == true } ?? 0
    EntryWall(query: query, mode: mode, label: "收藏的图集", dimRead: false) {
      VStack(alignment: .leading, spacing: 12) {
        PageSubtitle(text: "\(count)\(scope?.done == false ? "+" : "") 个图集 · 收藏会同步到你的 RSS 服务")
        ModePicker(mode: $mode)
      }
      .padding(.top, 4)
    } empty: {
      EmptyStateView(
        systemImage: "star",
        title: "还没有收藏",
        description: "在查看器里点星标，就能收藏整个图集。收藏会同步到你的 RSS 服务，其他设备上也能看到。"
      )
    }
    .tabPageTitle("收藏")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { SyncToolbarButton() }
    }
  }
}
