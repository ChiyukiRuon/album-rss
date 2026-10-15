import AlbumCore
import SwiftUI

/// 还没有正在使用的端点时的入口：选择已保存的端点、添加一个新的，或者先看演示数据
struct ConnectView: View {
  @Environment(AppModel.self) private var app
  @State private var model = EndpointFormModel(editing: nil)
  @State private var connecting: String?
  @State private var savedError: String?

  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
      Form {
        Section {
          VStack(alignment: .leading, spacing: 12) {
            Wordmark()
            Text("连接你的 RSS 服务")
              .font(.system(size: 28, weight: .bold))
              .foregroundStyle(Color.ink)
            Text("Album RSS 把订阅里的插画和照片整理成图集。它直接连接你已有的 Miniflux 或 Google Reader 兼容服务，不经过任何中转服务器。")
              .font(.system(size: 15))
              .foregroundStyle(Color.ink2)
          }
          .padding(.vertical, 8)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
        }

        if !app.store.endpoints.isEmpty {
          Section {
            ForEach(app.store.endpoints) { endpoint in
              Button {
                connect(endpoint)
              } label: {
                HStack(spacing: 12) {
                  Text(endpoint.monogram)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.onInk)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.ink))
                  VStack(alignment: .leading, spacing: 2) {
                    Text(endpoint.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
                    Text(endpoint.detail).font(.system(size: 12)).foregroundStyle(Color.ink2)
                  }
                  Spacer()
                  if connecting == endpoint.id { ProgressView() } else { Image(systemName: "chevron.right").foregroundStyle(Color.ink3) }
                }
              }
              .disabled(model.busy || (connecting != nil && connecting != endpoint.id))
            }
          } header: {
            Text("已保存的端点")
          } footer: {
            if let savedError { Text(savedError).foregroundStyle(Color.danger) }
          }
        }

        EndpointFields(model: model, onSubmit: submit)

        Section {
          Button(action: submit) {
            Text(model.busy ? "正在连接…" : "连接")
              .font(.system(size: 16, weight: .semibold))
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(InkButtonStyle(prominent: true))
          .disabled(model.busy)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())

          Button("先用演示数据看看") { app.store.enterDemo() }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity)
            .disabled(model.busy)
            .listRowBackground(Color.clear)
            .accessibilityIdentifier("enter-demo")
        } footer: {
          Text("连接后先读取订阅和最新一页文章，更早的文章在浏览时按需读取；已读与收藏会回写到服务。")
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
        }
      }
      .formStyle(.grouped)
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: model.failed) { _, failed in
        // 失败说明出现在表单末尾，滚动到能看到它的位置
        if failed { withAnimation { proxy.scrollTo(EndpointFields.failureAnchor, anchor: .center) } }
      }
      }
      .frame(maxWidth: 680)
      .frame(maxWidth: .infinity)
      .background(Color(uiColor: .systemGroupedBackground))
    }
  }

  private func submit() {
    guard !model.busy else { return }
    Task { _ = await model.submit(store: app.store) }
  }

  private func connect(_ endpoint: Endpoint) {
    connecting = endpoint.id
    savedError = nil
    Task {
      do {
        try await app.store.switchEndpoint(endpoint.id)
      } catch {
        savedError = errorMessage(error)
      }
      connecting = nil
    }
  }
}
