import AlbumCore
import AlbumImages
import NukeUI
import SafariServices
import SwiftUI

/// 订阅图标；没有图标或加载失败时显示名字的第一个字
struct AvatarView: View {
  var url: String?
  var name: String
  var size: CGFloat = 20
  var dark = false

  @Environment(\.imagePipeline) private var pipeline

  var body: some View {
    ZStack {
      Circle().fill(dark ? Color.viewerSurface2 : Color.paper3)
      Text(name.first.map { String($0).uppercased() } ?? "?")
        .font(.system(size: size * 0.46, weight: .bold))
        .foregroundStyle(dark ? Color.viewerForeground : Color.ink2)
      if let url, !url.isEmpty, let request = ImageRequests.thumbnail(url, size: CGSize(width: size, height: size)) {
        LazyImage(request: request) { state in
          if let image = state.image {
            image.resizable().scaledToFill()
          }
        }
        .pipeline(pipeline)
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .accessibilityHidden(true)
  }
}

struct EmptyStateView<Actions: View>: View {
  var systemImage: String
  var title: String
  var description: String
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    VStack(spacing: 14) {
      ToneView()
        .frame(width: 76, height: 76)
        .clipShape(Circle())
        .overlay {
          Image(systemName: systemImage)
            .font(.system(size: 28, weight: .medium))
            .foregroundStyle(Color.ink2)
        }
      Text(title)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(Color.ink)
        .multilineTextAlignment(.center)
      Text(description)
        .font(.system(size: 14))
        .foregroundStyle(Color.ink2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
      HStack(spacing: 10) { actions() }
        .padding(.top, 4)
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 48)
    .frame(maxWidth: .infinity)
  }
}

extension EmptyStateView where Actions == EmptyView {
  init(systemImage: String, title: String, description: String) {
    self.init(systemImage: systemImage, title: title, description: description) { EmptyView() }
  }
}

/// 墨色主按钮与描边次按钮
struct InkButtonStyle: ButtonStyle {
  var prominent = false
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 14, weight: .semibold))
      .padding(.horizontal, 16)
      .frame(minHeight: 38)
      .foregroundStyle(prominent ? Color.onInk : Color.ink)
      .background {
        Capsule().fill(prominent ? Color.ink : Color.paper)
          .overlay { if !prominent { Capsule().strokeBorder(Color.line) } }
      }
      .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
      .contentShape(Capsule())
  }
}

/// 屏幕底部的轻提示：同时最多三条，带撤销、重试等操作
struct ToastStack: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    VStack(spacing: 8) {
      ForEach(app.store.toasts.toasts) { toast in
        ToastRow(toast: toast) { app.store.toasts.dismiss(toast.id) }
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .padding(.horizontal, 16)
    .animation(.spring(duration: 0.3), value: app.store.toasts.toasts.map(\.id))
  }
}

private struct ToastRow: View {
  let toast: ToastCenter.Toast
  let dismiss: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(color)
        .padding(.top, 1)
      VStack(alignment: .leading, spacing: 2) {
        Text(toast.message)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(Color.ink)
        if let detail = toast.detail {
          Text(detail)
            .font(.system(size: 12))
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 4)
      if let action = toast.action {
        Button(action.label) {
          action.run()
          dismiss()
        }
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(Color.ink)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: 520)
    .glassBackground(in: RoundedRectangle(cornerRadius: 22, style: .continuous), fallback: .regularMaterial)
    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    .onTapGesture { if toast.action == nil { dismiss() } }
    .accessibilityElement(children: .combine)
  }

  private var icon: String {
    switch toast.tone {
    case .success: "checkmark.circle.fill"
    case .warning: "exclamationmark.circle.fill"
    case .neutral: "info.circle.fill"
    }
  }

  private var color: Color {
    switch toast.tone {
    case .success: .ok
    case .warning: .danger
    case .neutral: .ink2
    }
  }
}

/// 应用内浏览器：原文、原图、网站
struct SafariView: UIViewControllerRepresentable {
  let url: URL

  func makeUIViewController(context: Context) -> SFSafariViewController {
    let configuration = SFSafariViewController.Configuration()
    configuration.entersReaderIfAvailable = false
    let controller = SFSafariViewController(url: url, configuration: configuration)
    controller.preferredControlTintColor = UIColor(hex: 0xE5007E)
    return controller
  }

  func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// 页面顶部的错误横幅
struct Banner<Actions: View>: View {
  var title: String
  var message: String
  @ViewBuilder var actions: () -> Actions

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.circle.fill")
        .font(.system(size: 20))
        .foregroundStyle(Color.danger)
      VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.ink)
        Text(message).font(.system(size: 13)).foregroundStyle(Color.ink2)
        HStack(spacing: 8) { actions() }
          .padding(.top, 2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
    .background(Color.dangerSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

/// 连接或同步中的整页等待
struct LoadingView: View {
  var title: String
  var description: String

  var body: some View {
    VStack(spacing: 14) {
      ProgressView()
        .controlSize(.large)
      Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(Color.ink)
      Text(description)
        .font(.system(size: 14))
        .foregroundStyle(Color.ink2)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.paper)
  }
}
