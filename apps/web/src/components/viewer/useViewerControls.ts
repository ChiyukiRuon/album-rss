import { useLocation, useNavigate, type Location } from 'react-router'
import { actions } from '../../prototype/store'
import { heroClose, heroOpen } from './heroTransition'

interface ViewerHistoryState {
  /** 查看器是从列表里点开的：关闭时退回上一条历史，而不是再压入一条 */
  viewer?: boolean
}

export const VIEW_PARAM = 'view'
export const INDEX_PARAM = 'i'

export function withoutViewerParams(search: string): string {
  const params = new URLSearchParams(search)
  params.delete(VIEW_PARAM)
  params.delete(INDEX_PARAM)
  const rest = params.toString()
  return rest ? `?${rest}` : ''
}

function target(location: Location, entryId: string | null, index = 0) {
  const params = new URLSearchParams(location.search)
  if (entryId) {
    params.set(VIEW_PARAM, entryId)
    params.set(INDEX_PARAM, String(index))
  } else {
    params.delete(VIEW_PARAM)
    params.delete(INDEX_PARAM)
  }
  const search = params.toString()
  return { pathname: location.pathname, search: search ? `?${search}` : '' }
}

/**
 * 查看器的地址是当前列表加上 ?view=文章&i=序号：
 * 列表保持挂载、滚动位置不丢；浏览器的返回键可以关闭查看器。
 * 打开时压入一条历史，翻页只替换当前这一条。
 */
export function useViewerControls() {
  const navigate = useNavigate()
  const location = useLocation()
  const state = location.state as ViewerHistoryState | null

  return {
    hrefFor(entryId: string, index: number) {
      const to = target(location, entryId, index)
      return to.pathname + to.search
    },

    open(entryId: string, index: number, sequence: string[], from: HTMLImageElement | null) {
      actions.setViewerSequence(sequence)
      heroOpen(from, () =>
        navigate(target(location, entryId, index), {
          preventScrollReset: true,
          flushSync: true,
          state: { viewer: true } satisfies ViewerHistoryState,
        }),
      )
    },

    go(entryId: string, index: number) {
      void navigate(target(location, entryId, index), {
        replace: true,
        preventScrollReset: true,
        state,
      })
    },

    close(entryId: string, index: number) {
      const update = () =>
        state?.viewer
          ? navigate(-1)
          : navigate(target(location, null), {
              replace: true,
              preventScrollReset: true,
              flushSync: true,
            })
      heroClose([`${entryId}:${index}`, entryId], update)
    },
  }
}
