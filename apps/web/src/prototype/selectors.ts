import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  actions,
  appStore,
  queryOfKey,
  retainScope,
  scopeKey,
  useApp,
  type AppState,
} from './store'
import type { Entry, Feed, Folder, ListQuery } from './types'

export function hasImages(entry: Entry): boolean {
  return entry.parseState === 'ready' && entry.images.length > 0
}

function visible(entry: Entry | undefined, query: ListQuery, showImageless: boolean) {
  if (!entry) return false
  if (query.status === 'unread' && entry.read) return false
  if (query.status === 'starred' && !entry.starred) return false
  return hasImages(entry) || showImageless
}

/** 演示数据都在本地：直接从全部文章里筛选，后台同步到的新文章先不放进来 */
function demoIds(state: AppState, query: ListQuery): string[] {
  const pending = new Set(state.sync.pendingIds)
  const inFolder = query.folderId
    ? new Set(state.feeds.filter((f) => f.folderIds.includes(query.folderId!)).map((f) => f.id))
    : null
  return state.order.filter((id) => {
    const entry = state.entries[id]
    if (!entry || pending.has(id)) return false
    if (query.feedId && entry.feedId !== query.feedId) return false
    if (inFolder && !inFolder.has(entry.feedId)) return false
    return visible(entry, query, state.settings.showImageless)
  })
}

export interface ScopeList {
  ids: string[]
  /** 换了一份列表（筛选条件、显式刷新）才变化；追加下一页时不变，瀑布流据此保留已放下的卡片 */
  layoutKey: object
  /** 服务端还有更早的文章 */
  hasMore: boolean
  loading: boolean
  error?: string
  loadMore: () => void
}

/**
 * 列表快照：只在筛选条件变化或显式刷新时重新取数，读到下一页时只在末尾追加。
 * 查看器里标为已读或取消收藏的文章不会立刻从列表消失，列表也就不会跳动。
 * 真实服务按页读取：列表挂载时读第一页，滚到底再读下一页。
 */
export function useScopeList(input: ListQuery): ScopeList {
  const key = scopeKey(input)
  const query = useMemo(() => queryOfKey(key), [key])
  const demo = useApp((s) => s.endpoint?.kind !== 'connected')
  const scope = useApp((s) => s.scopes[key])
  const listVersion = useApp((s) => s.listVersion)
  const showImageless = useApp((s) => s.settings.showImageless)
  const resetKey = [key, showImageless, listVersion, demo].join('|')

  useEffect(() => retainScope(query), [query])
  useEffect(() => {
    if (!demo && !scope) void actions.loadMore(query)
  }, [demo, scope, query])

  const select = () => {
    const state = appStore.get()
    if (demo) return demoIds(state, query)
    return (state.scopes[key]?.ids ?? []).filter((id) =>
      visible(state.entries[id], query, showImageless),
    )
  }
  const [snapshot, setSnapshot] = useState(() => ({
    resetKey,
    source: scope?.ids,
    ids: select(),
    layoutKey: {},
  }))
  let current = snapshot
  if (snapshot.resetKey !== resetKey) {
    current = { resetKey, source: scope?.ids, ids: select(), layoutKey: {} }
    setSnapshot(current)
  } else if (!demo && snapshot.source !== scope?.ids) {
    // 读到了下一页：已有的保持原样，只在末尾补上新文章
    const entries = appStore.get().entries
    const have = new Set(snapshot.ids)
    const added = (scope?.ids ?? []).filter(
      (id) => !have.has(id) && visible(entries[id], query, showImageless),
    )
    current = {
      ...snapshot,
      source: scope?.ids,
      ids: added.length > 0 ? [...snapshot.ids, ...added] : snapshot.ids,
    }
    setSnapshot(current)
  }

  const loadMore = useCallback(() => void actions.loadMore(query), [query])
  return {
    ids: current.ids,
    layoutKey: current.layoutKey,
    hasMore: !demo && !scope?.done,
    loading: !demo && (scope?.loading ?? true),
    error: demo ? undefined : scope?.error,
    loadMore,
  }
}

/**
 * 订阅所属的分类名，来自 RSS 服务（Miniflux 每个订阅一个分类；Google Reader 可能有多个标签）。
 * 账号里不到两个分类时（例如全部在 Miniflux 默认的 All 里）不显示，和分类筛选的规则一致。
 */
export function categoryLabel(
  folderIds: readonly string[],
  folders: readonly Folder[],
): string | undefined {
  if (folders.length < 2) return undefined
  const names = folderIds.flatMap((id) => folders.find((folder) => folder.id === id)?.title ?? [])
  return names.length > 0 ? names.join('、') : undefined
}

export function useCategoryLabel(): (
  feed: Pick<Feed, 'folderIds'> | undefined,
) => string | undefined {
  const folders = useApp((s) => s.folders)
  return useCallback(
    (feed) => (feed ? categoryLabel(feed.folderIds, folders) : undefined),
    [folders],
  )
}

export function useFeedMap(): Map<string, Feed> {
  const feeds = useApp((s) => s.feeds)
  return useMemo(() => new Map(feeds.map((f) => [f.id, f])), [feeds])
}

export interface UnreadCounts {
  total: number
  byFeed: Record<string, number>
  byFolder: Record<string, number>
}

/**
 * 未读计数。服务提供计数接口时用服务端的数字（按文章计，未加载的文章也算在内），
 * 否则按已读取的文章统计，并和列表一样遵循“是否显示无图文章”的设置。
 */
export function useUnreadCounts(): UnreadCounts {
  const entries = useApp((s) => s.entries)
  const feeds = useApp((s) => s.feeds)
  const unread = useApp((s) => s.unread)
  const showImageless = useApp((s) => s.settings.showImageless)
  const local = useMemo(() => {
    if (unread) return null
    const byFeed: Record<string, number> = {}
    for (const entry of Object.values(entries)) {
      if (entry.read || !(hasImages(entry) || showImageless)) continue
      byFeed[entry.feedId] = (byFeed[entry.feedId] ?? 0) + 1
    }
    return byFeed
  }, [entries, unread, showImageless])
  return useMemo(() => {
    const byFeed = unread ?? local ?? {}
    let total = 0
    const byFolder: Record<string, number> = {}
    for (const feed of feeds) {
      const count = byFeed[feed.id] ?? 0
      total += count
      for (const folderId of feed.folderIds) byFolder[folderId] = (byFolder[folderId] ?? 0) + count
    }
    return { total, byFeed, byFolder }
  }, [unread, local, feeds])
}
