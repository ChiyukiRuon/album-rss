import { httpUrl } from '@album-rss/core'
import { createGate } from '@album-rss/providers'

const gate = createGate()
const cache = new Map<string, { until: number; result: Promise<string> }>()

export function parseFeedAvatar(xml: string, base: string): string {
  const doc = new DOMParser().parseFromString(xml, 'application/xml')
  const node =
    doc.querySelector('rss > channel > image > url, feed > logo') ??
    doc.querySelector('feed > icon')
  return httpUrl(node?.textContent?.trim() ?? '', base)
}

export function loadFeedAvatar(source: string): Promise<string> {
  const now = Date.now()
  const cached = cache.get(source)
  if (cached && cached.until > now) return cached.result
  for (const [key, entry] of cache) if (entry.until <= now) cache.delete(key)
  const result = gate
    .run(async () => {
      const response = await fetch(source, {
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
        signal: AbortSignal.timeout(10_000),
      })
      return response.ok ? parseFeedAvatar(await response.text(), response.url || source) : ''
    })
    .catch(() => '')
  cache.set(source, { until: now + 15 * 60_000, result })
  return result
}
