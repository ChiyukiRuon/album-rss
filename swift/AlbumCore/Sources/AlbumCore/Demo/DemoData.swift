import Foundation

/// 演示数据：本地按种子生成，不访问任何服务器。移植自 Web 端 `prototype/demoData.ts`，
/// 生成顺序与随机数调用一一对应，两端看到的画师、标题和图片比例相同。
/// 画师名与链接都是虚构的，链接指向 example.com。
public enum DemoContent {
  /// 演示端点的“服务地址”。.invalid 是保留域名：图片由 App 在本地绘制，不会真的发出请求
  public static let server = "https://demo.album-rss.invalid"
  public static let host = "demo.album-rss.invalid"

  public enum Palette: String, CaseIterable, Sendable {
    case dusk, sea, citrus, ink, sakura, autumn, night, mint
  }

  static func artURL(_ palette: Palette, seed: Int, width: Int, height: Int) -> String {
    "\(server)/art/\(palette.rawValue)/\(seed)/\(width)x\(height)"
  }

  /// 一个注定加载失败的地址，用来展示“加载失败”状态
  static func brokenURL(_ seed: Int) -> String {
    "\(server)/broken/\(seed)"
  }

  enum Platform {
    case pixiv, x, bilibili
  }

  enum Style {
    case illust, manga, strip
  }

  struct FeedSeed {
    var id: String
    var author: String
    var handle: String
    var platform: Platform
    var palette: Palette
    var folderIds: [String]
    var style: Style
    var count: Int
    var parsingError: String?
  }

  static let folders = [Folder(id: "illust", title: "插画"), Folder(id: "comic", title: "漫画")]

  static let seeds: [FeedSeed] = [
    FeedSeed(id: "1", author: "柚木ほたる", handle: "hotaru", platform: .pixiv, palette: .dusk, folderIds: ["illust"], style: .illust, count: 18),
    FeedSeed(id: "2", author: "Mori Kanae", handle: "mori_kanae", platform: .x, palette: .sea, folderIds: ["illust"], style: .illust, count: 16),
    FeedSeed(id: "3", author: "青柠汽水", handle: "qingning", platform: .bilibili, palette: .citrus, folderIds: ["illust"], style: .illust, count: 14),
    FeedSeed(id: "4", author: "kuroneko_ink", handle: "kuroneko_ink", platform: .x, palette: .ink, folderIds: ["comic"], style: .manga, count: 12),
    FeedSeed(id: "5", author: "白鷺ゆず", handle: "yuzu", platform: .pixiv, palette: .sakura, folderIds: ["illust"], style: .illust, count: 16),
    FeedSeed(id: "6", author: "阿栗Ari", handle: "ari", platform: .bilibili, palette: .autumn, folderIds: ["comic"], style: .strip, count: 10),
    FeedSeed(
      id: "7", author: "Hoshino Tsumugi", handle: "tsumugi", platform: .pixiv, palette: .night, folderIds: ["illust"],
      style: .illust, count: 14, parsingError: "抓取超时：订阅源在 30 秒内没有响应"),
    FeedSeed(id: "8", author: "灯里Akari", handle: "akari", platform: .x, palette: .mint, folderIds: ["illust"], style: .illust, count: 15),
  ]

  static func titles(_ platform: Platform) -> [String] {
    switch platform {
    case .pixiv:
      ["夏の終わり", "おやすみ", "らくがき", "雨の日", "君と花火", "練習", "冬服", "放課後", "ひとやすみ", "星を数えて", "春眠", "海辺にて",
       "新刊サンプル", "金魚", "夜更かし", "青い鳥", "ただいま", "透明"]
    case .x:
      ["new drawing ✨", "wip — lighting is hard", "commission for a friend, thank you!!", "🌙", "sketch dump from this week",
       "Finally finished this one after two weeks. I tried a new brush set and I think it shows? Let me know what you think!",
       "happy birthday to my favorite girl 🎂", "落書き", "color study", "redraw of a piece from 2021 — growth!",
       "quick doodle before bed", "thank you for 20k!!"]
    case .bilibili:
      ["百日绘 Day 42 / 晚霞", "新年贺图！祝大家新年快乐", "练习 · 光影", "约稿完成啦，感谢老板", "【原创】夏天的尾巴", "日常摸鱼",
       "过程分享：从草稿到上色", "画了喜欢的角色", "雨天", "百日绘 Day 43 / 柠檬汽水"]
    }
  }

  static let stripTitles = ["条漫｜周末的猫", "条漫｜搬家记", "条漫｜第一次养花", "条漫｜下雨天不想出门", "条漫｜便利店的夜班"]
  static let mangaTitles = [
    "short comic: the umbrella", "page 1–4", "little comic about my cat", "ネーム供養", "4コマ", "oneshot preview",
  ]

  static func sentences(_ platform: Platform) -> [String] {
    switch platform {
    case .pixiv:
      ["いつもありがとうございます。", "久しぶりの投稿です。", "色塗りを少し変えてみました。", "次の新刊に収録予定です。", "リクエストありがとうございました！"]
    case .x:
      ["Prints will be available at the next event.", "Process video is up on my page.",
       "Thank you all for the kind words last time!", "Trying out a softer palette this month."]
    case .bilibili:
      ["这张画了三个晚上，主要在练光影。", "欢迎在评论区说说想看什么角色。", "原图在动态里，可以点开看大图。", "下次直播会分享上色过程。"]
    }
  }

  static func tagPool(_ platform: Platform) -> [String] {
    switch platform {
    case .pixiv: ["オリジナル", "女の子", "風景", "創作", "落書き", "制服", "夏", "星空", "和服"]
    case .x: []
    case .bilibili: ["百日绘", "原创", "绘画", "插画", "日常"]
    }
  }

  static let ratios: [(Double, Double)] = [
    (1.5, 30), (1.333, 20), (1.414, 15), (1.25, 10), (1, 8), (1.778, 8), (0.5625, 6), (0.75, 6), (2.6, 2), (3.4, 1),
  ]
  static let widths = [1200, 1600, 2048, 2400, 2894, 3508]
  static let hour: TimeInterval = 3600

  struct Generated {
    var folders: [Folder]
    var feeds: [Feed]
    var entries: [Entry]
    /// 尚未“同步到”的新文章：刷新或后台同步时依次加入
    var arrivals: [Entry]
  }

  static func generate(now: Date) -> Generated {
    var rng = Mulberry32(seed: 20_261_015)
    let feeds = seeds.enumerated().map { index, seed in feed(seed, index: index, now: now, rng: &rng) }
    var entries: [Entry] = []
    var nextID = 1000
    for seed in seeds {
      for i in 0..<seed.count {
        let age = hour * (Double(i) * rng.between(6, 20) + rng.between(0.2, 5))
        entries.append(entry(&rng, seed, id: String(nextID), publishedAt: now.addingTimeInterval(-age), position: i))
        nextID += 1
      }
    }
    addSpecialCases(&rng, &entries, firstID: nextID, now: now)
    nextID += 10
    entries.sort { $0.publishedAt > $1.publishedAt }
    ensureStarred(&entries, &rng)
    var arrivals: [Entry] = []
    let healthy = seeds.filter { $0.parsingError == nil }
    for _ in 0..<6 {
      let seed = rng.pick(healthy)
      var arrival = entry(&rng, seed, id: String(nextID), publishedAt: now, position: 0)
      nextID += 1
      arrival.read = false
      arrival.starred = false
      arrivals.append(arrival)
    }
    return Generated(folders: folders, feeds: feeds, entries: entries, arrivals: arrivals)
  }

  private static func feed(_ seed: FeedSeed, index: Int, now: Date, rng: inout Mulberry32) -> Feed {
    let platformName = seed.platform == .pixiv ? "pixiv" : "bilibili"
    let title = seed.platform == .x ? "Twitter @\(seed.handle)" : "\(seed.author) 的 \(platformName) 动态"
    return Feed(
      id: seed.id,
      title: title,
      author: seed.author,
      siteURL: "https://example.com/\(platformPath(seed.platform))/\(seed.handle)",
      iconURL: artURL(seed.palette, seed: 9000 + index * 17, width: 160, height: 160),
      folderIds: seed.folderIds,
      checkedAt: now.addingTimeInterval(-hour * rng.between(0.1, 3)),
      parsingErrorCount: seed.parsingError == nil ? 0 : 3,
      parsingError: seed.parsingError
    )
  }

  private static func platformPath(_ platform: Platform) -> String {
    switch platform {
    case .pixiv: "pixiv"
    case .x: "x"
    case .bilibili: "bilibili"
    }
  }

  private static func entry(_ rng: inout Mulberry32, _ seed: FeedSeed, id: String, publishedAt: Date, position: Int)
    -> Entry
  {
    let images = makeImages(&rng, seed, entrySeed: Int(id) ?? 0)
    let title: String
    switch seed.style {
    case .strip: title = rng.next() < 0.6 ? rng.pick(stripTitles) : rng.pick(titles(.bilibili))
    case .manga: title = rng.pick(mangaTitles)
    case .illust: title = rng.pick(titles(seed.platform))
    }
    let sentenceCount = seed.platform == .x ? rng.intBetween(0, 1) : rng.intBetween(1, 3)
    var paragraphs: [String] = []
    for _ in 0..<sentenceCount {
      let sentence = rng.pick(sentences(seed.platform))
      if !paragraphs.contains(sentence) { paragraphs.append(sentence) }
    }
    let pool = tagPool(seed.platform)
    var tags: [String] = []
    if !pool.isEmpty {
      for _ in 0..<rng.intBetween(1, 4) {
        let tag = rng.pick(pool)
        if !tags.contains(tag) { tags.append(tag) }
      }
    }
    // 较新的文章大多未读，旧文章约一半已读
    let read = position > 3 && rng.next() < 0.55
    let starred = rng.next() < 0.06
    return Entry(
      id: id,
      feedId: seed.id,
      title: title,
      author: seed.author,
      url: "https://example.com/\(platformPath(seed.platform))/\(seed.handle)/\(id)",
      publishedAt: publishedAt,
      paragraphs: paragraphs,
      tags: tags,
      images: images,
      parseState: .ready,
      read: read,
      starred: starred
    )
  }

  private static func makeImages(_ rng: inout Mulberry32, _ seed: FeedSeed, entrySeed: Int) -> [ImageAsset] {
    var images: [ImageAsset] = []
    func push(_ ratio: Double, _ index: Int, _ rng: inout Mulberry32) {
      let width = rng.pick(widths)
      let height = Int((Double(width) * ratio + 0.5).rounded(.down))
      let known = rng.next() < 0.1
      images.append(
        ImageAsset(
          key: "\(entrySeed)-\(index)",
          url: artURL(seed.palette, seed: entrySeed * 31 + index, width: width, height: height),
          width: known ? Double(width) : nil,
          height: known ? Double(height) : nil
        ))
    }
    switch seed.style {
    case .manga:
      let five = rng.intBetween(5, 12)
      let pages = rng.weighted([(1, 3), (4, 4), (five, 3)])
      for i in 0..<pages { push(1.414, i, &rng) }
      return images
    case .strip:
      let few = rng.intBetween(2, 4)
      let parts = rng.weighted([(1, 5), (few, 3)])
      for i in 0..<parts {
        let ratio = rng.between(3, 5.5)
        push(ratio, i, &rng)
      }
      return images
    case .illust:
      let five = rng.intBetween(5, 8)
      let nine = rng.intBetween(9, 18)
      let count = rng.weighted([(1, 58), (2, 12), (3, 10), (4, 8), (five, 8), (nine, 4)])
      let ratio = rng.weighted(ratios)
      for i in 0..<count {
        // 同一组图通常比例一致，偶尔混入不同比例
        let mixed = rng.next() < 0.8 ? ratio : rng.weighted(ratios)
        push(mixed, i, &rng)
      }
      return images
    }
  }

  /// 无图文章、加载失败的图片：几种状态必须能区分
  private static func addSpecialCases(_ rng: inout Mulberry32, _ entries: inout [Entry], firstID: Int, now: Date) {
    func seedOf(_ id: String) -> FeedSeed { seeds.first { $0.id == id }! }
    func base(_ feedID: String, _ id: Int, _ hoursAgo: Double, _ rng: inout Mulberry32) -> Entry {
      var made = entry(&rng, seedOf(feedID), id: String(id), publishedAt: now.addingTimeInterval(-hoursAgo * hour), position: 0)
      made.read = false
      return made
    }
    var lottery = base("3", firstID, 7, &rng)
    lottery.title = "抽奖结果公布！谢谢大家参与"
    lottery.paragraphs = ["中奖的朋友请在一周内私信地址。没抽中的也别灰心，下个月还有。"]
    lottery.images = []
    lottery.parseState = .none
    entries.append(lottery)

    var thanks = base("2", firstID + 1, 30, &rng)
    thanks.title = "Thanks for 20k followers! Giveaway details next week, stay tuned."
    thanks.paragraphs = []
    thanks.images = []
    thanks.parseState = .none
    entries.append(thanks)

    var notice = base("5", firstID + 2, 3, &rng)
    notice.title = "お知らせ：しばらく更新をお休みします"
    notice.images = []
    notice.parseState = .none
    entries.append(notice)

    var coverBroken = base("8", firstID + 3, 5, &rng)
    coverBroken.images = [ImageAsset(key: "\(firstID + 3)-b", url: brokenURL(1))] + coverBroken.images
    entries.append(coverBroken)

    var midBroken = base("1", firstID + 4, 11, &rng)
    midBroken.images += [ImageAsset(key: "\(firstID + 4)-b", url: brokenURL(2))]
    midBroken.images += makeImages(&rng, seedOf("1"), entrySeed: (firstID + 4) * 7)
    entries.append(midBroken)
  }

  private static func ensureStarred(_ entries: inout [Entry], _ rng: inout Mulberry32) {
    let withImages = entries.indices.filter { !entries[$0].images.isEmpty }
    var starred = withImages.filter { entries[$0].starred }.count
    while starred < 8 {
      let index = rng.pick(withImages)
      if !entries[index].starred {
        entries[index].starred = true
        starred += 1
      }
    }
  }
}
