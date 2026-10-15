import {
  ArrowClockwiseIcon,
  ArrowSquareOutIcon,
  ChecksIcon,
  RssIcon,
  WarningCircleIcon,
} from '@phosphor-icons/react'
import { Fragment, type ReactNode } from 'react'
import { useNavigate, useParams } from 'react-router'
import { EmptyState } from '../components/page/EmptyState'
import { PageHeader } from '../components/page/PageHeader'
import { Avatar } from '../components/ui/Avatar'
import { Button } from '../components/ui/Button'
import { ConfirmButton } from '../components/ui/ConfirmButton'
import { EntryWall } from '../components/wall/EntryWall'
import { cx } from '../lib/cx'
import { relativeTime, siteName } from '../lib/format'
import { useNow } from '../lib/useNow'
import { useCategoryLabel, useScopeList, useUnreadCounts } from '../prototype/selectors'
import { actions, useApp } from '../prototype/store'
import styles from './pages.module.css'
import { ModeSwitch, StatusSwitch } from './wallControls'
import { useWallParams } from './useWallParams'

/** 单个订阅（画师）的页面 */
export function FeedPage() {
  const { feedId = '' } = useParams()
  const navigate = useNavigate()
  const feed = useApp((s) => s.feeds.find((f) => f.id === feedId))
  const refreshing = useApp((s) => Boolean(s.refreshingFeeds[feedId]))
  const canRefresh = useApp(
    (s) => s.endpoint?.kind === 'demo' || s.endpoint?.service === 'miniflux',
  )
  const { status, mode, update } = useWallParams()
  const list = useScopeList({ status, feedId })
  const counts = useUnreadCounts()
  const categoryOf = useCategoryLabel()
  const now = useNow()

  if (!feed) {
    return (
      <EmptyState
        icon={<RssIcon aria-hidden />}
        title="找不到这个订阅"
        description="它可能已在 RSS 服务里被删除。"
        actions={<Button onClick={() => navigate('/feeds')}>查看全部订阅</Button>}
      />
    )
  }

  const unread = counts.byFeed[feed.id] ?? 0
  const site = siteName(feed.siteUrl)
  // 分类 · 订阅标题（与名字相同时省略）· 抓取时间 · 网站链接
  const details: ReactNode[] = [
    categoryOf(feed),
    feed.title !== feed.author ? feed.title : null,
    refreshing ? '正在抓取…' : feed.checkedAt ? `${relativeTime(feed.checkedAt, now)}抓取` : null,
    site ? (
      <a
        className={styles.headerLink}
        href={feed.siteUrl}
        target="_blank"
        rel="noopener noreferrer"
      >
        在 {site} 查看
        <ArrowSquareOutIcon aria-hidden />
      </a>
    ) : null,
  ].filter(Boolean)

  return (
    <>
      <PageHeader
        leading={
          <Avatar src={feed.iconUrl} name={feed.author} size={64} className={styles.headerAvatar} />
        }
        title={feed.author}
        subtitle={details.map((part, i) => (
          <Fragment key={i}>
            {i > 0 && ' · '}
            {part}
          </Fragment>
        ))}
        actions={
          <>
            {canRefresh && (
              <Button
                size="sm"
                icon={<ArrowClockwiseIcon aria-hidden className={cx(refreshing && styles.spin)} />}
                disabled={refreshing}
                onClick={() => void actions.refreshFeed(feed.id)}
              >
                刷新
              </Button>
            )}
            <ConfirmButton
              label="全部标为已读"
              icon={<ChecksIcon aria-hidden />}
              disabled={unread === 0}
              message={`将「${feed.author}」的 ${unread} 个未读图集标为已读？之后可以撤销。`}
              confirmLabel="标为已读"
              onConfirm={() => void actions.markFeedRead(feed)}
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
          </>
        }
      />
      {feed.parsingErrorCount > 0 && (
        <div className={styles.banner} role="alert">
          <WarningCircleIcon weight="fill" aria-hidden className={styles.bannerIcon} />
          <div className={styles.bannerBody}>
            <p className={styles.bannerTitle}>最近 {feed.parsingErrorCount} 次抓取失败</p>
            <p className={styles.bannerText}>
              {feed.parsingError}。下面是之前同步到的内容，RSS 服务会继续按计划重试。
            </p>
          </div>
          {canRefresh && (
            <Button
              size="sm"
              disabled={refreshing}
              onClick={() => void actions.refreshFeed(feed.id)}
            >
              重试
            </Button>
          )}
        </div>
      )}
      <EntryWall
        list={list}
        mode={mode}
        label={`${feed.author}的图集`}
        dimRead
        empty={
          <EmptyState
            icon={<ChecksIcon aria-hidden />}
            title={status === 'unread' ? `「${feed.author}」没有未读图集` : '还没有图集'}
            description={
              status === 'unread'
                ? '新作品同步到之后会出现在这里。'
                : '这个订阅里还没有包含图片的文章。'
            }
            actions={
              status === 'unread' ? (
                <Button onClick={() => update({ status: 'all' })}>查看全部</Button>
              ) : undefined
            }
          />
        }
      />
    </>
  )
}
