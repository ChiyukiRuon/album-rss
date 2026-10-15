import { describe, expect, it } from 'vitest'
import {
  displayRatio,
  extendPlacement,
  MAX_RATIO,
  MIN_RATIO,
  placeTiles,
  wallMetrics,
} from './layout'

describe('wallMetrics', () => {
  it('窄屏按密度固定列数', () => {
    expect(wallMetrics(375, 'compact').columns).toBe(3)
    expect(wallMetrics(375, 'standard').columns).toBe(2)
    expect(wallMetrics(375, 'roomy').columns).toBe(1)
  })

  it('宽屏按目标列宽计算，至少两列', () => {
    expect(wallMetrics(1136, 'standard').columns).toBe(5)
    expect(wallMetrics(620, 'roomy').columns).toBe(2)
  })

  it('列宽加间距正好铺满容器', () => {
    const m = wallMetrics(1136, 'standard')
    expect(m.columnWidth * m.columns + m.gap * (m.columns - 1)).toBeCloseTo(1136)
  })
})

describe('displayRatio', () => {
  it('普通比例原样保留', () => {
    expect(displayRatio(2000, 3000)).toEqual({ ratio: 1.5, long: false, cropped: false })
  })

  it('长图限高并标记', () => {
    const r = displayRatio(1000, 5000)
    expect(r.ratio).toBe(MAX_RATIO)
    expect(r.long).toBe(true)
    expect(r.cropped).toBe(true)
  })

  it('很宽的图压到最小比例，但不算长图', () => {
    const r = displayRatio(3000, 1000)
    expect(r.ratio).toBe(MIN_RATIO)
    expect(r.long).toBe(false)
    expect(r.cropped).toBe(true)
  })
})

describe('placeTiles', () => {
  const metrics = { columns: 2, gap: 10, footer: 20, columnWidth: 100 }

  it('依次放进最矮的一列，高度相同时靠左', () => {
    const { placements, columnHeights } = placeTiles([1, 2, 1], metrics)
    expect(placements.map((p) => [p.x, p.y])).toEqual([
      [0, 0],
      [110, 0],
      [0, 130],
    ])
    expect(placements[1]?.height).toBe(220)
    expect(columnHeights).toEqual([260, 230])
  })

  it('可以从已有的列高继续排', () => {
    const { placements } = placeTiles([1], metrics, [300, 50])
    expect(placements[0]).toMatchObject({ x: 110, y: 50 })
  })
})

describe('extendPlacement', () => {
  const keys = ['a', 'b', 'c', 'd', 'e', 'f']

  it('窗口内谁先就绪谁先放下，慢的那张不挡住后面', () => {
    const ready = new Set([1, 2])
    expect(extendPlacement([], keys, (i) => ready.has(i), 4)).toEqual(['b', 'c'])
  })

  it('不越过窗口', () => {
    const ready = new Set([4, 5])
    expect(extendPlacement([], keys, (i) => ready.has(i), 4)).toEqual([])
  })

  it('慢的那张就绪后接在已放下的后面，已放下的顺序不变', () => {
    const placed = ['b', 'c']
    const next = extendPlacement(placed, keys, (i) => i <= 3, 4)
    expect(next).toEqual(['b', 'c', 'a', 'd'])
  })

  it('没有新卡片时返回原数组', () => {
    const placed = ['a']
    expect(extendPlacement(placed, keys, () => false, 4)).toBe(placed)
  })
})
