// @vitest-environment jsdom
import { flushSync } from 'react-dom'
import { createRoot } from 'react-dom/client'
import { expect, it, vi } from 'vitest'
import { Stage } from './Stage'

it('视频手动播放后通知已读，失败时提供视频和原文入口', () => {
  const container = document.createElement('div')
  const root = createRoot(container)
  const onShown = vi.fn()
  try {
    flushSync(() =>
      root.render(
        <Stage
          image={{
            key: 'video',
            url: 'https://example.com/video.mp4',
            kind: 'video',
            poster: 'https://example.com/poster.jpg',
          }}
          entryUrl="https://example.com/article"
          onShown={onShown}
          onPrev={vi.fn()}
          onNext={vi.fn()}
          onDismiss={vi.fn()}
          onTap={vi.fn()}
        />,
      ),
    )
    const video = container.querySelector('video')!
    expect(video).not.toBeNull()
    expect(video.controls).toBe(true)
    expect(video.autoplay).toBe(false)
    expect(video.preload).toBe('metadata')
    expect(video.poster).toBe('https://example.com/poster.jpg')
    expect(onShown).not.toHaveBeenCalled()
    video.dispatchEvent(new Event('playing'))
    expect(onShown).toHaveBeenCalledOnce()
    flushSync(() => video.dispatchEvent(new Event('error')))
    expect(container.querySelector('video')).toBeNull()
    expect(Array.from(container.querySelectorAll('a')).map((link) => link.href)).toEqual([
      'https://example.com/video.mp4',
      'https://example.com/article',
    ])
  } finally {
    flushSync(() => root.unmount())
  }
})

it('允许自动播放时尝试播放，被浏览器拦截后仍可手动播放', async () => {
  const { actions } = await import('../../prototype/store')
  const play = vi
    .spyOn(HTMLMediaElement.prototype, 'play')
    .mockRejectedValue(new DOMException('blocked', 'NotAllowedError'))
  const pause = vi.spyOn(HTMLMediaElement.prototype, 'pause').mockImplementation(() => {})
  const container = document.createElement('div')
  const root = createRoot(container)
  actions.updateSettings({ videoAutoplay: true, videoAutoplayCellular: true })
  try {
    flushSync(() =>
      root.render(
        <Stage
          image={{ key: 'v', url: 'https://example.com/v.mp4', kind: 'video' }}
          entryUrl="https://example.com/article"
          onShown={vi.fn()}
          onPrev={vi.fn()}
          onNext={vi.fn()}
          onDismiss={vi.fn()}
          onTap={vi.fn()}
        />,
      ),
    )
    await Promise.resolve()
    expect(play).toHaveBeenCalledOnce()
    expect(container.querySelector('video')?.controls).toBe(true)
    expect(container.querySelector('[role="alert"]')).toBeNull()
    flushSync(() => actions.updateSettings({ videoAutoplay: false }))
    expect(pause).toHaveBeenCalledOnce()
  } finally {
    flushSync(() => root.unmount())
    actions.updateSettings({ videoAutoplay: false, videoAutoplayCellular: false })
    vi.restoreAllMocks()
  }
})

it.each(['loop', 'pause', 'nextGroup'] as const)('播放结束行为：%s', async (videoEndBehavior) => {
  const { actions } = await import('../../prototype/store')
  const container = document.createElement('div')
  const root = createRoot(container)
  const onNext = vi.fn()
  const onNextGroup = vi.fn()
  actions.updateSettings({ videoAutoplay: false, videoEndBehavior })
  try {
    flushSync(() =>
      root.render(
        <Stage
          image={{ key: 'v', url: 'https://example.com/v.mp4', kind: 'video' }}
          entryUrl="https://example.com/article"
          onShown={vi.fn()}
          onPrev={vi.fn()}
          onNext={onNext}
          onNextGroup={onNextGroup}
          onDismiss={vi.fn()}
          onTap={vi.fn()}
        />,
      ),
    )
    const video = container.querySelector('video')!
    expect(video.loop).toBe(videoEndBehavior === 'loop')
    video.dispatchEvent(new Event('ended'))
    expect(onNext).not.toHaveBeenCalled()
    expect(onNextGroup).toHaveBeenCalledTimes(videoEndBehavior === 'nextGroup' ? 1 : 0)
  } finally {
    flushSync(() => root.unmount())
    actions.updateSettings({ videoEndBehavior: 'pause' })
  }
})
