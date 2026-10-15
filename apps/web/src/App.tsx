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

/** 没有登录（或选择演示数据）时先去连接页 */
function RequireSession() {
  const session = useApp((s) => s.session)
  const loaded = useApp((s) => s.loaded)
  useEffect(() => {
    if (session?.kind === 'connected' && !loaded) void actions.sync({ explicit: true })
  }, [session, loaded])
  if (session && !loaded)
    return (
      <EmptyState
        icon={<CircleNotchIcon />}
        title="正在同步订阅和图集…"
        description="正在读取 RSS 服务里的订阅和文章。"
      />
    )
  return session ? <AppShell /> : <Navigate to="/connect" replace />
}

const router = createBrowserRouter([
  {
    element: <Root />,
    children: [
      { path: '/connect', element: <ConnectPage /> },
      {
        element: <RequireSession />,
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
