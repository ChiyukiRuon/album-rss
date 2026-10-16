import { httpUrl, type Entry, type ImageAsset, type RemoteEntry } from '@album-rss/core'

export function mediaUrl(
  value: string,
  base: string,
  server: string,
  mediaOrigin?: string,
): string {
  const resolved = httpUrl(value, base)
  if (!resolved) return ''
  const url = new URL(resolved)
  if (
    mediaOrigin &&
    url.origin === new URL(mediaOrigin).origin &&
    url.pathname.startsWith('/proxy/')
  ) {
    const target = new URL(server)
    return target.origin + target.pathname.replace(/\/$/, '') + url.pathname + url.search
  }
  return resolved
}

function srcset(value: string | null): string {
  return (
    (value ?? '')
      .split(',')
      .map((item) => {
        const [url = '', size = '0'] = item.trim().split(/\s+/)
        return { url, size: Number.parseFloat(size) || 0 }
      })
      .sort((a, b) => b.size - a.size)[0]?.url ?? ''
  )
}

export function parseEntry(remote: RemoteEntry, server: string, mediaOrigin?: string): Entry {
  // 脱离页面的 template 不执行正文，文章 HTML 不会进入实际页面。
  const template = document.createElement('template')
  template.innerHTML = remote.content
  const root = template.content
  root
    .querySelectorAll('script,style,iframe,object,embed,svg,noscript')
    .forEach((node) => node.remove())
  const images: ImageAsset[] = []
  const seen = new Set<string>()
  const add = (
    value: string,
    width?: number,
    height?: number,
    alt?: string,
    kind?: 'video',
    poster?: string,
  ) => {
    const url = mediaUrl(value, remote.url || server, server, mediaOrigin)
    if (
      !url ||
      seen.has(url) ||
      (width !== undefined && height !== undefined && width <= 2 && height <= 2)
    )
      return
    seen.add(url)
    images.push({ key: url, url, width, height, alt, kind, poster })
  }
  const dimension = (value: string | null) => {
    const n = Number(value)
    return Number.isFinite(n) && n > 0 ? n : undefined
  }
  root.querySelectorAll('img,video').forEach((image) => {
    if (image.tagName === 'VIDEO') {
      const candidates = [
        image.getAttribute('src'),
        image.getAttribute('data-src'),
        ...Array.from(image.querySelectorAll('source')).map((source) => source.getAttribute('src')),
      ]
      const value = candidates.find(
        (value) => value && mediaUrl(value, remote.url || server, server, mediaOrigin),
      )
      if (value)
        add(
          value,
          dimension(image.getAttribute('width')),
          dimension(image.getAttribute('height')),
          undefined,
          'video',
          mediaUrl(image.getAttribute('poster') ?? '', remote.url || server, server, mediaOrigin) ||
            undefined,
        )
      return
    }
    const source = image.closest('picture')?.querySelector('source[srcset]')
    const value =
      image.getAttribute('data-original') ||
      image.getAttribute('data-src') ||
      image.getAttribute('data-lazy-src') ||
      srcset(image.getAttribute('data-srcset')) ||
      srcset(image.getAttribute('srcset')) ||
      srcset(source?.getAttribute('srcset') ?? null) ||
      image.getAttribute('src') ||
      ''
    add(
      value,
      dimension(image.getAttribute('width')),
      dimension(image.getAttribute('height')),
      image.getAttribute('alt') ||
        image.closest('figure')?.querySelector('figcaption')?.textContent ||
        undefined,
    )
  })
  for (const attachment of remote.enclosures) {
    if (attachment.mimeType?.toLowerCase().startsWith('image/')) add(attachment.url)
    if (attachment.mimeType?.toLowerCase().startsWith('video/'))
      add(attachment.url, undefined, undefined, undefined, 'video')
  }
  root.querySelectorAll('br').forEach((node) => node.replaceWith('\n'))
  root
    .querySelectorAll('p,div,li,blockquote,h1,h2,h3,figcaption')
    .forEach((node) => node.append('\n'))
  const paragraphs = (root.textContent ?? '')
    .split(/\n+/)
    .map((p) => p.trim())
    .filter(Boolean)
  return {
    id: remote.id,
    feedId: remote.feedId,
    title: remote.title,
    author: remote.author,
    url: remote.url,
    publishedAt: remote.publishedAt,
    read: remote.read,
    starred: remote.starred,
    tags: remote.tags,
    images,
    paragraphs,
    parseState: images.length ? 'ready' : 'none',
  }
}
