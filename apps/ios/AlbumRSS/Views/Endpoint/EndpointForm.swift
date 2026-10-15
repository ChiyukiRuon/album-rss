import AlbumCore
import Observation
import SwiftUI

/// 添加或编辑 API 端点：验证连接、读取订阅后切换到这个端点
@MainActor @Observable
final class EndpointFormModel {
  enum StepStatus {
    case waiting
    case running
    case done
    case failed
  }

  struct Attempt {
    var host: String
    var origin: String
    var local: Bool
    var statuses: [StepStatus]
    var error: String?
  }

  let editing: Endpoint?
  var name: String
  var service: ServiceKind {
    didSet { if service != oldValue { attempt = nil } }
  }
  var server: String
  var apiKey: String
  var username: String
  var password = ""
  var showSecret = false
  var remember: Bool
  var mediaOrigin: String
  var fieldError: String?
  var attempt: Attempt?

  init(editing: Endpoint?) {
    self.editing = editing
    name = editing?.name ?? ""
    service = editing?.service ?? .miniflux
    server = editing?.server ?? ""
    apiKey = editing?.service == .miniflux ? (editing?.token ?? "") : ""
    username = editing?.username ?? ""
    // iOS 上凭据保存在钥匙串，默认保存
    remember = editing?.remember ?? true
    mediaOrigin = editing?.mediaOrigin ?? ""
  }

  var busy: Bool { attempt?.statuses.contains(.running) ?? false }
  var failed: Bool { attempt?.statuses.contains(.failed) ?? false }

  var stepLabels: [String] {
    ["连接服务", service == .miniflux ? "验证 API 密钥" : "登录并换取访问令牌", "读取订阅和最新文章"]
  }

  /// 返回是否连接成功
  func submit(store: AlbumStore) async -> Bool {
    let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), url.host() != nil else {
      fieldError = "请输入完整的地址，例如 https://rss.example.com"
      return false
    }
    guard scheme == "http" || scheme == "https" else {
      fieldError = "地址需要以 http:// 或 https:// 开头"
      return false
    }
    // Google Reader：地址和用户名不变、没填新密码时沿用已保存的令牌
    var normalized = trimmed
    while normalized.hasSuffix("/") { normalized.removeLast() }
    let token =
      editing?.service == service && editing?.server == normalized
        && editing?.username == username.trimmingCharacters(in: .whitespaces) && password.isEmpty
      ? editing?.token : nil
    let missing =
      service == .miniflux
      ? apiKey.trimmingCharacters(in: .whitespaces).isEmpty
      : username.trimmingCharacters(in: .whitespaces).isEmpty || (password.isEmpty && token == nil)
    if missing {
      fieldError = service == .miniflux ? "请填写 API 密钥" : "请填写用户名和密码"
      return false
    }
    fieldError = nil
    let host = url.host() ?? trimmed
    var statuses: [StepStatus] = [.running, .waiting, .waiting]
    var current = 0
    let base = (host: host + (url.port.map { ":\($0)" } ?? ""), origin: "\(scheme)://\(host)", local: Self.isLocal(host))
    attempt = Attempt(host: base.host, origin: base.origin, local: base.local, statuses: statuses)
    do {
      try await store.connect(
        ConnectInput(
          id: editing?.id,
          name: name,
          token: token,
          service: service,
          server: trimmed,
          username: username,
          remember: remember,
          apiKey: apiKey,
          password: password,
          mediaOrigin: service == .miniflux ? mediaOrigin : nil
        )
      ) { step in
        current = step
        for index in statuses.indices { statuses[index] = index < step ? .done : index == step ? .running : .waiting }
        self.attempt?.statuses = statuses
      }
      password = ""
      apiKey = ""
      attempt = nil
      return true
    } catch {
      statuses[current] = .failed
      attempt = Attempt(
        host: base.host, origin: base.origin, local: base.local, statuses: statuses, error: errorMessage(error))
      return false
    }
  }

  /// 局域网或本机地址：iOS 需要“本地网络”权限
  static func isLocal(_ host: String) -> Bool {
    let lower = host.lowercased()
    if lower == "localhost" || lower.hasSuffix(".local") || lower.hasSuffix(".lan") || lower.hasSuffix(".home") { return true }
    let parts = lower.split(separator: ".").compactMap { Int($0) }
    guard parts.count == 4 else { return lower.contains(":") && (lower.hasPrefix("fe80") || lower.hasPrefix("fd")) }
    return parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168) || (parts[0] == 172 && (16...31).contains(parts[1]))
      || (parts[0] == 169 && parts[1] == 254)
  }
}

/// 表单的各个分区，放在 Form 里使用
struct EndpointFields: View {
  @Bindable var model: EndpointFormModel
  /// 在密钥或密码框里按“前往”时连接
  var onSubmit: () -> Void = {}

  var body: some View {
    Section {
      Picker("服务类型", selection: $model.service) {
        Text("Miniflux").tag(ServiceKind.miniflux)
        Text("Google Reader 兼容").tag(ServiceKind.greader)
      }
      .pickerStyle(.segmented)
      .listRowBackground(Color.clear)
      .listRowInsets(EdgeInsets())
    }

    Section {
      Field("服务地址") {
        TextField(
          "服务地址",
          text: $model.server,
          prompt: Text(verbatim: model.service == .miniflux ? "https://rss.example.com" : "https://rss.example.com/api/greader.php")
        )
        .keyboardType(.URL)
        .textContentType(.URL)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .accessibilityIdentifier("endpoint-server")
      }
      if model.service == .greader {
        Field("用户名") {
          TextField("用户名", text: $model.username)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityIdentifier("endpoint-username")
        }
      }
      Field(model.service == .miniflux ? "API 密钥" : "密码") {
        HStack {
          Group {
            if model.showSecret {
              TextField(model.service == .miniflux ? "API 密钥" : "密码", text: secret)
            } else {
              SecureField(model.service == .miniflux ? "API 密钥" : "密码", text: secret)
            }
          }
          .textContentType(model.service == .miniflux ? nil : .password)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .submitLabel(.go)
          .onSubmit(onSubmit)
          .accessibilityIdentifier("endpoint-secret")
          Button {
            model.showSecret.toggle()
          } label: {
            Image(systemName: model.showSecret ? "eye.slash" : "eye").foregroundStyle(Color.ink3)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(model.showSecret ? "隐藏" : "显示")
        }
      }
    } header: {
      Text("服务")
    } footer: {
      Text(
        model.service == .miniflux
          ? "在 Miniflux 的“设置 → API 密钥”里创建。"
          : model.editing != nil
            ? "地址和用户名不变时，可留空以保留现有令牌；密码不会被保存。"
            : "密码只用来换取访问令牌，不会被保存。服务地址需包含 API 路径。")
    }

    Section {
      Field("端点名称（可选）") {
        TextField("端点名称", text: $model.name, prompt: Text("例如：插画订阅"))
      }
      if model.service == .miniflux {
        Field("服务公开地址（可选）") {
          TextField("服务公开地址", text: $model.mediaOrigin, prompt: Text(verbatim: "https://miniflux.example.com"))
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
      }
      Toggle("在此设备保存凭据", isOn: $model.remember)
    } footer: {
      VStack(alignment: .leading, spacing: 6) {
        if model.service == .miniflux {
          Text("服务公开地址：通过局域网地址连接时，可填写 Miniflux 配置的公开地址，将其 /proxy/ 图片指向当前服务。")
        }
        Text("凭据保存在本机钥匙串，删除这个端点时清除。关闭后只保存在内存中，App 退出后这个端点会被移除。")
      }
    }

    if let error = model.fieldError {
      Section {
        Label(error, systemImage: "exclamationmark.circle.fill")
          .foregroundStyle(Color.danger)
          .font(.system(size: 14, weight: .semibold))
      }
    }

    if let attempt = model.attempt {
      Section("连接进度") {
        ForEach(Array(model.stepLabels.enumerated()), id: \.offset) { index, label in
          StepRow(label: label, status: attempt.statuses[index])
        }
      }
      if model.failed {
        Section {
          VStack(alignment: .leading, spacing: 8) {
            Label("无法连接到 \(attempt.host)", systemImage: "exclamationmark.triangle.fill")
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(Color.danger)
            if let error = attempt.error {
              Text(error).font(.system(size: 14)).foregroundStyle(Color.ink)
            }
            VStack(alignment: .leading, spacing: 4) {
              Text("可能的原因：").font(.system(size: 13, weight: .semibold))
              Text("· 这台设备访问不到这个地址。可以在 Safari 里打开 \(attempt.origin) 确认。")
              Text("· 服务器证书无效或已过期。")
              if attempt.local {
                Text("· 这是局域网地址：请在系统“设置 → 隐私与安全性 → 本地网络”中允许 Album RSS，并确认设备和服务在同一网络。")
              }
              Text(
                model.service == .miniflux
                  ? "· 服务不是 Miniflux，或地址多了、少了子路径。"
                  : "· 服务类型或 API 路径不对：地址需要包含协议入口，例如 FreshRSS 的 /api/greader.php。")
            }
            .font(.system(size: 13))
            .foregroundStyle(Color.ink2)
          }
          .padding(.vertical, 4)
          .id(EndpointFields.failureAnchor)
        }
      }
    }
  }

  static let failureAnchor = "endpoint-failure"

  private var secret: Binding<String> {
    model.service == .miniflux ? $model.apiKey : $model.password
  }
}

/// 表单字段：上面是小号标签，下面是输入框（与 Web 端的表单一致）
private struct Field<Content: View>: View {
  let label: String
  @ViewBuilder var content: () -> Content

  init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
    self.label = label
    self.content = content
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.ink2)
        .accessibilityHidden(true)
      content()
    }
    .padding(.vertical, 2)
  }
}

private struct StepRow: View {
  let label: String
  let status: EndpointFormModel.StepStatus

  var body: some View {
    HStack(spacing: 10) {
      Group {
        switch status {
        case .running: ProgressView().controlSize(.small)
        case .done: Image(systemName: "checkmark").foregroundStyle(Color.ok)
        case .failed: Image(systemName: "xmark").foregroundStyle(Color.danger)
        case .waiting: Circle().strokeBorder(Color.ink3, lineWidth: 1.5).frame(width: 12, height: 12)
        }
      }
      .frame(width: 20)
      Text(label).foregroundStyle(status == .waiting ? Color.ink3 : Color.ink)
    }
    .font(.system(size: 14, weight: .medium))
    .accessibilityElement(children: .combine)
  }
}

/// 应用里添加、编辑端点的弹层
struct EndpointSheetView: View {
  let route: EndpointSheet

  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  @State private var model: EndpointFormModel?

  var body: some View {
    NavigationStack {
      Group {
        if let model {
          ScrollViewReader { proxy in
            Form { EndpointFields(model: model, onSubmit: submit) }
              .disabled(model.busy)
              .onChange(of: model.failed) { _, failed in
                // 失败说明出现在表单末尾，滚动到能看到它的位置
                if failed { withAnimation { proxy.scrollTo(EndpointFields.failureAnchor, anchor: .bottom) } }
              }
          }
        }
      }
      .navigationTitle(editing == nil ? "添加 API 端点" : "编辑 API 端点")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("取消") {
            // 关闭弹层即放弃进行中的连接
            app.store.cancelConnect()
            dismiss()
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(model?.busy == true ? "正在连接…" : editing == nil ? "连接" : "保存并连接", action: submit)
            .disabled(model?.busy ?? true)
        }
      }
    }
    .interactiveDismissDisabled(model?.busy ?? false)
    .onAppear { if model == nil { model = EndpointFormModel(editing: editing) } }
  }

  private var editing: Endpoint? {
    if case .edit(let id) = route { return app.store.endpoints.first { $0.id == id } }
    return nil
  }

  private func submit() {
    guard let model, !model.busy else { return }
    Task {
      if await model.submit(store: app.store) { dismiss() }
    }
  }
}
