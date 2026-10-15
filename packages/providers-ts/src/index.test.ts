import { describe, expect, it } from 'vitest'
import { PROVIDERS_DEPENDS_ON } from './index'

describe('@album-rss/providers', () => {
  it('resolves @album-rss/core through the workspace', () => {
    expect(PROVIDERS_DEPENDS_ON).toEqual(['@album-rss/core'])
  })
})
