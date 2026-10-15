import AlbumCore
import AlbumImages
import SwiftUI

/// 设置：API 端点、浏览、外观、图片缓存；演示模式下另有原型调试项
struct SettingsView: View {
  @Environment(AppModel.self) private var app
  @State private var cacheUsage: Int?
  @State private var removing: Endpoint?
  @State private var switching: String?

  private static let cacheLimits = [250, 500, 1000, 2000, 5000].map { $0 * 1_000_000 }

  var body: some View {
    let store = app.store
    Form {
      Section {
        if let current = store.endpoint, current.isDemo {
          LabeledContent {
            Button("退出演示") { store.exitDemo() }
          } label: {
            EndpointLabel(title: "演示数据", detail: "本地生成的示例，没有连接任何服务器。", current: true)
          }
        }
        ForEach(store.endpoints) { endpoint in
          endpointRow(endpoint, current: endpoint.id == store.endpoint?.id)
        }
        Button("添加 API 端点", systemImage: "plus") { app.endpointSheet = .add }
      } header: {
        Text("API 端点")
      } footer: {
        Text("每个端点分别保存地址、凭据，以及是否把凭据保存在钥匙串里。已读和收藏会同步到对应的 RSS 服务。")
      }

      Section("浏览") {
        Toggle(isOn: binding(\.autoRead)) {
          SettingLabel(title: "打开图集时标为已读", detail: "至少一张图片显示成功后才标记；滚动列表和预加载不会标记。")
        }
        Toggle(isOn: binding(\.downloadRead)) {
          SettingLabel(title: "保存后标为已读", detail: "本次保存的图片全部成功后，将所属图集标为已读；失败时不标记。")
        }
        Toggle(isOn: binding(\.showImageless)) {
          SettingLabel(title: "显示没有图片的文章", detail: "包括确认没有图片的文章，和图片还没解析出来的文章。")
        }
        Picker(selection: binding(\.defaultStatus)) {
          Text("未读").tag(ListStatus.unread)
          Text("全部").tag(ListStatus.all)
        } label: {
          SettingLabel(title: "默认显示", detail: "打开“浏览”时先看到的范围。")
        }
        Picker(selection: binding(\.density)) {
          Text("紧凑").tag(Density.compact)
          Text("标准").tag(Density.standard)
          Text("宽松").tag(Density.roomy)
        } label: {
          SettingLabel(title: "卡片大小", detail: "iPhone 竖屏上分别是三列、两列和一列。")
        }
      }

      Section("外观") {
        Picker(selection: binding(\.theme)) {
          Text("跟随系统").tag(Theme.system)
          Text("浅色").tag(Theme.light)
          Text("深色").tag(Theme.dark)
        } label: {
          SettingLabel(title: "主题", detail: "查看器始终使用深色背景。")
        }
      }

      Section {
        LabeledContent("已使用") {
          Text(cacheUsage.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "正在计算…")
            .monospacedDigit()
        }
        Picker("容量上限", selection: binding(\.imageCacheLimit)) {
          ForEach(Self.cacheLimits, id: \.self) { limit in
            Text(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file)).tag(limit)
          }
        }
        Button("清除图片缓存", systemImage: "trash", role: .destructive) {
          Task {
            await app.images.clearAll()
            await refreshUsage()
            store.toasts.show("已清除图片缓存", tone: .success)
          }
        }
      } header: {
        Text("图片缓存")
      } footer: {
        Text("浏览时看过的原图会缓存在这台设备上，离线时也能查看；超过上限时自动清理最久没看的。保存到相册的图片不受影响。")
      }

      if store.endpoint?.isDemo == true {
        Section("原型调试") {
          Toggle(isOn: binding(\.simulateLatency)) {
            SettingLabel(title: "模拟图片加载耗时", detail: "用来观察网点占位，以及瀑布流“先测量尺寸再放入”的过程。")
          }
          Button("模拟后台同步") { Task { await store.sync(explicit: false) } }
          Button("重置演示数据") { store.resetDemo() }
        }
      }

      Section {
        VStack(alignment: .leading, spacing: 8) {
          Wordmark()
          Text("直接连接你的 RSS 服务，不经过任何中转服务器。")
            .font(.system(size: 13))
            .foregroundStyle(Color.ink2)
          Text("版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
            .font(.system(size: 12))
            .foregroundStyle(Color.ink3)
        }
        .padding(.vertical, 4)
        Button {
          app.open("https://github.com/ChiyukiRuon/album-rss")
        } label: {
          Label("ChiyukiRuon/album-rss", systemImage: "chevron.left.forwardslash.chevron.right")
        }
      }
    }
    .tabPageTitle("设置")
    .task { await refreshUsage() }
    .confirmationDialog(
      removing.map { endpoint in
        endpoint.id == store.endpoint?.id
          ? "删除正在使用的端点「\(endpoint.label)」及其保存的凭据？之后会切换到下一个端点；已同步到服务器的已读和收藏不受影响。"
          : "删除端点「\(endpoint.label)」及其保存的凭据？已同步到服务器的已读和收藏不受影响。"
      } ?? "",
      isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
      titleVisibility: .visible
    ) {
      Button("删除端点", role: .destructive) {
        if let endpoint = removing { Task { await store.removeEndpoint(endpoint.id) } }
        removing = nil
      }
      Button("取消", role: .cancel) { removing = nil }
    }
  }

  private func endpointRow(_ endpoint: Endpoint, current: Bool) -> some View {
    let detail = [
      endpoint.service.label,
      endpoint.name == nil ? nil : endpoint.host,
      endpoint.remember ? "凭据保存在钥匙串" : "仅本次运行，退出后移除",
    ].compactMap { $0 }.joined(separator: " · ")
    return Button {
      guard !current else { return }
      switching = endpoint.id
      Task {
        do {
          try await app.store.switchEndpoint(endpoint.id)
        } catch {
          app.store.toasts.show("无法切换到「\(endpoint.label)」", detail: errorMessage(error), tone: .warning)
        }
        switching = nil
      }
    } label: {
      HStack {
        EndpointLabel(title: endpoint.label, detail: detail, current: current)
        Spacer()
        if switching == endpoint.id { ProgressView() }
      }
    }
    .foregroundStyle(Color.ink)
    .swipeActions {
      Button("删除", role: .destructive) { removing = endpoint }
      Button("编辑") { app.endpointSheet = .edit(endpoint.id) }
    }
    .contextMenu {
      Button("编辑", systemImage: "pencil") { app.endpointSheet = .edit(endpoint.id) }
      Button("删除", systemImage: "trash", role: .destructive) { removing = endpoint }
    }
  }

  private func binding<Value>(_ keyPath: WritableKeyPath<Settings, Value>) -> Binding<Value> {
    Binding(
      get: { app.store.settings[keyPath: keyPath] },
      set: { value in app.updateSettings { $0[keyPath: keyPath] = value } }
    )
  }

  private func refreshUsage() async {
    cacheUsage = await app.images.diskUsage()
  }
}

private struct EndpointLabel: View {
  let title: String
  let detail: String
  let current: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Text(title).font(.system(size: 16, weight: .semibold))
        if current {
          Label("当前使用", systemImage: "circle.fill")
            .labelStyle(CurrentBadgeStyle())
        }
      }
      Text(detail).font(.system(size: 12)).foregroundStyle(Color.ink2)
    }
    .padding(.vertical, 2)
  }
}

private struct CurrentBadgeStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 4) {
      configuration.icon.font(.system(size: 6)).foregroundStyle(Color.ok)
      configuration.title.font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink2)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 3)
    .background(Capsule().fill(Color.paper2))
  }
}

private struct SettingLabel: View {
  let title: String
  let detail: String

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title)
      Text(detail).font(.system(size: 12)).foregroundStyle(Color.ink2)
    }
  }
}
