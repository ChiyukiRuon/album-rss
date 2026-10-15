/*
 * 封面尺寸测量。真实订阅里绝大多数图片没有宽高，瀑布流采用“先测量再入列”：
 * 卡片在拿到尺寸（或等待超时）之后才放进布局，放下以后不再因为图片加载而移动。
 */
import { isDemoUrl } from '../prototype/art'
import { createStore } from './createStore'
import { whenImageSrc } from './imageSource'

export type ProbeResult =
  { kind: 'size'; width: number; height: number } | { kind: 'error' } | { kind: 'timeout' }

/** 等待尺寸的上限；超时的卡片按固定比例放置，图片到达后在框内裁切显示 */
export const PROBE_TIMEOUT_MS = 3000
/**
 * 同时测量的图片数上限，按列表顺序排队：一面墙不会一下子向同一个图片服务
 * （例如 Miniflux 的 /proxy/）发出几十个请求。等待上限从请求测量时算起，
 * 排队期间超时的直接放弃，由卡片自己加载图片。演示图片不经过网络，不排队。
 */
const MAX_PROBES = 6
const queue: { settled: () => boolean; start: () => void }[] = []
let running = 0

function pump() {
  while (running < MAX_PROBES && queue.length > 0) {
    const task = queue.shift()!
    if (task.settled()) continue
    running++
    task.start()
  }
}

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
  let counted = false
  const settle = (result: ProbeResult) => {
    if (settled) return
    settled = true
    inflight.delete(url)
    results.set(url, result)
    bump()
    if (counted) {
      running--
      pump()
    }
  }
  const timer = window.setTimeout(() => settle({ kind: 'timeout' }), PROBE_TIMEOUT_MS)
  // 超时只结束等待，已经开始的加载继续，之后卡片里直接用缓存
  const load = () =>
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
  if (isDemoUrl(url)) {
    load()
    return
  }
  queue.push({
    settled: () => settled,
    start: () => {
      counted = true
      load()
    },
  })
  pump()
}
