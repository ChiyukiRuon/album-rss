/*
 * 封面尺寸测量。真实订阅里绝大多数图片没有宽高，瀑布流采用“先测量再入列”：
 * 卡片在拿到尺寸（或等待超时）之后才放进布局，放下以后不再因为图片加载而移动。
 */
import { createStore } from './createStore'
import { whenImageSrc } from './imageSource'

export type ProbeResult =
  { kind: 'size'; width: number; height: number } | { kind: 'error' } | { kind: 'timeout' }

/** 等待尺寸的上限；超时的卡片按固定比例放置，图片到达后在框内裁切显示 */
export const PROBE_TIMEOUT_MS = 3000

const results = new Map<string, ProbeResult>()
const inflight = new Set<string>()
/** 任何地方加载成功后记下的真实尺寸，查看器缩放等处可以复用 */
const loadedSizes = new Map<string, { width: number; height: number }>()

/** 测量结果变化的版本号；同一帧内的多次完成合并为一次通知 */
export const probeVersion = createStore(0)
let bumpScheduled = false
function bump() {
  if (bumpScheduled) return
  bumpScheduled = true
  requestAnimationFrame(() => {
    bumpScheduled = false
    probeVersion.set((v) => v + 1)
  })
}

export function getProbe(url: string): ProbeResult | undefined {
  return results.get(url)
}

export function getLoadedSize(url: string) {
  return loadedSizes.get(url)
}

export function recordLoadedSize(url: string, width: number, height: number) {
  if (width > 0 && height > 0) loadedSizes.set(url, { width, height })
}

export function probe(url: string) {
  if (results.has(url) || inflight.has(url)) return
  inflight.add(url)
  let settled = false
  const settle = (result: ProbeResult) => {
    if (settled) return
    settled = true
    inflight.delete(url)
    results.set(url, result)
    bump()
  }
  const timer = window.setTimeout(() => settle({ kind: 'timeout' }), PROBE_TIMEOUT_MS)
  void whenImageSrc(url).then((src) => {
    const image = new Image()
    image.decoding = 'async'
    image.onload = () => {
      window.clearTimeout(timer)
      recordLoadedSize(url, image.naturalWidth, image.naturalHeight)
      settle({ kind: 'size', width: image.naturalWidth, height: image.naturalHeight })
    }
    image.onerror = () => {
      window.clearTimeout(timer)
      settle({ kind: 'error' })
    }
    image.src = src
  })
}
