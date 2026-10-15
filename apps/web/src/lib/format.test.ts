import { describe, expect, it } from 'vitest'
import { relativeTime, siteName } from './format'

describe('relativeTime', () => {
  const now = new Date(2026, 9, 15, 14, 30).getTime()
  const at = (...args: [number, number, number, number, number]) => new Date(...args).getTime()

  it('一分钟内是“刚刚”', () => {
    expect(relativeTime(now - 20_000, now)).toBe('刚刚')
  })

  it('一小时内按分钟，今天按小时', () => {
    expect(relativeTime(now - 5 * 60_000, now)).toBe('5 分钟前')
    expect(relativeTime(at(2026, 9, 15, 9, 0), now)).toBe('5 小时前')
  })

  it('昨天带时刻，今年带月日，更早带年份', () => {
    expect(relativeTime(at(2026, 9, 14, 21, 4), now)).toBe('昨天 21:04')
    expect(relativeTime(at(2026, 2, 3, 8, 0), now)).toBe('3月3日')
    expect(relativeTime(at(2025, 9, 3, 8, 0), now)).toBe('2025年10月3日')
  })
})

describe('siteName', () => {
  it('取主机名并去掉 www.', () => {
    expect(siteName('https://www.pixiv.net/users/1')).toBe('pixiv.net')
    expect(siteName('https://space.bilibili.com/2/dynamic')).toBe('space.bilibili.com')
  })

  it('地址为空或无效时返回空字符串', () => {
    expect(siteName('')).toBe('')
    expect(siteName('not a url')).toBe('')
  })
})
