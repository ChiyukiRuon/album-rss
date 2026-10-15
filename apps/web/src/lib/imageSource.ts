/*
 * 图片加载地址与演示资源。真实数据的代理地址在 parseEntry 中映射。
 */
import { useCallback, useSyncExternalStore } from 'react'
import { isDemoUrl, renderDemoUrl } from '../prototype/art'
import { hashString } from '../prototype/random'

const ready = new Map<string, string>()
const started = new Set<string>()
const waiting = new Map<string, Set<() => void>>()
let latencyEnabled: () => boolean = () => false

export function configureLatency(enabled: () => boolean) {
  latencyEnabled = enabled
}

/** 按地址固定的耗时：多数很快，少数较慢，约 4% 超过尺寸测量的等待上限 */
function demoDelay(url: string): number {
  const roll = (hashString(url) % 1000) / 1000
  if (roll < 0.04) return 4200 + roll * 20000
  if (roll < 0.3) return 700 + roll * 3000
  return 120 + roll * 900
}

export function getImageSrc(url: string): string | undefined {
  return isDemoUrl(url) ? ready.get(url) : url
}

function requestImageSrc(url: string) {
  if (!isDemoUrl(url) || ready.has(url) || started.has(url)) return
  started.add(url)
  const finish = () => {
    ready.set(url, renderDemoUrl(url))
    started.delete(url)
    const listeners = waiting.get(url)
    waiting.delete(url)
    listeners?.forEach((listener) => listener())
  }
  if (latencyEnabled()) window.setTimeout(finish, demoDelay(url))
  else finish()
}

function subscribeImageSrc(url: string, listener: () => void) {
  let listeners = waiting.get(url)
  if (!listeners) {
    listeners = new Set()
    waiting.set(url, listeners)
  }
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function whenImageSrc(url: string): Promise<string> {
  const src = getImageSrc(url)
  if (src) return Promise.resolve(src)
  return new Promise((resolve) => {
    const off = subscribeImageSrc(url, () => {
      off()
      resolve(getImageSrc(url) ?? '')
    })
    requestImageSrc(url)
  })
}

/** 返回可交给 img 的地址；尚未就绪时返回 undefined */
export function useImageSrc(url: string | undefined): string | undefined {
  const subscribe = useCallback(
    (listener: () => void) => {
      if (!url) return () => {}
      const off = subscribeImageSrc(url, listener)
      requestImageSrc(url)
      return off
    },
    [url],
  )
  return useSyncExternalStore(subscribe, () => (url ? getImageSrc(url) : undefined))
}

/** 在新标签页打开原图。演示图片转成 blob 地址打开，真实地址不带来源信息 */
export async function openImage(url: string) {
  if (!isDemoUrl(url)) {
    window.open(url, '_blank', 'noopener,noreferrer')
    return
  }
  const tab = window.open('', '_blank')
  const src = await whenImageSrc(url)
  const svg = src.startsWith('data:image/svg+xml')
    ? decodeURIComponent(src.slice(src.indexOf(',') + 1))
    : ''
  const blob = new Blob([svg], { type: 'image/svg+xml' })
  if (tab) tab.location.href = URL.createObjectURL(blob)
}
