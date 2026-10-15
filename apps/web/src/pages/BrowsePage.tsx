import { ArrowClockwiseIcon, ChecksIcon } from '@phosphor-icons/react'
import { EmptyState } from '../components/page/EmptyState'
import { PageHeader } from '../components/page/PageHeader'
import { Button } from '../components/ui/Button'
import { EntryWall } from '../components/wall/EntryWall'
import { relativeTime } from '../lib/format'
import { useNow } from '../lib/useNow'
import { useScopeList, useUnreadCounts } from '../prototype/selectors'
import { actions, useApp } from '../prototype/store'
import { FolderChips, ModeSwitch, NewItemsPill, StatusSwitch, SyncButton } from './wallControls'
import { useWallParams } from './useWallParams'

export function BrowsePage() {
  const { status, mode, folderId, update } = useWallParams()
  const list = useScopeList({ status, folderId })
  const counts = useUnreadCounts()
  const folders = useApp((s) => s.folders)
  const sync = useApp((s) => s.sync)
  const now = useNow()
  const folder = folders.find((f) => f.id === folderId)
  const unread = folderId ? (counts.byFolder[folderId] ?? 0) : counts.total
  const syncedText =
    sync.status === 'syncing' ? '正在同步…' : `${relativeTime(sync.lastSyncedAt, now)}同步`

  return (
    <>
      <PageHeader
        title="浏览"
        wrapToolbar
        subtitle={
          <>
            {folder ? `${folder.title} · ` : ''}
            {status === 'unread'
              ? `${unread} 个未读图集`
              : `${list.ids.length}${list.hasMore ? '+' : ''} 个图集`}{' '}
            · {syncedText}
          </>
        }
        actions={<SyncButton />}
        toolbar={
          <>
            <StatusSwitch
              status={status}
              unread={unread}
              onChange={(value) => update({ status: value })}
            />
            <ModeSwitch
              mode={mode}
              onChange={(value) => update({ mode: value === 'albums' ? null : value })}
            />
            {/* 分类来自 RSS 服务；只有一个分类时筛选没有意义，不显示 */}
            {folders.length > 1 && (
              <FolderChips
                inline
                chips={folders.map((f) => ({
                  id: f.id,
                  title: f.title,
                  count: counts.byFolder[f.id],
                }))}
                value={folderId}
                onChange={(id) => update({ folder: id })}
              />
            )}
          </>
        }
      />
      <NewItemsPill />
      <EntryWall
        list={list}
        mode={mode}
        label={folder ? `${folder.title}中的图集` : '图集'}
        dimRead
        empty={
          status === 'unread' ? (
            <EmptyState
              icon={<ChecksIcon aria-hidden />}
              title="未读的图集都看完了"
              description={`${syncedText}。可以再同步一次看看有没有新的，或者回顾全部图集。`}
              actions={
                <>
                  <Button
                    variant="primary"
                    icon={<ArrowClockwiseIcon aria-hidden />}
                    onClick={() => void actions.sync({ explicit: true })}
                  >
                    同步
                  </Button>
                  <Button onClick={() => update({ status: 'all' })}>查看全部</Button>
                </>
              }
            />
          ) : (
            <EmptyState
              icon={<ArrowClockwiseIcon aria-hidden />}
              title="这里还没有图集"
              description="订阅里还没有包含图片的文章。同步完成后，新的图集会出现在这里。"
              actions={
                <Button variant="primary" onClick={() => void actions.sync({ explicit: true })}>
                  同步
                </Button>
              }
            />
          )
        }
      />
    </>
  )
}
