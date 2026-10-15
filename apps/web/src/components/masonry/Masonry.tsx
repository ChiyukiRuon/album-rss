import {
  useCallback,
  useEffect,
  useRef,
  useState,
  useSyncExternalStore,
  type CSSProperties,
  type ReactNode,
} from 'react'
import { getProbe, probe, probeVersion } from '../../lib/imageProbe'
import type { Density, ImageAsset } from '../../prototype/types'
import { Tone } from '../tone/Tone'
import {
  displayRatio,
  extendPlacement,
  FALLBACK_RATIO,
  placeTiles,
  wallMetrics,
  type DisplayRatio,
  type Placement,
} from './layout'
import styles from './Masonry.module.css'

export interface TileInfo extends DisplayRatio {
  width: number
  mediaHeight: number
  /** 尺寸测量时图片就加载失败了 */
  failed: boolean
  /** 在列表中的位置（从 1 开始），按文章顺序而不是放置顺序 */
  position: number
}

interface MasonryProps<T> {
  items: readonly T[]
  getKey: (item: T) => string
  /** 返回封面图；null 表示没有图片的文字卡片 */
  getCover: (item: T) => ImageAsset | null
  renderTile: (item: T, info: TileInfo) => ReactNode
  /** 换成另一份列表时改变它；分页追加时保持不变，已放下的卡片位置也就不变 */
  layoutKey: unknown
  density: Density
  hasMore: boolean
  onLoadMore: () => void
  /** 查看器当前停留的卡片：列表在后台跟随滚动，关闭查看器时它就在眼前 */
  focusKey?: string | null
  label: string
}

type ResolvedTile = DisplayRatio & { failed: boolean }

const TEXT_TILE: ResolvedTile = { ratio: 1.05, long: false, cropped: false, failed: false }
const SKELETON_RATIOS = [1.333, 1.5, 1, 1.25, 1.6, 1.414, 1.12, 1.78]

// 返回列表时先按上次的宽度排版，滚动位置才能在第一帧恢复
let lastWidth = 0

function resolveTile(cover: ImageAsset | null): ResolvedTile | null {
  if (!cover) return TEXT_TILE
  if (cover.width && cover.height)
    return { ...displayRatio(cover.width, cover.height), failed: false }
  const result = getProbe(cover.url)
  if (!result) return null
  if (result.kind === 'size') return { ...displayRatio(result.width, result.height), failed: false }
  return { ratio: FALLBACK_RATIO, long: false, cropped: true, failed: result.kind === 'error' }
}

interface ViewportSnapshot {
  /** 视口在列表坐标系中的上下边界，按 160px 分档，滚动时不必每帧重新渲染 */
  top: number
  bottom: number
  height: number
}

function createViewport() {
  const BUCKET = 160
  let element: HTMLElement | null = null
  let snapshot: ViewportSnapshot = { top: 0, bottom: 1600, height: 900 }
  const listeners = new Set<() => void>()
  let frame = 0
  const measure = () => {
    frame = 0
    if (!element) return
    const rect = element.getBoundingClientRect()
    const height = window.innerHeight
    const top = Math.floor(-rect.top / BUCKET) * BUCKET
    const bottom = Math.ceil((height - rect.top) / BUCKET) * BUCKET
    if (top !== snapshot.top || bottom !== snapshot.bottom || height !== snapshot.height) {
      snapshot = { top, bottom, height }
      listeners.forEach((listener) => listener())
    }
  }
  const schedule = () => {
    if (!frame) frame = requestAnimationFrame(measure)
  }
  return {
    attach(node: HTMLElement | null) {
      element = node
      if (node) schedule()
    },
    subscribe(listener: () => void) {
      listeners.add(listener)
      if (listeners.size === 1) {
        window.addEventListener('scroll', schedule, { passive: true })
        window.addEventListener('resize', schedule)
      }
      schedule()
      return () => {
        listeners.delete(listener)
        if (listeners.size > 0) return
        window.removeEventListener('scroll', schedule)
        window.removeEventListener('resize', schedule)
        cancelAnimationFrame(frame)
        frame = 0
      }
    },
    getSnapshot: () => snapshot,
    schedule,
  }
}

export function Masonry<T>({
  items,
  getKey,
  getCover,
  renderTile,
  layoutKey,
  density,
  hasMore,
  onLoadMore,
  focusKey,
  label,
}: MasonryProps<T>) {
  const [viewport] = useState(createViewport)
  const view = useSyncExternalStore(viewport.subscribe, viewport.getSnapshot)
  const [width, setWidth] = useState(lastWidth)
  const [placement, setPlacement] = useState<{ layoutKey: unknown; keys: readonly string[] }>({
    layoutKey,
    keys: [],
  })
  const elementRef = useRef<HTMLDivElement | null>(null)
  // 尺寸测量完成时重新排版
  probeVersion.use((v) => v)

  const attach = useCallback(
    (node: HTMLDivElement | null) => {
      if (!node) return
      elementRef.current = node
      viewport.attach(node)
      const observer = new ResizeObserver(([entry]) => {
        if (!entry) return
        const next = Math.round(entry.contentRect.width)
        lastWidth = next
        setWidth(next)
        viewport.schedule()
      })
      observer.observe(node)
      return () => {
        observer.disconnect()
        viewport.attach(null)
        elementRef.current = null
      }
    },
    [viewport],
  )

  const metrics = wallMetrics(width, density)
  const windowSize = metrics.columns * 3
  const keys = items.map(getKey)
  const indexByKey = new Map(keys.map((key, index) => [key, index]))

  // 先测量再入列：拿到尺寸（或等待超时）的卡片才放进布局，放下后不再移动
  const previous = placement.layoutKey === layoutKey ? placement.keys : []
  const placedKeys = extendPlacement(
    previous.filter((key) => indexByKey.has(key)),
    keys,
    (index) => {
      const item = items[index]
      return item !== undefined && resolveTile(getCover(item)) !== null
    },
    windowSize,
  )
  if (placement.layoutKey !== layoutKey || placedKeys.length !== placement.keys.length) {
    setPlacement({ layoutKey, keys: placedKeys })
  }

  const placedItems: { item: T; index: number; tile: ResolvedTile }[] = []
  for (const key of placedKeys) {
    const index = indexByKey.get(key)
    const item = index === undefined ? undefined : items[index]
    const tile = item === undefined ? null : resolveTile(getCover(item))
    if (item !== undefined && index !== undefined && tile) placedItems.push({ item, index, tile })
  }

  const { placements, columnHeights } = placeTiles(
    placedItems.map((p) => p.tile.ratio),
    metrics,
  )
  const placedBottom = Math.max(0, ...columnHeights) - metrics.gap
  const placedSet = new Set(placedKeys)
  const firstUnplaced = keys.findIndex((key) => !placedSet.has(key))
  const allPlaced = firstUnplaced === -1
  const waiting = !allPlaced || hasMore
  const skeleton = waiting
    ? placeTiles(
        Array.from(
          { length: metrics.columns * 2 },
          (_, i) => SKELETON_RATIOS[i % SKELETON_RATIOS.length] ?? 1,
        ),
        metrics,
        columnHeights,
      )
    : null
  const contentHeight = Math.max(
    0,
    Math.max(0, ...(skeleton ?? { columnHeights }).columnHeights) - metrics.gap,
  )

  const focusIndex = focusKey ? (indexByKey.get(focusKey) ?? -1) : -1
  const nearEnd = placedBottom - view.bottom < view.height * 1.5

  // 测量：接近底部时为后面几行开始测量；查看器跳到更远的位置时一直测到那里
  useEffect(() => {
    if (firstUnplaced === -1) return
    const target = Math.max(
      firstUnplaced + (nearEnd ? windowSize + metrics.columns : 1),
      focusIndex >= 0 ? focusIndex + metrics.columns * 2 : 0,
    )
    for (let i = firstUnplaced; i < Math.min(items.length, target); i++) {
      const item = items[i]
      const cover = item === undefined ? null : getCover(item)
      if (cover && !(cover.width && cover.height)) probe(cover.url)
    }
  }, [firstUnplaced, items, getCover, nearEnd, focusIndex, windowSize, metrics.columns])

  // 已放下的卡片接近视口底部时追加下一页
  useEffect(() => {
    if (allPlaced && hasMore && nearEnd) onLoadMore()
  }, [allPlaced, hasMore, nearEnd, onLoadMore])

  // 跟随查看器：目标卡片不在视口内时，直接把它滚到视口上部
  const focusSlot = focusKey ? placedKeys.indexOf(focusKey) : -1
  const focusPlacement: Placement | undefined = focusSlot >= 0 ? placements[focusSlot] : undefined
  const focusY = focusPlacement?.y
  const focusHeight = focusPlacement?.height
  useEffect(() => {
    const element = elementRef.current
    if (!element || focusY === undefined || focusHeight === undefined) return
    const top = element.getBoundingClientRect().top + window.scrollY + focusY
    const visibleTop = window.scrollY + 96
    const visibleBottom = window.scrollY + window.innerHeight
    if (top >= visibleTop && top + focusHeight <= visibleBottom) return
    window.scrollTo({ top: Math.max(0, top - window.innerHeight * 0.22), behavior: 'instant' })
  }, [focusKey, focusY, focusHeight])

  const top = view.top - view.height
  const bottom = view.bottom + view.height
  const wallStyle = {
    height: contentHeight,
    '--card-footer': `${metrics.footer}px`,
  } as CSSProperties

  return (
    <div
      ref={attach}
      className={styles.wall}
      style={wallStyle}
      role="feed"
      aria-label={label}
      aria-busy={waiting}
    >
      {width > 0 &&
        placements.map((placement, slot) => {
          if (placement.y + placement.height < top || placement.y > bottom) return null
          const placed = placedItems[slot]
          if (!placed) return null
          return (
            <div key={getKey(placed.item)} className={styles.slot} style={slotStyle(placement)}>
              {renderTile(placed.item, {
                ...placed.tile,
                width: placement.width,
                mediaHeight: placement.mediaHeight,
                position: placed.index + 1,
              })}
            </div>
          )
        })}
      {width > 0 &&
        skeleton?.placements.map((placement, index) =>
          placement.y > bottom ? null : (
            <div key={`skeleton-${index}`} className={styles.slot} style={slotStyle(placement)}>
              <Tone
                loading
                className={styles.skeletonMedia}
                style={{ height: placement.mediaHeight }}
              />
              <div className={styles.skeletonFooter} aria-hidden>
                <span className={styles.skeletonAvatar} />
                <span className={styles.skeletonLine} />
              </div>
            </div>
          ),
        )}
    </div>
  )
}

function slotStyle(placement: Placement): CSSProperties {
  return {
    width: placement.width,
    height: placement.height,
    transform: `translate(${placement.x}px, ${placement.y}px)`,
  }
}
