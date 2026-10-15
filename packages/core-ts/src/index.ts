export const CORE_PACKAGE = '@album-rss/core'

export type ServiceKind = 'miniflux' | 'greader'

export interface Folder {
  id: string
  title: string
}

export interface Feed {
  id: string
  title: string
  author: string
  siteUrl: string
  iconUrl: string
  folderIds: string[]
  checkedAt: number
  parsingErrorCount: number
  parsingError?: string
}

export interface ImageAsset {
  key: string
  url: string
  width?: number
  height?: number
  alt?: string
}

export type ImageParseState = 'ready' | 'none' | 'pending'

export interface Entry {
  id: string
  feedId: string
  title: string
  author: string
  url: string
  publishedAt: number
  paragraphs: string[]
  tags: string[]
  images: ImageAsset[]
  parseState: ImageParseState
  read: boolean
  starred: boolean
}

export interface RemoteEntry extends Omit<Entry, 'images' | 'paragraphs' | 'parseState'> {
  content: string
  enclosures: { url: string; mimeType: string }[]
}

export interface Subscriptions {
  folders: Folder[]
  feeds: Feed[]
}

/** 文章列表的查询范围；不带条件即全部订阅的全部文章 */
export interface EntryScope {
  feedId?: string
  folderId?: string
  unread?: boolean
  starred?: boolean
}

/** 一页文章，新的在前；cursor 为 null 表示已经到底 */
export interface EntryPage {
  entries: RemoteEntry[]
  cursor: string | null
}

export function httpUrl(value: string, base?: string): string {
  if (!value.trim()) return ''
  try {
    const url = new URL(value, base)
    return /^https?:$/.test(url.protocol) && !url.username && !url.password ? url.href : ''
  } catch {
    return ''
  }
}
