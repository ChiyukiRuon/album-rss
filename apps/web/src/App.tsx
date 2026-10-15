import { useEffect } from 'react'
import { createBrowserRouter, Navigate, Outlet } from 'react-router'
import { RouterProvider } from 'react-router/dom'
import { AppShell } from './components/shell/AppShell'
import { BrowsePage } from './pages/BrowsePage'
import { ConnectPage } from './pages/ConnectPage'
import { FeedPage } from './pages/FeedPage'
import { FeedsPage } from './pages/FeedsPage'
import { NotFoundPage } from './pages/NotFoundPage'
import { SettingsPage } from './pages/SettingsPage'
import { StarredPage } from './pages/StarredPage'
import { actions, useApp } from './prototype/store'
import { EmptyState } from './components/page/EmptyState'
import { CircleNotchIcon } from '@phosphor-icons/react'

/** 把“跟随系统 / 浅色 / 深色”落到 <html data-theme> 上 */
function useTheme() {
  const theme = useApp((s) => s.settings.theme)
  useEffect(() => {
    const media = window.matchMedia('(prefers-color-scheme: dark)')
    const apply = () => {
      const dark = theme === 'dark' || (theme === 'system' && media.matches)
      document.documentElement.dataset.theme = dark ? 'dark' : 'light'
    }
    apply()
    media.addEventListener('change', apply)
    return () => media.removeEventListener('change', apply)
  }, [theme])
}

function Root() {
  useTheme()
  return <Outlet />
}

/** 没有正在使用的端点（或演示数据）时先去连接页 */
function RequireEndpoint() {
  const endpoint = useApp((s) => s.endpoint)
  const loaded = useApp((s) => s.loaded)
  useEffect(() => {
    if (endpoint?.kind === 'connected' && !loaded) void actions.sync({ explicit: true })
  }, [endpoint, loaded])
  if (endpoint && !loaded)
    return (
      <EmptyState
        icon={<CircleNotchIcon />}
        title="正在同步订阅和图集…"
        description="正在读取订阅和最新一页文章，更早的文章会在浏览时按需读取。"
      />
    )
  return endpoint ? <AppShell /> : <Navigate to="/connect" replace />
}

const router = createBrowserRouter([
  {
    element: <Root />,
    children: [
      { path: '/connect', element: <ConnectPage /> },
      {
        element: <RequireEndpoint />,
        children: [
          { index: true, element: <BrowsePage /> },
          { path: 'starred', element: <StarredPage /> },
          { path: 'feeds', element: <FeedsPage /> },
          { path: 'feeds/:feedId', element: <FeedPage /> },
          { path: 'settings', element: <SettingsPage /> },
          { path: '*', element: <NotFoundPage /> },
        ],
      },
    ],
  },
])

export default function App() {
  return <RouterProvider router={router} />
}
