import { useCallback, useMemo, useState } from 'react'
import { appStore, useApp, type AppState } from './store'
import type { Entry, Feed, Folder, ListStatus } from './types'

export interface ListQuery {
  status: ListStatus | 'starred'
  feedId?: string
  folderId?: string
}

export function hasImages(entry: Entry): boolean {
  return entry.parseState === 'ready' && entry.images.length > 0
}

function selectIds(state: AppState, query: ListQuery): string[] {
  const pending = new Set(state.sync.pendingIds)
  const inFolder = query.folderId
    ? new Set(state.feeds.filter((f) => f.folderIds.includes(query.folderId!)).map((f) => f.id))
    : null
  return state.order.filter((id) => {
    const entry = state.entries[id]
    if (!entry || pending.has(id)) return false
    if (query.feedId && entry.feedId !== query.feedId) return false
    if (inFolder && !inFolder.has(entry.feedId)) return false
    if (query.status === 'unread' && entry.read) return false
    if (query.status === 'starred' && !entry.starred) return false
    return hasImages(entry) || state.settings.showImageless
  })
}

/**
 * 列表快照：只在筛选条件变化或显式刷新时重新取数。
 * 查看器里标为已读或取消收藏的文章不会立刻从列表消失，列表也就不会跳动。
 */
export function useListSnapshot(query: ListQuery): string[] {
  const listVersion = useApp((s) => s.listVersion)
  const showImageless = useApp((s) => s.settings.showImageless)
  const key = [query.status, query.feedId, query.folderId, showImageless, listVersion].join('|')
  const [snapshot, setSnapshot] = useState(() => ({ key, ids: selectIds(appStore.get(), query) }))
  if (snapshot.key !== key) {
    const next = { key, ids: selectIds(appStore.get(), query) }
    setSnapshot(next)
    return next.ids
  }
  return snapshot.ids
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

/** 未读计数按当前“是否显示无图文章”的设置统计，和列表里看到的一致 */
export function useUnreadCounts(): UnreadCounts {
  const entries = useApp((s) => s.entries)
  const feeds = useApp((s) => s.feeds)
  const showImageless = useApp((s) => s.settings.showImageless)
  return useMemo(() => {
    const byFeed: Record<string, number> = {}
    let total = 0
    for (const entry of Object.values(entries)) {
      if (entry.read || !(hasImages(entry) || showImageless)) continue
      byFeed[entry.feedId] = (byFeed[entry.feedId] ?? 0) + 1
      total++
    }
    const byFolder: Record<string, number> = {}
    for (const feed of feeds) {
      for (const folderId of feed.folderIds) {
        byFolder[folderId] = (byFolder[folderId] ?? 0) + (byFeed[feed.id] ?? 0)
      }
    }
    return { total, byFeed, byFolder }
  }, [entries, feeds, showImageless])
}
