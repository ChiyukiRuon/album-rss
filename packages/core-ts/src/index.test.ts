import { describe, expect, it } from 'vitest'
import { CORE_PACKAGE } from './index'

describe('@album-rss/core', () => {
  it('exposes its package name', () => {
    expect(CORE_PACKAGE).toBe('@album-rss/core')
  })
})
