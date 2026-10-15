import { useEffect } from 'react'
import { Outlet, ScrollRestoration, useSearchParams } from 'react-router'
import { actions, appStore, useApp } from '../../prototype/store'
import { EndpointDialog } from '../endpoint/EndpointDialog'
import { openEndpointDialog } from '../endpoint/endpointDialogStore'
import { Button } from '../ui/Button'
import { Toaster } from '../ui/Toaster'
import { Viewer } from '../viewer/Viewer'
import { VIEW_PARAM, withoutViewerParams } from '../viewer/useViewerControls'
import { Rail } from './Rail'
import { TabBar } from './TabBar'
import styles from './AppShell.module.css'

/** 回到前台时后台同步；新内容只计数，不直接插进正在看的列表 */
function useForegroundSync() {
  useEffect(() => {
    const onVisible = () => {
      if (document.visibilityState !== 'visible') return
      if (Date.now() - appStore.get().sync.lastSyncedAt < 30_000) return
      void actions.sync({ explicit: false })
    }
    document.addEventListener('visibilitychange', onVisible)
    return () => document.removeEventListener('visibilitychange', onVisible)
  }, [])
}

export function AppShell() {
  const sync = useApp((s) => s.sync)
  const endpoint = useApp((s) => s.endpoint)
  const [params] = useSearchParams()
  const viewerOpen = params.has(VIEW_PARAM)
  useForegroundSync()

  return (
    <>
      <div className={styles.shell} inert={viewerOpen}>
        <Rail />
        <main className={styles.main}>
          {sync.error && (
            <div role="alert" style={{ padding: '16px' }}>
              <p>{sync.error}</p>
              <Button
                size="sm"
                disabled={sync.status === 'syncing'}
                onClick={() => void actions.sync({ explicit: true })}
              >
                重试同步
              </Button>
              {endpoint?.kind === 'connected' && (
                <Button
                  size="sm"
                  onClick={() => openEndpointDialog({ mode: 'edit', id: endpoint.id })}
                >
                  编辑端点
                </Button>
              )}
            </div>
          )}
          <Outlet />
        </main>
        <TabBar />
      </div>
      <Viewer />
      <EndpointDialog />
      <Toaster />
      {/* 滚动位置按“页面 + 筛选条件”记录，查看器参数不算在内，关闭查看器后停在跟随到的位置 */}
      <ScrollRestoration
        getKey={(location) => location.pathname + withoutViewerParams(location.search)}
      />
    </>
  )
}
