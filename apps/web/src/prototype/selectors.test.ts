import { describe, expect, it } from 'vitest'
import { categoryLabel } from './selectors'

describe('categoryLabel', () => {
  const folders = [
    { id: '1', title: '插画' },
    { id: '2', title: '漫画' },
  ]

  it('显示订阅所属分类的名字', () => {
    expect(categoryLabel(['2'], folders)).toBe('漫画')
  })

  it('多个标签用顿号连接，忽略找不到的分类', () => {
    expect(categoryLabel(['1', 'missing', '2'], folders)).toBe('插画、漫画')
  })

  it('没有分类时不显示', () => {
    expect(categoryLabel([], folders)).toBeUndefined()
  })

  it('账号里只有一个分类时不显示', () => {
    expect(categoryLabel(['1'], [{ id: '1', title: 'All' }])).toBeUndefined()
  })
})
