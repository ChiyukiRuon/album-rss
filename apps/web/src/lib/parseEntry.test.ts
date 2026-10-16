// @vitest-environment jsdom
import type { RemoteEntry } from '@album-rss/core'
import { describe, expect, it } from 'vitest'
import { parseEntry } from './parseEntry'

interface MediaCase {
  name: string
  input: {
    content: string
    url: string
    server: string
    mediaOrigin?: string | null
    enclosures?: { url: string; mimeType: string }[]
  }
  expected: {
    images: {
      url: string
      width?: number
      height?: number
      alt?: string
      kind?: string
      poster?: string
    }[]
    paragraphs: string[]
  }
}

// 与 Swift 端的 EntryParserTests 读取同一组跨端样例，保证两端对同一正文的提取结果一致
const files = import.meta.glob<{ cases: MediaCase[] }>(
  '../../../../contracts/fixtures/media/*.json',
  {
    eager: true,
    import: 'default',
  },
)
const cases = Object.values(files).flatMap((file) => file.cases)

describe('parseEntry 跨端样例', () => {
  it('读取到 contracts/fixtures/media 下的样例', () => {
    expect(cases.length).toBeGreaterThanOrEqual(15)
  })

  it.each(cases.map((fixture) => [fixture.name, fixture] as const))('%s', (_, fixture) => {
    const remote: RemoteEntry = {
      id: '1',
      feedId: 'f',
      title: 'Title',
      author: '',
      url: fixture.input.url,
      publishedAt: 0,
      content: fixture.input.content,
      enclosures: fixture.input.enclosures ?? [],
      tags: [],
      read: false,
      starred: false,
    }
    const entry = parseEntry(remote, fixture.input.server, fixture.input.mediaOrigin ?? undefined)
    expect(
      entry.images.map(({ url, width, height, alt, kind, poster }) => ({
        url,
        width,
        height,
        alt,
        kind,
        poster,
      })),
    ).toEqual(fixture.expected.images)
    expect(entry.images.every((image) => image.key === image.url)).toBe(true)
    expect(entry.paragraphs).toEqual(fixture.expected.paragraphs)
    expect(entry.parseState).toBe(fixture.expected.images.length ? 'ready' : 'none')
  })
})
