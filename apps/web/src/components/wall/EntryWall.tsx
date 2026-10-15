import { ArrowClockwiseIcon, ArrowDownIcon, WarningCircleIcon } from '@phosphor-icons/react'
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { useSearchParams } from 'react-router'
import { hasImages, useCategoryLabel, useFeedMap, type ScopeList } from '../../prototype/selectors'
import { actions, appStore, useApp } from '../../prototype/store'
import type { Entry, ImageAsset, WallMode } from '../../prototype/types'
import { cardKeyOf } from '../card/cardKey'
import { GalleryCard, type CardTarget } from '../card/GalleryCard'
import { Masonry, type TileInfo } from '../masonry/Masonry'
import { EmptyState } from '../page/EmptyState'
import { Button } from '../ui/Button'
import { INDEX_PARAM, useViewerControls, VIEW_PARAM } from '../viewer/useViewerControls'
import styles from './EntryWall.module.css'

interface EntryWallProps {
  /** 列表快照（见 useScopeList） */
  list: ScopeList
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
/**
 * 连续读到几页都没有可显示的图集（例如订阅里都是无图文章）时，停止自动翻页，
 * 改为让用户点“加载更早的内容”，避免一口气发出大量请求。
 */
const AUTO_PAGES = 3

const getKey = (item: WallItem) => cardKeyOf(item.entry.id, item.index)
const getCover = (item: WallItem): ImageAsset | null => item.entry.images[item.index ?? 0] ?? null

/** 瀑布流列表：分页追加、打开查看器、跟随查看器滚动 */
export function EntryWall({ list, mode, label, dimRead, empty }: EntryWallProps) {
  const { ids, layoutKey, hasMore: remoteMore, loading, error, loadMore } = list
  const entries = useApp((s) => s.entries)
  const density = useApp((s) => s.settings.density)
  const feeds = useFeedMap()
  const categoryOf = useCategoryLabel()
  const viewer = useViewerControls()
  const [params] = useSearchParams()
  const [pages, setPages] = useState(1)
  const [pagedKey, setPagedKey] = useState(layoutKey)

  // 换了一份列表就从第一页开始；追加下一页时保持
  if (pagedKey !== layoutKey) {
    setPagedKey(layoutKey)
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

  // 自上次列表变长以来自动读了几页
  const [stall, setStall] = useState({ length: allItems.length, misses: 0 })
  if (stall.length !== allItems.length) setStall({ length: allItems.length, misses: 0 })
  const autoLoad = stall.misses < AUTO_PAGES

  const viewId = params.get(VIEW_PARAM)
  const viewIndex = Number.parseInt(params.get(INDEX_PARAM) ?? '0', 10) || 0
  const focusKey = viewId ? (mode === 'images' ? cardKeyOf(viewId, viewIndex) : viewId) : null
  const focusPosition = focusKey ? allItems.findIndex((item) => getKey(item) === focusKey) : -1

  // 查看器翻到还没显示的位置时，列表跟着把那一页也显示出来
  const pageSize = PAGE_SIZE[mode]
  const visibleCount = Math.max(pages * pageSize, focusPosition + Math.ceil(pageSize / 2))
  const items = useMemo(() => allItems.slice(0, visibleCount), [allItems, visibleCount])
  const localMore = visibleCount < allItems.length
  const fetchMore = remoteMore && !error && autoLoad

  const onLoadMore = useCallback(() => {
    if (localMore) setPages((n) => n + 1)
    else if (fetchMore && !loading) {
      setStall((current) => ({ ...current, misses: current.misses + 1 }))
      loadMore()
    }
  }, [localMore, fetchMore, loading, loadMore])

  // 查看器翻到已读取部分的末尾时继续读下一页；同样最多连读几页没有新图集的
  const viewerLoads = useRef({ length: -1, count: 0 })
  const nearViewerEnd = focusPosition >= 0 && focusPosition >= allItems.length - 3
  useEffect(() => {
    if (!nearViewerEnd || !remoteMore || error || loading) return
    const tracker = viewerLoads.current
    if (tracker.length !== allItems.length) {
      tracker.length = allItems.length
      tracker.count = 0
    }
    if (tracker.count >= AUTO_PAGES) return
    tracker.count++
    loadMore()
  }, [nearViewerEnd, remoteMore, error, loading, allItems.length, loadMore])

  // 换了列表或展示方式就重新排版；分页追加时保持已放下卡片的位置
  const wallKey = useMemo(() => ({ layoutKey, mode }), [layoutKey, mode])

  const sequence = useMemo(
    () => ids.filter((id) => entries[id] && hasImages(entries[id])),
    [ids, entries],
  )

  // 查看器打开期间读到了下一页：把新文章接到翻页顺序后面
  useEffect(() => {
    if (!focusKey) return
    const current = appStore.get().viewerSequence
    if (current && sequence.length > current.length && current.every((id, i) => sequence[i] === id))
      actions.setViewerSequence(sequence)
  }, [focusKey, sequence])

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

  const retry = () => {
    setStall((current) => ({ ...current, misses: 0 }))
    loadMore()
  }

  if (allItems.length === 0 && !fetchMore && !loading) {
    if (error)
      return (
        <EmptyState
          icon={<WarningCircleIcon aria-hidden />}
          title="没能读取这个列表"
          description={error}
          actions={
            <Button icon={<ArrowClockwiseIcon aria-hidden />} onClick={retry}>
              重试
            </Button>
          }
        />
      )
    if (!remoteMore) return <>{empty}</>
  }

  return (
    <>
      <Masonry
        items={items}
        getKey={getKey}
        getCover={getCover}
        renderTile={renderTile}
        layoutKey={wallKey}
        density={density}
        hasMore={localMore || fetchMore || loading}
        onLoadMore={onLoadMore}
        focusKey={focusKey}
        label={label}
      />
      {!localMore && remoteMore && !loading && (error || !autoLoad) && (
        <div className={styles.more} role={error ? 'alert' : undefined}>
          {error ? (
            <p className={styles.error}>{error}</p>
          ) : (
            allItems.length === 0 && (
              <p className={styles.hint}>最近读取的文章里没有可显示的图集。</p>
            )
          )}
          <Button
            icon={error ? <ArrowClockwiseIcon aria-hidden /> : <ArrowDownIcon aria-hidden />}
            onClick={retry}
          >
            {error ? '重试' : '加载更早的内容'}
          </Button>
        </div>
      )}
    </>
  )
}
