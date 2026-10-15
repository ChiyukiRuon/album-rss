import { useCallback, useMemo, useRef, useState, type ReactNode } from 'react'
import { useSearchParams } from 'react-router'
import { hasImages, useCategoryLabel, useFeedMap } from '../../prototype/selectors'
import { useApp } from '../../prototype/store'
import type { Entry, ImageAsset, WallMode } from '../../prototype/types'
import { cardKeyOf } from '../card/cardKey'
import { GalleryCard, type CardTarget } from '../card/GalleryCard'
import { Masonry, type TileInfo } from '../masonry/Masonry'
import { INDEX_PARAM, useViewerControls, VIEW_PARAM } from '../viewer/useViewerControls'

interface EntryWallProps {
  /** 列表快照（见 useListSnapshot） */
  ids: string[]
  mode: WallMode
  label: string
  /** 已读文章在列表里变暗；收藏页不需要 */
  dimRead: boolean
  empty: ReactNode
}

interface WallItem {
  entry: Entry
  /** 单图模式下的图片序号 */
  index: number | null
}

const PAGE_SIZE = { albums: 36, images: 60 }

const getKey = (item: WallItem) => cardKeyOf(item.entry.id, item.index)
const getCover = (item: WallItem): ImageAsset | null => item.entry.images[item.index ?? 0] ?? null

/** 瀑布流列表：分页追加、打开查看器、跟随查看器滚动 */
export function EntryWall({ ids, mode, label, dimRead, empty }: EntryWallProps) {
  const entries = useApp((s) => s.entries)
  const density = useApp((s) => s.settings.density)
  const feeds = useFeedMap()
  const categoryOf = useCategoryLabel()
  const viewer = useViewerControls()
  const [params] = useSearchParams()
  const [pages, setPages] = useState(1)
  const [pagedIds, setPagedIds] = useState(ids)
  const loadingMore = useRef(false)

  // 换了筛选条件就从第一页开始
  if (pagedIds !== ids) {
    setPagedIds(ids)
    setPages(1)
  }

  const allItems = useMemo(() => {
    const items: WallItem[] = []
    for (const id of ids) {
      const entry = entries[id]
      if (!entry) continue
      if (mode === 'albums') items.push({ entry, index: null })
      else entry.images.forEach((_, index) => items.push({ entry, index }))
    }
    return items
  }, [ids, entries, mode])

  const viewId = params.get(VIEW_PARAM)
  const viewIndex = Number.parseInt(params.get(INDEX_PARAM) ?? '0', 10) || 0
  const focusKey = viewId ? (mode === 'images' ? cardKeyOf(viewId, viewIndex) : viewId) : null
  const focusPosition = focusKey ? allItems.findIndex((item) => getKey(item) === focusKey) : -1

  // 查看器翻到还没加载的位置时，列表跟着把那一页也加载进来
  const pageSize = PAGE_SIZE[mode]
  const visibleCount = Math.max(pages * pageSize, focusPosition + Math.ceil(pageSize / 2))
  const items = useMemo(() => allItems.slice(0, visibleCount), [allItems, visibleCount])
  const hasMore = visibleCount < allItems.length

  // 原型里用短暂延迟模拟下一页的读取
  const onLoadMore = useCallback(() => {
    if (loadingMore.current) return
    loadingMore.current = true
    window.setTimeout(() => {
      loadingMore.current = false
      setPages((n) => n + 1)
    }, 450)
  }, [])

  // 换了列表或展示方式就重新排版；分页追加时保持已放下卡片的位置
  const layoutKey = useMemo(() => ({ ids, mode }), [ids, mode])

  const sequence = useMemo(
    () => ids.filter((id) => entries[id] && hasImages(entries[id])),
    [ids, entries],
  )

  const onOpen = useCallback(
    (target: CardTarget, image: HTMLImageElement | null) =>
      viewer.open(target.entry.id, target.index, sequence, image),
    [viewer, sequence],
  )

  const renderTile = (item: WallItem, info: TileInfo) => (
    <GalleryCard
      entry={item.entry}
      feed={feeds.get(item.entry.feedId)}
      category={categoryOf(feeds.get(item.entry.feedId))}
      imageIndex={item.index}
      info={info}
      setSize={allItems.length}
      dimmed={dimRead && item.entry.read}
      href={viewer.hrefFor(item.entry.id, item.index ?? 0)}
      onOpen={onOpen}
    />
  )

  if (allItems.length === 0) return <>{empty}</>

  return (
    <Masonry
      items={items}
      getKey={getKey}
      getCover={getCover}
      renderTile={renderTile}
      layoutKey={layoutKey}
      density={density}
      hasMore={hasMore}
      onLoadMore={onLoadMore}
      focusKey={focusKey}
      label={label}
    />
  )
}
