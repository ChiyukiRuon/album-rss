import { NavLink } from 'react-router'
import { cx } from '../../lib/cx'
import { feedPath } from '../../lib/paths'
import { useCategoryLabel, useUnreadCounts } from '../../prototype/selectors'
import { scopeKey, useApp } from '../../prototype/store'
import { Avatar } from '../ui/Avatar'
import { Wordmark } from './Logo'
import { NAV_ITEMS } from './nav'
import { EndpointSwitcher } from '../endpoint/EndpointSwitcher'
import styles from './Rail.module.css'

const STARRED_KEY = scopeKey({ status: 'starred' })

/** 桌面端左侧导航：四个入口 + 关注的画师 */
export function Rail() {
  const counts = useUnreadCounts()
  const feeds = useApp((s) => s.feeds)
  const categoryOf = useCategoryLabel()
  // 收藏按需读取：读完收藏列表之前，已加载的收藏数不代表总数，先不显示
  const starred = useApp((s) =>
    s.endpoint?.kind !== 'connected' || s.scopes[STARRED_KEY]?.done
      ? Object.values(s.entries).filter((e) => e.starred).length
      : undefined,
  )
  const pending = useApp((s) => s.sync.pendingIds.length)

  const badges: Record<string, number | undefined> = { '/': counts.total, '/starred': starred }

  return (
    <nav className={styles.rail} aria-label="主导航">
      <NavLink to="/" className={styles.brand} aria-label="Album RSS 首页">
        <Wordmark />
      </NavLink>

      <ul className={styles.nav}>
        {NAV_ITEMS.map(({ to, label, icon: Icon }) => (
          <li key={to}>
            <NavLink
              to={to}
              end={to === '/'}
              className={({ isActive }) => cx(styles.item, isActive && styles.active)}
            >
              {({ isActive }) => (
                <>
                  <Icon
                    className={styles.icon}
                    weight={isActive ? 'fill' : 'regular'}
                    aria-hidden
                  />
                  <span className={styles.label}>{label}</span>
                  {to === '/' && pending > 0 && (
                    <span className={styles.dot} aria-label="有新图集" />
                  )}
                  {badges[to] ? <span className={styles.count}>{badges[to]}</span> : null}
                </>
              )}
            </NavLink>
          </li>
        ))}
      </ul>

      <p className={styles.section}>画师</p>
      <ul className={styles.feeds}>
        {feeds.map((feed) => (
          <li key={feed.id}>
            <NavLink
              to={feedPath(feed.id)}
              className={({ isActive }) => cx(styles.feed, isActive && styles.active)}
              title={[feed.author, categoryOf(feed)].filter(Boolean).join(' · ')}
            >
              <Avatar src={feed.iconUrl} name={feed.author} size={24} />
              <span className={styles.feedName}>{feed.author}</span>
              {feed.parsingErrorCount > 0 && (
                <span className={styles.error} aria-label="抓取出错" />
              )}
              {counts.byFeed[feed.id] ? (
                <span className={styles.count}>{counts.byFeed[feed.id]}</span>
              ) : null}
            </NavLink>
          </li>
        ))}
      </ul>

      <EndpointSwitcher />
    </nav>
  )
}
