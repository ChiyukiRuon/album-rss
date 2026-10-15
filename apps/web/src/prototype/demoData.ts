/*
 * 演示数据。形状参照本地 Miniflux 实测（Pixiv / X / Bilibili 画师订阅）：
 * 大多数图片没有宽高信息、标题长短差异很大、单篇最多十几张图。
 * 画师名与链接都是虚构的，链接指向 example.com。
 * 分类与 Miniflux 一致：每个订阅只属于一个分类。
 */
import { artUrl, brokenUrl, type PaletteName } from './art'
import { between, intBetween, mulberry32, pick, weighted, type Rng } from './random'
import type { Entry, Feed, Folder, ImageAsset } from './types'

/** 只在演示数据内部使用：生成标题、正文和模拟下载结果，不进入界面模型 */
type DemoPlatform = 'pixiv' | 'x' | 'bilibili'

interface FeedSeed {
  id: string
  author: string
  handle: string
  platform: DemoPlatform
  palette: PaletteName
  folderIds: string[]
  style: 'illust' | 'manga' | 'strip'
  count: number
  parsingError?: string
}

const FOLDERS: Folder[] = [
  { id: 'illust', title: '插画' },
  { id: 'comic', title: '漫画' },
]

const FEED_SEEDS: FeedSeed[] = [
  {
    id: '1',
    author: '柚木ほたる',
    handle: 'hotaru',
    platform: 'pixiv',
    palette: 'dusk',
    folderIds: ['illust'],
    style: 'illust',
    count: 18,
  },
  {
    id: '2',
    author: 'Mori Kanae',
    handle: 'mori_kanae',
    platform: 'x',
    palette: 'sea',
    folderIds: ['illust'],
    style: 'illust',
    count: 16,
  },
  {
    id: '3',
    author: '青柠汽水',
    handle: 'qingning',
    platform: 'bilibili',
    palette: 'citrus',
    folderIds: ['illust'],
    style: 'illust',
    count: 14,
  },
  {
    id: '4',
    author: 'kuroneko_ink',
    handle: 'kuroneko_ink',
    platform: 'x',
    palette: 'ink',
    folderIds: ['comic'],
    style: 'manga',
    count: 12,
  },
  {
    id: '5',
    author: '白鷺ゆず',
    handle: 'yuzu',
    platform: 'pixiv',
    palette: 'sakura',
    folderIds: ['illust'],
    style: 'illust',
    count: 16,
  },
  {
    id: '6',
    author: '阿栗Ari',
    handle: 'ari',
    platform: 'bilibili',
    palette: 'autumn',
    folderIds: ['comic'],
    style: 'strip',
    count: 10,
  },
  {
    id: '7',
    author: 'Hoshino Tsumugi',
    handle: 'tsumugi',
    platform: 'pixiv',
    palette: 'night',
    folderIds: ['illust'],
    style: 'illust',
    count: 14,
    parsingError: '抓取超时：订阅源在 30 秒内没有响应',
  },
  {
    id: '8',
    author: '灯里Akari',
    handle: 'akari',
    platform: 'x',
    palette: 'mint',
    folderIds: ['illust'],
    style: 'illust',
    count: 15,
  },
]

const TITLES: Record<DemoPlatform, readonly string[]> = {
  pixiv: [
    '夏の終わり',
    'おやすみ',
    'らくがき',
    '雨の日',
    '君と花火',
    '練習',
    '冬服',
    '放課後',
    'ひとやすみ',
    '星を数えて',
    '春眠',
    '海辺にて',
    '新刊サンプル',
    '金魚',
    '夜更かし',
    '青い鳥',
    'ただいま',
    '透明',
  ],
  x: [
    'new drawing ✨',
    'wip — lighting is hard',
    'commission for a friend, thank you!!',
    '🌙',
    'sketch dump from this week',
    'Finally finished this one after two weeks. I tried a new brush set and I think it shows? Let me know what you think!',
    'happy birthday to my favorite girl 🎂',
    '落書き',
    'color study',
    'redraw of a piece from 2021 — growth!',
    'quick doodle before bed',
    'thank you for 20k!!',
  ],
  bilibili: [
    '百日绘 Day 42 / 晚霞',
    '新年贺图！祝大家新年快乐',
    '练习 · 光影',
    '约稿完成啦，感谢老板',
    '【原创】夏天的尾巴',
    '日常摸鱼',
    '过程分享：从草稿到上色',
    '画了喜欢的角色',
    '雨天',
    '百日绘 Day 43 / 柠檬汽水',
  ],
}

const STRIP_TITLES = [
  '条漫｜周末的猫',
  '条漫｜搬家记',
  '条漫｜第一次养花',
  '条漫｜下雨天不想出门',
  '条漫｜便利店的夜班',
]
const MANGA_TITLES = [
  'short comic: the umbrella',
  'page 1–4',
  'little comic about my cat',
  'ネーム供養',
  '4コマ',
  'oneshot preview',
]

const SENTENCES: Record<DemoPlatform, readonly string[]> = {
  pixiv: [
    'いつもありがとうございます。',
    '久しぶりの投稿です。',
    '色塗りを少し変えてみました。',
    '次の新刊に収録予定です。',
    'リクエストありがとうございました！',
  ],
  x: [
    'Prints will be available at the next event.',
    'Process video is up on my page.',
    'Thank you all for the kind words last time!',
    'Trying out a softer palette this month.',
  ],
  bilibili: [
    '这张画了三个晚上，主要在练光影。',
    '欢迎在评论区说说想看什么角色。',
    '原图在动态里，可以点开看大图。',
    '下次直播会分享上色过程。',
  ],
}

const TAGS: Record<DemoPlatform, readonly string[]> = {
  pixiv: ['オリジナル', '女の子', '風景', '創作', '落書き', '制服', '夏', '星空', '和服'],
  x: [],
  bilibili: ['百日绘', '原创', '绘画', '插画', '日常'],
}

const RATIOS = [
  [1.5, 30],
  [1.333, 20],
  [1.414, 15],
  [1.25, 10],
  [1, 8],
  [1.778, 8],
  [0.5625, 6],
  [0.75, 6],
  [2.6, 2],
  [3.4, 1],
] as const

const WIDTHS = [1200, 1600, 2048, 2400, 2894, 3508] as const

const HOUR = 3_600_000

/** 演示：Bilibili 的图片经 Miniflux 代理，网页无法读取，下载会走“右键 / 长按保存”的分支（与本地实测一致） */
export function demoBlocksDownload(feedId: string): boolean {
  return FEED_SEEDS.find((seed) => seed.id === feedId)?.platform === 'bilibili'
}

export interface DemoData {
  folders: Folder[]
  feeds: Feed[]
  entries: Entry[]
  /** 尚未“同步到”的新文章：刷新或后台同步时依次加入 */
  arrivals: Entry[]
}

export function createDemoData(now: number): DemoData {
  const rng = mulberry32(20261015)
  const feeds = FEED_SEEDS.map((seed, index) => toFeed(seed, index, now, rng))
  const entries: Entry[] = []
  let nextId = 1000

  FEED_SEEDS.forEach((seed) => {
    for (let i = 0; i < seed.count; i++) {
      const age = HOUR * (i * between(rng, 6, 20) + between(rng, 0.2, 5))
      entries.push(makeEntry(rng, seed, String(nextId++), now - age, i))
    }
  })

  addSpecialCases(rng, entries, nextId, now)
  nextId += 10
  entries.sort((a, b) => b.publishedAt - a.publishedAt)
  ensureStarred(entries, rng)

  const arrivals: Entry[] = []
  for (let i = 0; i < 6; i++) {
    const seed = pick(
      rng,
      FEED_SEEDS.filter((s) => !s.parsingError),
    )
    const entry = makeEntry(rng, seed, String(nextId++), now, 0)
    arrivals.push({ ...entry, read: false, starred: false })
  }

  return { folders: FOLDERS, feeds, entries, arrivals }
}

function toFeed(seed: FeedSeed, index: number, now: number, rng: Rng): Feed {
  const title =
    seed.platform === 'x'
      ? `Twitter @${seed.handle}`
      : `${seed.author} 的 ${seed.platform === 'pixiv' ? 'pixiv' : 'bilibili'} 动态`
  return {
    id: seed.id,
    title,
    author: seed.author,
    siteUrl: `https://example.com/${seed.platform}/${seed.handle}`,
    iconUrl: artUrl(seed.palette, 9000 + index * 17, 160, 160),
    folderIds: seed.folderIds,
    checkedAt: now - HOUR * between(rng, 0.1, 3),
    parsingErrorCount: seed.parsingError ? 3 : 0,
    parsingError: seed.parsingError,
  }
}

function makeEntry(
  rng: Rng,
  seed: FeedSeed,
  id: string,
  publishedAt: number,
  position: number,
): Entry {
  const images = makeImages(rng, seed, Number(id))
  const title =
    seed.style === 'strip'
      ? pick(rng, rng() < 0.6 ? STRIP_TITLES : TITLES.bilibili)
      : seed.style === 'manga'
        ? pick(rng, MANGA_TITLES)
        : pick(rng, TITLES[seed.platform])
  const sentenceCount = seed.platform === 'x' ? intBetween(rng, 0, 1) : intBetween(rng, 1, 3)
  const paragraphs = [
    ...new Set(Array.from({ length: sentenceCount }, () => pick(rng, SENTENCES[seed.platform]))),
  ]
  const tagPool = TAGS[seed.platform]
  const tags =
    tagPool.length > 0
      ? Array.from(new Set(Array.from({ length: intBetween(rng, 1, 4) }, () => pick(rng, tagPool))))
      : []
  return {
    id,
    feedId: seed.id,
    title,
    author: seed.author,
    url: `https://example.com/${seed.platform}/${seed.handle}/${id}`,
    publishedAt,
    paragraphs,
    tags,
    images,
    parseState: 'ready',
    // 较新的文章大多未读，旧文章约一半已读
    read: position > 3 && rng() < 0.55,
    starred: rng() < 0.06,
  }
}

function makeImages(rng: Rng, seed: FeedSeed, entrySeed: number): ImageAsset[] {
  const images: ImageAsset[] = []
  const push = (ratio: number, index: number) => {
    const width = pick(rng, WIDTHS)
    const height = Math.round(width * ratio)
    const known = rng() < 0.1
    images.push({
      key: `${entrySeed}-${index}`,
      url: artUrl(seed.palette, entrySeed * 31 + index, width, height),
      width: known ? width : undefined,
      height: known ? height : undefined,
    })
  }

  if (seed.style === 'manga') {
    const pages = weighted(rng, [
      [1, 3],
      [4, 4],
      [intBetween(rng, 5, 12), 3],
    ])
    for (let i = 0; i < pages; i++) push(1.414, i)
    return images
  }
  if (seed.style === 'strip') {
    const parts = weighted(rng, [
      [1, 5],
      [intBetween(rng, 2, 4), 3],
    ])
    for (let i = 0; i < parts; i++) push(between(rng, 3, 5.5), i)
    return images
  }

  const count = weighted(rng, [
    [1, 58],
    [2, 12],
    [3, 10],
    [4, 8],
    [intBetween(rng, 5, 8), 8],
    [intBetween(rng, 9, 18), 4],
  ])
  const ratio = weighted(rng, RATIOS)
  for (let i = 0; i < count; i++) {
    // 同一组图通常比例一致，偶尔混入不同比例
    push(rng() < 0.8 ? ratio : weighted(rng, RATIOS), i)
  }
  return images
}

/** 无图文章、未解析文章、加载失败的图片：三种状态必须能区分 */
function addSpecialCases(rng: Rng, entries: Entry[], firstId: number, now: number) {
  const seedOf = (feedId: string) => {
    const seed = FEED_SEEDS.find((s) => s.id === feedId)
    if (!seed) throw new Error(`unknown feed ${feedId}`)
    return seed
  }
  const base = (feedId: string, id: number, hoursAgo: number) => ({
    ...makeEntry(rng, seedOf(feedId), String(id), now - hoursAgo * HOUR, 0),
    read: false,
  })
  entries.push({
    ...base('3', firstId, 7),
    title: '抽奖结果公布！谢谢大家参与',
    paragraphs: ['中奖的朋友请在一周内私信地址。没抽中的也别灰心，下个月还有。'],
    images: [],
    parseState: 'none',
  })
  entries.push({
    ...base('2', firstId + 1, 30),
    title: 'Thanks for 20k followers! Giveaway details next week, stay tuned.',
    paragraphs: [],
    images: [],
    parseState: 'none',
  })
  entries.push({
    ...base('5', firstId + 2, 3),
    title: 'お知らせ：しばらく更新をお休みします',
    images: [],
    parseState: 'pending',
  })
  const coverBroken = base('8', firstId + 3, 5)
  entries.push({
    ...coverBroken,
    images: [{ key: `${firstId + 3}-b`, url: brokenUrl(1) }, ...coverBroken.images],
  })
  const midBroken = base('1', firstId + 4, 11)
  entries.push({
    ...midBroken,
    images: [
      ...midBroken.images,
      { key: `${firstId + 4}-b`, url: brokenUrl(2) },
      ...makeImages(rng, seedOf('1'), (firstId + 4) * 7),
    ],
  })
}

function ensureStarred(entries: Entry[], rng: Rng) {
  const withImages = entries.filter((e) => e.images.length > 0)
  let starred = withImages.filter((e) => e.starred).length
  while (starred < 8) {
    const entry = pick(rng, withImages)
    if (!entry.starred) {
      entry.starred = true
      starred++
    }
  }
}
