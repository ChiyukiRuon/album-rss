// @vitest-environment jsdom
import type { Feed } from '@album-rss/core'
import { flushSync } from 'react-dom'
import { createRoot } from 'react-dom/client'
import { expect, it, vi } from 'vitest'
import { Avatar } from './Avatar'

vi.mock('../../lib/feedAvatar', () => ({
  loadFeedAvatar: async () => 'https://example.org/original.jpg',
}))

it('保留首字和服务图标，直到原始头像加载成功', async () => {
  const container = document.createElement('div')
  const root = createRoot(container)
  const feed: Feed = {
    id: '1',
    title: '摄影',
    author: '摄影',
    siteUrl: '',
    iconUrl: 'https://example.org/icon.png',
    feedUrl: 'https://example.org/rss',
    folderIds: [],
    checkedAt: 0,
    parsingErrorCount: 0,
  }
  try {
    flushSync(() => root.render(<Avatar feed={feed} name={feed.title} />))
    const service = container.querySelector('img')!
    expect(container.textContent).toBe('摄')
    expect(service.style.opacity).toBe('0')
    flushSync(() => service.dispatchEvent(new Event('load')))
    await vi.waitFor(() => expect(container.querySelectorAll('img')).toHaveLength(2))
    const original = container.querySelectorAll('img')[1]!
    expect(service.style.opacity).toBe('1')
    expect(original.style.opacity).toBe('0')
    flushSync(() => original.dispatchEvent(new Event('error')))
    expect(service.style.opacity).toBe('1')
    expect(original.style.opacity).toBe('0')
    flushSync(() => original.dispatchEvent(new Event('load')))
    expect(original.style.opacity).toBe('1')
  } finally {
    flushSync(() => root.unmount())
  }
})
