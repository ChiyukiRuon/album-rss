// @vitest-environment jsdom
import { expect, it } from 'vitest'
import { parseFeedAvatar } from './feedAvatar'

const base = 'https://example.org/feeds/gallery.xml'

it('读取频道头像、解析相对地址，忽略文章配图', () => {
  const item = '<item><image><url>article.jpg</url></image></item>'
  expect(
    parseFeedAvatar(
      `<rss><channel>${item}<image><url><![CDATA[../face.jpg?a=1&b=2]]></url></image></channel></rss>`,
      base,
    ),
  ).toBe('https://example.org/face.jpg?a=1&b=2')
  expect(parseFeedAvatar(`<rss><channel>${item}</channel></rss>`, base)).toBe('')
})

it('读取 Atom 的 logo 并拒绝非 HTTP 图片', () => {
  expect(
    parseFeedAvatar(
      '<feed xmlns="http://www.w3.org/2005/Atom"><icon>small</icon><logo>large</logo></feed>',
      base,
    ),
  ).toBe('https://example.org/feeds/large')
  expect(
    parseFeedAvatar('<rss><channel><image><url>file:///face</url></image></channel></rss>', base),
  ).toBe('')
})
