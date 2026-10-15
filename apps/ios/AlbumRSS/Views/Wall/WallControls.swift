import AlbumCore
import SwiftUI

/// 未读 / 全部
struct StatusPicker: View {
  @Binding var status: ListStatus
  var unread: Int

  var body: some View {
    Picker("显示范围", selection: $status) {
      Text(unread > 0 ? "未读 \(unread)" : "未读").tag(ListStatus.unread)
      Text("全部").tag(ListStatus.all)
    }
    .pickerStyle(.segmented)
    .fixedSize()
  }
}

/// 图集 / 图片流
struct ModePicker: View {
  @Binding var mode: WallMode

  var body: some View {
    Picker("展示方式", selection: $mode) {
      Label("图集", systemImage: "square.stack").tag(WallMode.albums)
      Label("图片流", systemImage: "photo.on.rectangle").tag(WallMode.images)
    }
    .pickerStyle(.segmented)
    .fixedSize()
  }
}

struct FolderChip: Identifiable, Equatable {
  var id: String
  var title: String
  /// 按钮里的小号数字；为 0 或空时不显示
  var count: Int?
}

/// 按分类筛选。分类来自 RSS 服务；不到两个分类时由调用方隐藏。始终只占一行，放不下时横向滚动
struct FolderChips: View {
  let chips: [FolderChip]
  @Binding var selection: String?

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          chip(id: nil, title: "全部订阅", count: nil)
          ForEach(chips) { chip(id: $0.id, title: $0.title, count: $0.count) }
        }
        .padding(.vertical, 2)
      }
      .scrollIndicators(.hidden)
      .scrollClipDisabled()
      .onAppear { if let selection { proxy.scrollTo(selection, anchor: .center) } }
      .onChange(of: selection) { _, value in
        withAnimation { proxy.scrollTo(value ?? "all", anchor: .center) }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("按分类筛选")
  }

  private func chip(id: String?, title: String, count: Int?) -> some View {
    let selected = selection == id
    return Button {
      selection = id
    } label: {
      HStack(spacing: 6) {
        Text(title)
        if let count, count > 0 {
          Text("\(count)").monospacedDigit().opacity(0.6)
        }
      }
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(selected ? Color.onInk : Color.ink2)
      .padding(.horizontal, 14)
      .frame(height: 32)
      .background {
        Capsule()
          .fill(selected ? Color.ink : Color.paper)
          .overlay { Capsule().strokeBorder(selected ? Color.ink : Color.line) }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .id(id ?? "all")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// 后台同步到的新内容：由用户决定何时放进列表，正在看的列表不会自己跳动
struct NewItemsPill: View {
  let count: Int
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label("\(count) 个新图集", systemImage: "arrow.up")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .glassBackground(in: Capsule(), tint: .spot, interactive: true)
        .shadow(color: Color.spot.opacity(0.35), radius: 9, y: 6)
    }
    .buttonStyle(.plain)
  }
}

/// 页面标题下方的一行说明
struct PageSubtitle: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 13))
      .foregroundStyle(Color.ink2)
      .lineLimit(2)
  }
}

/// 同步失败、写入被拒时的横幅
struct SyncBanners: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    let store = app.store
    if let endpoint = store.endpoint, let message = store.writeErrors[endpoint.id] {
      Banner(title: "已读和收藏暂时无法写入服务", message: message) {
        Button("编辑端点") { app.endpointSheet = .edit(endpoint.id) }
          .buttonStyle(InkButtonStyle(prominent: true))
      }
    }
    if let error = store.sync.error {
      Banner(title: "同步失败", message: error) {
        Button("重试同步") { Task { await store.sync(explicit: true) } }
          .buttonStyle(InkButtonStyle(prominent: true))
          .disabled(store.sync.status == .syncing)
        if let endpoint = store.endpoint, endpoint.kind == .connected {
          Button("编辑端点") { app.endpointSheet = .edit(endpoint.id) }
            .buttonStyle(InkButtonStyle())
        }
      }
    }
  }
}

/// 工具栏的同步按钮：同步中显示进度
struct SyncToolbarButton: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    let syncing = app.store.sync.status == .syncing
    Button {
      Task { await app.store.sync(explicit: true) }
    } label: {
      if syncing {
        ProgressView()
      } else {
        Image(systemName: "arrow.clockwise")
      }
    }
    .disabled(syncing)
    .accessibilityLabel(syncing ? "正在同步" : "同步")
  }
}
