import { WarningCircleIcon } from '@phosphor-icons/react'
import { useMemo } from 'react'
import { Link, useSearchParams } from 'react-router'
import { PageHeader } from '../components/page/PageHeader'
import { Avatar } from '../components/ui/Avatar'
import { ImageThumb } from '../components/ui/ImageThumb'
import { relativeTime, siteName } from '../lib/format'
import { feedPath } from '../lib/paths'
import { useNow } from '../lib/useNow'
import { hasImages, useUnreadCounts } from '../prototype/selectors'
import { useApp } from '../prototype/store'
import type { Feed, ImageAsset } from '../prototype/types'
import styles from './FeedsPage.module.css'
import { FolderChips, SyncButton } from './wallControls'

export function FeedsPage() {
  const feeds = useApp((s) => s.feeds)
  const folders = useApp((s) => s.folders)
  const entries = useApp((s) => s.entries)
  const order = useApp((s) => s.order)
  const counts = useUnreadCounts()
  const [params, setParams] = useSearchParams()

  // 每个订阅最近的三张封面
  const covers = useMemo(() => {
    const map = new Map<string, ImageAsset[]>()
    for (const id of order) {
      const entry = entries[id]
      const cover = entry && hasImages(entry) ? entry.images[0] : undefined
      if (!entry || !cover) continue
      const list = map.get(entry.feedId) ?? []
      if (list.length < 3) map.set(entry.feedId, [...list, cover])
    }
    return map
  }, [order, entries])

  // 按分类分组。Miniflux 每个订阅只有一个分类；数据模型允许多对多，以兼容支持多个标签的 Google Reader 服务
  const groups = [
    ...folders.map((folder) => ({
      id: folder.id,
      title: folder.title,
      feeds: feeds.filter((feed) => feed.folderIds.includes(folder.id)),
    })),
    { id: 'none', title: '未分类', feeds: feeds.filter((feed) => feed.folderIds.length === 0) },
  ].filter((group) => group.feeds.length > 0)

  // 分类筛选放在地址里，和浏览页一样；找不到的分类（例如切换端点后）当作全部
  const requested = params.get('folder')
  const active = groups.find((group) => group.id === requested)
  const setFolder = (id: string | null) =>
    setParams(
      (current) => {
        const next = new URLSearchParams(current)
        if (id === null) next.delete('folder')
        else next.set('folder', id)
        return next
      },
      { replace: true },
    )

  return (
    <>
      <PageHeader
        title="订阅"
        subtitle={
          active
            ? `${active.title} · ${active.feeds.length} 个订阅`
            : `${feeds.length} 个订阅 · ${folders.length} 个分类`
        }
        actions={<SyncButton />}
        wrapToolbar
        toolbar={
          // 不到两个分类时筛选没有意义，和浏览页的规则一致
          folders.length > 1 ? (
            <FolderChips
              chips={groups.map((group) => ({
                id: group.id,
                title: group.title,
                count: group.feeds.length,
              }))}
              value={active?.id}
              onChange={setFolder}
            />
          ) : undefined
        }
      />
      {(active ? [active] : groups).map((group) => (
        <section key={group.id} className={styles.group} aria-labelledby={`folder-${group.id}`}>
          <h2 id={`folder-${group.id}`} className={styles.groupTitle}>
            {group.title}
            <span className={styles.groupCount}>{group.feeds.length}</span>
          </h2>
          <ul className={styles.grid}>
            {group.feeds.map((feed) => (
              <li key={feed.id}>
                <FeedTile
                  feed={feed}
                  unread={counts.byFeed[feed.id] ?? 0}
                  covers={covers.get(feed.id) ?? []}
                />
              </li>
            ))}
          </ul>
        </section>
      ))}
    </>
  )
}

function FeedTile({ feed, unread, covers }: { feed: Feed; unread: number; covers: ImageAsset[] }) {
  const now = useNow()
  return (
    <Link to={feedPath(feed.id)} className={styles.tile}>
      <span className={styles.covers} aria-hidden>
        {[0, 1, 2].map((i) => (
          <ImageThumb key={i} url={covers[i]?.url} className={styles.cover} lazy />
        ))}
      </span>
      <span className={styles.body}>
        <Avatar src={feed.iconUrl} name={feed.author} size={44} className={styles.avatar} />
        <span className={styles.text}>
          <span className={styles.name}>{feed.author}</span>
          <span className={styles.meta}>
            {/* 这一页已按分类分组，卡片里不再重复分类 */}
            {feed.checkedAt
              ? `${relativeTime(feed.checkedAt, now)}抓取`
              : siteName(feed.siteUrl) || '抓取时间未知'}
          </span>
        </span>
        {unread > 0 && (
          <span className={styles.unread} aria-label={`${unread} 个未读`}>
            {unread}
          </span>
        )}
      </span>
      {feed.parsingErrorCount > 0 && (
        <span className={styles.error}>
          <WarningCircleIcon weight="fill" aria-hidden />
          最近 {feed.parsingErrorCount} 次抓取失败
        </span>
      )}
    </Link>
  )
}
