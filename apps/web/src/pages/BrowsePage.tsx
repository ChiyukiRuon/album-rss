import { ArrowClockwiseIcon, ChecksIcon } from '@phosphor-icons/react'
import { useEffect } from 'react'
import { EmptyState } from '../components/page/EmptyState'
import { PageHeader } from '../components/page/PageHeader'
import { Button } from '../components/ui/Button'
import { ConfirmButton } from '../components/ui/ConfirmButton'
import { EntryWall } from '../components/wall/EntryWall'
import { relativeTime } from '../lib/format'
import { useNow } from '../lib/useNow'
import { hasImages, useScopeList, useUnreadCounts } from '../prototype/selectors'
import { actions, useApp } from '../prototype/store'
import { FolderChips, ModeSwitch, NewItemsPill, StatusSwitch, SyncButton } from './wallControls'
import { useWallParams } from './useWallParams'

/** 只在未读墙显示空状态时挂载，保留已在浏览的列表快照。 */
function AutoShowNewUnread({ folderId, imagesOnly }: { folderId?: string; imagesOnly: boolean }) {
  const available = useApp((state) =>
    state.sync.pendingIds.some((id) => {
      const entry = state.entries[id]
      if (
        !entry ||
        entry.read ||
        (!hasImages(entry) && (imagesOnly || !state.settings.showImageless))
      )
        return false
      return (
        !folderId ||
        state.feeds.some((feed) => feed.id === entry.feedId && feed.folderIds.includes(folderId))
      )
    }),
  )
  useEffect(() => {
    if (available) actions.applyPending()
  }, [available])
  return null
}

export function BrowsePage() {
  const { status, mode, folderId, update } = useWallParams()
  const list = useScopeList({ status, folderId })
  const counts = useUnreadCounts()
  const folders = useApp((s) => s.folders)
  const sync = useApp((s) => s.sync)
  const now = useNow()
  const folder = folders.find((f) => f.id === folderId)
  const unread = folderId ? (counts.byFolder[folderId] ?? 0) : counts.total
  const scopeLabel = folder ? `「${folder.title}」` : '全部订阅'
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
        actions={
          <>
            <SyncButton />
            <ConfirmButton
              label="全部标为已读"
              icon={<ChecksIcon aria-hidden />}
              disabled={unread === 0}
              message={`将 ${unread} 个未读图集标为已读？`}
              confirmLabel="标为已读"
              onConfirm={() => void actions.markScopeRead({ folderId }, scopeLabel)}
            />
          </>
        }
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
            <>
              <AutoShowNewUnread folderId={folderId} imagesOnly={mode === 'images'} />
              <EmptyState
                icon={<ChecksIcon aria-hidden />}
                title="没有未读的订阅"
                description={`${syncedText}`}
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
            </>
          ) : (
            <EmptyState
              icon={<ArrowClockwiseIcon aria-hidden />}
              title="这里还没有图集"
              description="同步完成后，新的图集会出现在这里。"
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
