// @vitest-environment jsdom
import { flushSync } from 'react-dom'
import { createRoot } from 'react-dom/client'
import { MemoryRouter } from 'react-router'
import { expect, it } from 'vitest'
import { actions } from '../prototype/store'
import { SettingsPage } from './SettingsPage'

it('主开关控制流量开关显隐，并保留流量选择', () => {
  const container = document.createElement('div')
  const root = createRoot(container)
  const findSwitch = (label: string) =>
    Array.from(container.querySelectorAll<HTMLButtonElement>('[role="switch"]')).find((button) => {
      const id = button.getAttribute('aria-labelledby')
      return Array.from(container.querySelectorAll('[id]')).some(
        (node) => node.id === id && node.textContent === label,
      )
    })
  actions.updateSettings({
    videoAutoplay: false,
    videoAutoplayCellular: false,
    videoEndBehavior: 'pause',
  })
  try {
    flushSync(() =>
      root.render(
        <MemoryRouter>
          <SettingsPage />
        </MemoryRouter>,
      ),
    )
    const nextGroup = Array.from(container.querySelectorAll<HTMLButtonElement>('button')).find(
      (button) => button.textContent === '播完切换',
    )!
    expect(nextGroup).toBeDefined()
    flushSync(() => nextGroup.click())
    expect(JSON.parse(localStorage.getItem('album-rss:settings')!).videoEndBehavior).toBe(
      'nextGroup',
    )
    expect(findSwitch('使用数据流量时自动播放')).toBeUndefined()
    flushSync(() => findSwitch('打开视频时自动播放')!.click())
    expect(findSwitch('使用数据流量时自动播放')?.getAttribute('aria-checked')).toBe('false')
    flushSync(() => findSwitch('使用数据流量时自动播放')!.click())
    flushSync(() => findSwitch('打开视频时自动播放')!.click())
    expect(findSwitch('使用数据流量时自动播放')).toBeUndefined()
    const saved = JSON.parse(localStorage.getItem('album-rss:settings')!)
    expect(saved).toMatchObject({ videoAutoplay: false, videoAutoplayCellular: true })
    flushSync(() => findSwitch('打开视频时自动播放')!.click())
    expect(findSwitch('使用数据流量时自动播放')?.getAttribute('aria-checked')).toBe('true')
  } finally {
    flushSync(() => root.unmount())
    actions.updateSettings({
      videoAutoplay: false,
      videoAutoplayCellular: false,
      videoEndBehavior: 'pause',
    })
  }
})
