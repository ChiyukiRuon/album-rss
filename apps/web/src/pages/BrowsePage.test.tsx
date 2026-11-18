// @vitest-environment jsdom
import { flushSync } from 'react-dom'
import { createRoot } from 'react-dom/client'
import { MemoryRouter } from 'react-router'
import { expect, it, vi } from 'vitest'
import { hasImages } from '../prototype/selectors'
import { appStore } from '../prototype/store'
import { BrowsePage } from './BrowsePage'

vi.mock('../components/page/PageHeader', () => ({ PageHeader: () => null }))
vi.mock('../components/masonry/Masonry', () => ({
  Masonry: ({ items }: { items: unknown[] }) => <div>显示 {items.length} 个图集</div>,
}))

it('空的未读列表直接显示新图集，已有图集时保留新内容提示', () => {
  const original = appStore.get()
  const entry = Object.values(original.entries).find(hasImages)!
  const container = document.createElement('div')
  const root = createRoot(container)
  try {
    appStore.set(() => ({ ...original, entries: {}, order: [] }))
    flushSync(() =>
      root.render(
        <MemoryRouter>
          <BrowsePage />
        </MemoryRouter>,
      ),
    )
    const arrive = (id: string) =>
      flushSync(() =>
        appStore.set((state) => ({
          ...state,
          entries: { ...state.entries, [id]: { ...entry, id, read: false } },
          order: [id, ...state.order],
          sync: { ...state.sync, pendingIds: [id] },
        })),
      )
    expect(container.textContent).toContain('没有未读的订阅')
    arrive('first')
    expect(container.textContent).toContain('显示 1 个图集')
    expect(appStore.get().sync.pendingIds).toEqual([])
    arrive('second')
    expect(container.textContent).toContain('显示 1 个图集')
    expect(container.textContent).toContain('1 个新图集')
  } finally {
    flushSync(() => root.unmount())
    appStore.set(() => original)
  }
})
