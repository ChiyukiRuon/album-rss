import AVKit
import AlbumCore
import AlbumImages
import Nuke
import SwiftUI
import UIKit

/// 查看器里的一页：某篇文章的第几张图
nonisolated struct ViewerPage: Hashable, Sendable {
  let entryID: String
  let index: Int
  let url: String
  /// 原图尺寸（已知时）：用于适应窗口和限制解码大小。不参与相等判断：
  /// 尺寸测量结果晚到时，同一页不应被当成另一页而重新加载
  let size: CGSize?
  var isVideo: Bool = false

  static func == (lhs: ViewerPage, rhs: ViewerPage) -> Bool {
    lhs.entryID == rhs.entryID && lhs.index == rhs.index && lhs.url == rhs.url
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(entryID)
    hasher.combine(index)
    hasher.combine(url)
  }
}

/// 左右翻页：相邻页按列表顺序惰性计算，看完一个图集直接进入下一组
struct ImagePager: UIViewControllerRepresentable {
  enum Direction {
    case before
    case after
  }

  let current: ViewerPage
  let pipeline: ImagePipeline
  let autoplay: Bool
  let endBehavior: VideoEndBehavior
  let onVideoEnded: (ViewerPage) -> Void
  let neighbor: (ViewerPage, Direction) -> ViewerPage?
  /// 页在顺序里的位置，决定程序跳转时的翻页方向
  let order: (ViewerPage) -> [Int]
  let onChange: (ViewerPage) -> Void
  /// 当前页的图片显示成功
  let onShown: (ViewerPage) -> Void
  let onTap: () -> Void
  let onOpenOriginal: (ViewerPage) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIViewController(context: Context) -> UIPageViewController {
    let controller = UIPageViewController(
      transitionStyle: .scroll, navigationOrientation: .horizontal, options: [.interPageSpacing: 16])
    controller.dataSource = context.coordinator
    controller.delegate = context.coordinator
    controller.view.backgroundColor = .clear
    controller.setViewControllers([context.coordinator.makePage(current)], direction: .forward, animated: false)
    context.coordinator.displayed = current
    context.coordinator.prefetch(around: current)
    return controller
  }

  func updateUIViewController(_ controller: UIPageViewController, context: Context) {
    let coordinator = context.coordinator
    coordinator.parent = self
    (controller.viewControllers?.first as? ZoomPageController)?.refreshAutoplay()
    guard let displayed = coordinator.displayed, displayed != current, !coordinator.transitioning else { return }
    // 缩略图条、“下一组”等程序跳转
    let forward = !order(current).lexicographicallyPrecedes(order(displayed))
    let page = coordinator.makePage(current)
    coordinator.displayed = current
    let target = current
    controller.setViewControllers([page], direction: forward ? .forward : .reverse, animated: true) { [weak controller, weak coordinator] _ in
      // UIPageViewController 在动画跳转后会缓存旧的相邻页：再设一次（不带动画）刷新数据源。
      // 期间又跳到了别的页时不再设置，免得旧的跳转盖过新的
      DispatchQueue.main.async {
        guard let coordinator, coordinator.displayed == target else { return }
        controller?.setViewControllers([page], direction: .forward, animated: false)
      }
    }
    coordinator.prefetch(around: current)
  }

  final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    var parent: ImagePager
    var displayed: ViewerPage?
    var transitioning = false
    private var prefetcher: ImagePrefetcher?

    init(parent: ImagePager) {
      self.parent = parent
    }

    func makePage(_ page: ViewerPage) -> ZoomPageController {
      let controller = ZoomPageController(page: page, pipeline: parent.pipeline)
      controller.endBehavior = { [weak self] in self?.parent.endBehavior ?? .pause }
      controller.onVideoEnded = { [weak self] page in
        guard let self, self.displayed == page, !self.transitioning else { return }
        self.parent.onVideoEnded(page)
      }
      controller.shouldAutoplay = { [weak self] in self?.parent.autoplay ?? false }
      controller.onTap = { [weak self] in self?.parent.onTap() }
      controller.onShown = { [weak self] page in
        guard let self, page == self.displayed else { return }
        self.parent.onShown(page)
      }
      controller.onOpenOriginal = { [weak self] page in self?.parent.onOpenOriginal(page) }
      return controller
    }

    /// 预取前后各一张，换图时放弃旧的预取
    func prefetch(around page: ViewerPage) {
      let pages = [parent.neighbor(page, .after), parent.neighbor(page, .before)].compactMap { $0 }
      let requests = pages.filter { !$0.isVideo }.compactMap { ImageRequests.viewer($0.url, originalSize: $0.size) }
      prefetcher?.stopPrefetching()
      let prefetcher = ImagePrefetcher(pipeline: parent.pipeline)
      prefetcher.startPrefetching(with: requests)
      self.prefetcher = prefetcher
    }

    func pageViewController(_ controller: UIPageViewController, viewControllerBefore viewController: UIViewController)
      -> UIViewController?
    {
      guard let page = (viewController as? ZoomPageController)?.page, let previous = parent.neighbor(page, .before)
      else { return nil }
      return makePage(previous)
    }

    func pageViewController(_ controller: UIPageViewController, viewControllerAfter viewController: UIViewController)
      -> UIViewController?
    {
      guard let page = (viewController as? ZoomPageController)?.page, let next = parent.neighbor(page, .after) else {
        return nil
      }
      return makePage(next)
    }

    func pageViewController(
      _ controller: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]
    ) {
      transitioning = true
    }

    func pageViewController(
      _ controller: UIPageViewController,
      didFinishAnimating finished: Bool,
      previousViewControllers: [UIViewController],
      transitionCompleted completed: Bool
    ) {
      transitioning = false
      guard completed, let current = controller.viewControllers?.first as? ZoomPageController else { return }
      displayed = current.page
      parent.onChange(current.page)
      prefetch(around: current.page)
      // 停稳后才算“显示成功”：预备好的相邻页不会把下一组标为已读
      if current.isShown { parent.onShown(current.page) }
    }
  }
}

/// 一页：加载、适应窗口、缩放；失败时可以重试或打开原图
final class ZoomPageController: UIViewController {
  let page: ViewerPage
  private let pipeline: ImagePipeline
  private let zoomView = ZoomImageView()
  private var placeholder: UIHostingController<PageStateView>?
  private var task: Task<Void, Never>?
  var endBehavior: (() -> VideoEndBehavior)?
  var onVideoEnded: ((ViewerPage) -> Void)?
  var shouldAutoplay: (() -> Bool)?
  private var visible = false
  private var attemptedAutoplay = false
  private var automaticallyPlaying = false
  private var videoController: AVPlayerViewController?
  private var playbackObservation: NSKeyValueObservation?
  private var statusObservation: NSKeyValueObservation?
  private(set) var isShown = false
  var onTap: (() -> Void)?
  var onShown: ((ViewerPage) -> Void)?
  var onOpenOriginal: ((ViewerPage) -> Void)?

  init(page: ViewerPage, pipeline: ImagePipeline) {
    self.page = page
    self.pipeline = pipeline
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    zoomView.frame = view.bounds
    zoomView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    zoomView.onSingleTap = { [weak self] in self?.onTap?() }
    view.addSubview(zoomView)
    load()
  }

  deinit {
    task?.cancel()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    visible = true
    refreshAutoplay()
  }

  /// 相邻预备页不播放；网络变化也不会把用户暂停的视频重新启动。
  func refreshAutoplay() {
    guard page.isVideo else { return }
    guard shouldAutoplay?() == true else {
      if automaticallyPlaying { videoController?.player?.pause() }
      automaticallyPlaying = false
      return
    }
    guard visible, !attemptedAutoplay, let player = videoController?.player else { return }
    attemptedAutoplay = true
    automaticallyPlaying = true
    player.play()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    visible = false
    attemptedAutoplay = false
    automaticallyPlaying = false
    videoController?.player?.pause()
  }

  private func loadVideo() {
    showState(nil)
    zoomView.isHidden = true
    if videoController == nil {
      let controller = AVPlayerViewController()
      addChild(controller)
      view.addSubview(controller.view)
      controller.view.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        controller.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 72),
        controller.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -140),
      ])
      controller.didMove(toParent: self)
      videoController = controller
    }
    guard let url = URL(string: page.url) else { showState(.failed); return }
    videoController?.player?.pause()
    let player = AVPlayer(url: url)
    videoController?.player = player
    NotificationCenter.default.removeObserver(self, name: AVPlayerItem.didPlayToEndTimeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(videoEnded(_:)),
      name: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem)
    playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
      let playing = player.timeControlStatus == .playing
      Task { @MainActor [weak self] in
        guard let self, playing else { return }
        self.isShown = true
        self.onShown?(self.page)
      }
    }
    statusObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      let failed = item.status == .failed
      Task { @MainActor [weak self] in
        if failed { self?.showState(.failed) }
      }
    }
  }

  @objc nonisolated private func videoEnded(_ notification: Notification) {
    let item = notification.object as? AVPlayerItem
    Task { @MainActor [weak self] in
      guard let self, self.visible, let player = self.videoController?.player, player.currentItem === item else { return }
      switch self.endBehavior?() ?? .pause {
      case .pause:
        player.pause()
      case .nextGroup:
        player.pause()
        self.onVideoEnded?(self.page)
      case .loop:
        let finished = await player.seek(to: .zero)
        guard finished, self.visible, player === self.videoController?.player, self.endBehavior?() == .loop else { return }
        player.play()
      }
    }
  }

  private func load() {
    if page.isVideo { loadVideo(); return }
    showState(.loading(aspect: page.size.map { $0.width / max(1, $0.height) }))
    task?.cancel()
    guard let request = ImageRequests.viewer(page.url, originalSize: page.size) else {
      showState(.failed)
      return
    }
    let pipeline = pipeline
    task = Task { [weak self] in
      do {
        let image = try await pipeline.image(for: request)
        guard let self, !Task.isCancelled else { return }
        let natural = self.page.size ?? CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        self.zoomView.display(image, naturalSize: natural)
        self.showState(nil)
        self.isShown = true
        self.onShown?(self.page)
      } catch {
        guard let self, !Task.isCancelled else { return }
        self.showState(.failed)
      }
    }
  }

  private func showState(_ state: PageStateView.State?) {
    placeholder?.view.removeFromSuperview()
    placeholder?.removeFromParent()
    placeholder = nil
    guard let state else { return }
    let host = UIHostingController(
      rootView: PageStateView(
        state: state,
        retry: { [weak self] in self?.load() },
        openOriginal: { [weak self] in
          guard let self else { return }
          self.onOpenOriginal?(self.page)
        }))
    host.view.backgroundColor = .clear
    host.view.frame = view.bounds
    host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addChild(host)
    view.addSubview(host.view)
    host.didMove(toParent: self)
    // 加载中的网点不拦截点按：单击照样可以切换界面
    host.view.isUserInteractionEnabled = state == .failed
    placeholder = host
  }
}

/// 页面上的加载中与失败状态
struct PageStateView: View {
  enum State: Equatable {
    case loading(aspect: Double?)
    case failed
  }

  let state: State
  let retry: () -> Void
  let openOriginal: () -> Void

  var body: some View {
    GeometryReader { proxy in
      switch state {
      case .loading(let aspect):
        let ratio = aspect ?? 0.75
        let width = min(proxy.size.width, proxy.size.height * ratio)
        ToneView(loading: true, background: .viewerTone, dot: .viewerToneDot)
          .frame(width: width, height: width / ratio)
          .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
      case .failed:
        VStack(spacing: 10) {
          Image(systemName: "photo.badge.exclamationmark").font(.system(size: 34))
          Text("媒体加载失败").font(.system(size: 17, weight: .bold))
          Text("可能是源站暂时无法访问，地址已经失效或格式不受支持。")
            .font(.system(size: 14))
            .foregroundStyle(Color.viewerSecondary)
            .multilineTextAlignment(.center)
          HStack(spacing: 10) {
            Button("重试", systemImage: "arrow.clockwise", action: retry)
            Button("打开媒体链接", systemImage: "arrow.up.forward.square", action: openOriginal)
          }
          .buttonStyle(.bordered)
          .tint(.white)
          .padding(.top, 4)
        }
        .foregroundStyle(Color.viewerForeground)
        .padding(32)
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
    }
  }
}

/// 可缩放的图片：适应窗口显示、不放大小图；双击放大或复位；超长的条漫切成多段显示
final class ZoomImageView: UIScrollView, UIScrollViewDelegate {
  var onSingleTap: (() -> Void)?
  private let container = UIView()
  private var naturalSize = CGSize.zero
  private var fittedSize = CGSize.zero
  private var lastBounds = CGSize.zero
  /// 每一段在整张图里的位置（占总高度的比例）
  private var stripes: [(view: UIImageView, top: CGFloat, height: CGFloat)] = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    delegate = self
    showsVerticalScrollIndicator = false
    showsHorizontalScrollIndicator = false
    decelerationRate = .fast
    contentInsetAdjustmentBehavior = .never
    bouncesZoom = true
    addSubview(container)
    let double = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
    double.numberOfTapsRequired = 2
    let single = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
    // 单击要等双击失败再触发，免得放大时界面先消失
    single.require(toFail: double)
    addGestureRecognizer(double)
    addGestureRecognizer(single)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func display(_ image: UIImage, naturalSize: CGSize) {
    container.subviews.forEach { $0.removeFromSuperview() }
    stripes = []
    let pieces = Self.stripes(of: image)
    let total = max(1, pieces.reduce(0) { $0 + $1.size.height })
    var top: CGFloat = 0
    for piece in pieces {
      let view = UIImageView(image: piece)
      view.contentMode = .scaleToFill
      view.layer.minificationFilter = .trilinear
      container.addSubview(view)
      stripes.append((view, top / total, piece.size.height / total))
      top += piece.size.height
    }
    self.naturalSize = naturalSize
    lastBounds = .zero
    setNeedsLayout()
  }

  /// 很长的图（高度超过 4096 像素）切成多段，避免超出单张纹理的上限
  private static func stripes(of image: UIImage) -> [UIImage] {
    guard let cg = image.cgImage, cg.height > 4096, cg.height > cg.width * 3 else { return [image] }
    var pieces: [UIImage] = []
    var y = 0
    while y < cg.height {
      let height = min(2048, cg.height - y)
      if let piece = cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: height)) {
        pieces.append(UIImage(cgImage: piece, scale: image.scale, orientation: .up))
      }
      y += height
    }
    return pieces.isEmpty ? [image] : pieces
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard naturalSize.width > 0, bounds.width > 0 else { return }
    if bounds.size != lastBounds {
      lastBounds = bounds.size
      // 适应窗口显示，不放大小图（与 Web 端相同：图片的 1 像素按 1 点计）
      let fit = min(bounds.width / naturalSize.width, bounds.height / naturalSize.height, 1)
      fittedSize = CGSize(width: naturalSize.width * fit, height: naturalSize.height * fit)
      zoomScale = 1
      container.frame = CGRect(origin: .zero, size: fittedSize)
      for stripe in stripes {
        stripe.view.frame = CGRect(
          x: 0, y: stripe.top * fittedSize.height, width: fittedSize.width, height: stripe.height * fittedSize.height)
      }
      contentSize = fittedSize
      minimumZoomScale = 1
      maximumZoomScale = max(3, 1 / fit)
    }
    center()
  }

  /// 内容比窗口小时居中
  private func center() {
    let content = container.frame.size
    let horizontal = max(0, (bounds.width - content.width) / 2)
    let vertical = max(0, (bounds.height - content.height) / 2)
    contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    container
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    center()
  }

  @objc private func singleTapped() {
    onSingleTap?()
  }

  @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
    if zoomScale > minimumZoomScale + 0.01 {
      setZoomScale(minimumZoomScale, animated: true)
      return
    }
    guard fittedSize.width > 0 else { return }
    let fit = fittedSize.width / naturalSize.width
    // 长图（条漫）：放大到撑满宽度，从顶部开始，之后拖动往下看
    if fittedSize.width < bounds.width * 0.6 {
      let scale = min(maximumZoomScale, bounds.width / fittedSize.width)
      zoom(to: CGRect(x: 0, y: 0, width: fittedSize.width, height: bounds.height / scale), animated: true)
      return
    }
    let scale = fit < 0.4 ? min(1 / fit, 4) : 2.5
    let point = gesture.location(in: container)
    let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
    zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
  }
}
