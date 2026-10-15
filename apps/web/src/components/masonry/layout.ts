import type { Density } from '../../prototype/types'

/** 高宽比超过它的图按长图处理：限高、从顶部裁切并标“长图” */
export const MAX_RATIO = 1.8
/** 很宽的图最多压到 2:1，左右裁切 */
export const MIN_RATIO = 0.5
/** 尺寸测量超时或失败时使用的占位比例 */
export const FALLBACK_RATIO = 4 / 3

export interface WallMetrics {
  columns: number
  gap: number
  /** 卡片下方作者行的高度 */
  footer: number
  columnWidth: number
}

const TARGET_COLUMN: Record<Density, number> = { compact: 168, standard: 208, roomy: 288 }
const NARROW_COLUMNS: Record<Density, number> = { compact: 3, standard: 2, roomy: 1 }

export function wallMetrics(width: number, density: Density): WallMetrics {
  const narrow = width < 600
  const gap = narrow ? 8 : 16
  const footer = narrow ? 38 : 44
  const columns = narrow
    ? NARROW_COLUMNS[density]
    : Math.max(2, Math.floor((width + gap) / (TARGET_COLUMN[density] + gap)))
  const columnWidth = Math.max(0, (width - gap * (columns - 1)) / columns)
  return { columns, gap, footer, columnWidth }
}

export interface DisplayRatio {
  /** 显示用的高宽比，已限制在 MIN_RATIO 与 MAX_RATIO 之间 */
  ratio: number
  /** 原图比显示框更长，从顶部裁切 */
  long: boolean
  /** 显示框与原图比例不同，需要 object-fit: cover */
  cropped: boolean
}

export function displayRatio(width: number, height: number): DisplayRatio {
  const raw = height / width
  const ratio = Math.min(MAX_RATIO, Math.max(MIN_RATIO, raw))
  return { ratio, long: raw > MAX_RATIO, cropped: ratio !== raw }
}

export interface Placement {
  x: number
  y: number
  width: number
  height: number
  mediaHeight: number
}

/** 依次放进当前最矮的一列；高度相同时靠左。结果只取决于输入，便于测试 */
export function placeTiles(
  ratios: readonly number[],
  metrics: WallMetrics,
  start?: number[],
): { placements: Placement[]; columnHeights: number[] } {
  const { columns, gap, footer, columnWidth } = metrics
  const heights = start ? [...start] : new Array<number>(columns).fill(0)
  const placements = ratios.map((ratio) => {
    let column = 0
    for (let c = 1; c < columns; c++) {
      if ((heights[c] ?? 0) < (heights[column] ?? 0) - 0.5) column = c
    }
    const y = heights[column] ?? 0
    const mediaHeight = Math.round(columnWidth * ratio)
    const height = mediaHeight + footer
    heights[column] = y + height + gap
    return { x: column * (columnWidth + gap), y, width: columnWidth, height, mediaHeight }
  })
  return { placements, columnHeights: heights }
}

/**
 * 入列顺序：在第一张还没放下的卡片之后的一个窗口内，谁先测量完谁先放下。
 * 一张慢图不会挡住后面所有卡片，乱序也不会超过一个窗口；已经放下的卡片顺序不再改变。
 * 没有新卡片可放时返回原数组，调用方可以据此判断是否需要更新。
 */
export function extendPlacement(
  placed: readonly string[],
  keys: readonly string[],
  isReady: (index: number) => boolean,
  windowSize: number,
): readonly string[] {
  const placedSet = new Set(placed)
  const first = keys.findIndex((key) => !placedSet.has(key))
  if (first === -1) return placed
  const additions: string[] = []
  const end = Math.min(keys.length, first + windowSize)
  for (let i = first; i < end; i++) {
    const key = keys[i]
    if (key !== undefined && !placedSet.has(key) && isReady(i)) additions.push(key)
  }
  return additions.length > 0 ? [...placed, ...additions] : placed
}
