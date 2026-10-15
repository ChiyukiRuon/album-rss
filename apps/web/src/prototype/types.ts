import type { ServiceKind } from '@album-rss/core'
export type { Entry, Feed, Folder, ImageAsset, ImageParseState, ServiceKind } from '@album-rss/core'

export type Theme = 'system' | 'light' | 'dark'
export type Density = 'compact' | 'standard' | 'roomy'
export type ListStatus = 'unread' | 'all'
export type WallMode = 'albums' | 'images'

export interface Settings {
  /** 进入图集且至少一张图片显示成功后标记已读 */
  autoRead: boolean
  downloadRead: boolean
  /** 显示没有图片或图片待解析的文章 */
  showImageless: boolean
  defaultStatus: ListStatus
  density: Density
  theme: Theme
  /** 演示：模拟图片加载耗时，用来查看占位与测量过程 */
  simulateLatency: boolean
}

/** 一个 API 端点：服务地址与凭据。演示数据也作为一个端点出现 */
export interface Endpoint {
  id: string
  name?: string
  kind: 'demo' | 'connected'
  service: ServiceKind
  server: string
  /** Google Reader 换取令牌用的用户名；Miniflux 为服务返回的用户名 */
  username: string
  /** 是否把凭据保存在这个浏览器里；否则只保存在内存，刷新后移除 */
  remember: boolean
  token?: string
  mediaOrigin?: string
}

/** 一个文章列表的筛选条件 */
export interface ListQuery {
  status: ListStatus | 'starred'
  feedId?: string
  folderId?: string
}

/** 列表在服务端的分页进度 */
export interface ScopeState {
  query: ListQuery
  /** 按服务端顺序读到的文章，只会在末尾追加 */
  ids: string[]
  cursor: string | null
  /** 服务端已经没有更早的文章 */
  done: boolean
  loading: boolean
  error?: string
  /** 重新读取第一页时更换，迟到的旧页据此丢弃 */
  token: number
}

export type DownloadStatus = 'running' | 'done' | 'blocked'

export interface DownloadState {
  status: DownloadStatus
  done: number
  total: number
}
