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

export interface Session {
  id?: string
  name?: string
  kind: 'demo' | 'connected'
  service: ServiceKind
  server: string
  username: string
  /** 是否在浏览器中记住登录；否则只保存在内存里 */
  remember: boolean
  token?: string
  mediaOrigin?: string
}

export type DownloadStatus = 'running' | 'done' | 'blocked'

export interface DownloadState {
  status: DownloadStatus
  done: number
  total: number
}
