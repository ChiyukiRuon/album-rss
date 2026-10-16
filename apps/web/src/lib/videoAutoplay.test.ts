import { describe, expect, it } from 'vitest'
import { permitsVideoAutoplay } from './videoAutoplay'

describe('视频自动播放网络规则', () => {
  it.each([undefined, 'wifi', 'ethernet', 'cellular', 'unknown', 'none'])(
    '主开关关闭时不自动播放：%s',
    (type) => {
      expect(permitsVideoAutoplay(false, true, type)).toBe(false)
    },
  )
  it.each(['wifi', 'ethernet'])('允许非流量网络：%s', (type) => {
    expect(permitsVideoAutoplay(true, false, type)).toBe(true)
  })
  it.each([undefined, 'cellular', 'unknown', 'bluetooth'])(
    '流量开关关闭时不猜测网络：%s',
    (type) => {
      expect(permitsVideoAutoplay(true, false, type)).toBe(false)
      expect(permitsVideoAutoplay(true, true, type)).toBe(true)
    },
  )
  it('离线时不自动播放', () => {
    expect(permitsVideoAutoplay(true, true, 'none')).toBe(false)
  })
})
