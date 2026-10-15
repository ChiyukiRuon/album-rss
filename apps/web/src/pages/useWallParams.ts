import { useSearchParams } from 'react-router'
import { INDEX_PARAM, VIEW_PARAM } from '../components/viewer/useViewerControls'
import { useApp } from '../prototype/store'
import type { ListStatus, WallMode } from '../prototype/types'

/** 列表的筛选条件放在地址里：可以前进后退、刷新后保留 */
export function useWallParams() {
  const [params, setParams] = useSearchParams()
  const defaultStatus = useApp((s) => s.settings.defaultStatus)
  const statusParam = params.get('status')
  const status: ListStatus =
    statusParam === 'all' || statusParam === 'unread' ? statusParam : defaultStatus
  const mode: WallMode = params.get('mode') === 'images' ? 'images' : 'albums'
  const folderId = params.get('folder') ?? undefined

  const update = (patch: Record<string, string | null>) =>
    setParams(
      (current) => {
        const next = new URLSearchParams(current)
        for (const [key, value] of Object.entries(patch)) {
          if (value === null) next.delete(key)
          else next.set(key, value)
        }
        next.delete(VIEW_PARAM)
        next.delete(INDEX_PARAM)
        return next
      },
      { replace: true },
    )

  return { status, mode, folderId, update }
}
