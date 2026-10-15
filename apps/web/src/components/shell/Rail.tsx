import { NavLink } from 'react-router'
import { cx } from '../../lib/cx'
import { feedPath } from '../../lib/paths'
import { useCategoryLabel, useUnreadCounts } from '../../prototype/selectors'
import { useApp } from '../../prototype/store'
import { Avatar } from '../ui/Avatar'
import { Wordmark } from './Logo'
import { NAV_ITEMS } from './nav'
import { EndpointSelect } from './EndpointSelect'
import styles from './Rail.module.css'

/** 桌面端左侧导航：四个入口 + 关注的画师 */
export function Rail() {
  const counts = useUnreadCounts()
  const feeds = useApp((s) => s.feeds)
  const categoryOf = useCategoryLabel()
  const starred = useApp((s) => Object.values(s.entries).filter((e) => e.starred).length)
  const session = useApp((s) => s.session)
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

      {session && (
        <div className={styles.account}>
          <EndpointSelect />
          <NavLink to="/settings" className={styles.accountInfo}>
            <span className={styles.accountDot} aria-hidden />
            <span className={styles.accountText}>
              <span className={styles.accountServer}>{session.server}</span>
              <span className={styles.accountKind}>
                {session.kind === 'demo'
                  ? '演示数据'
                  : session.service === 'miniflux'
                    ? 'Miniflux'
                    : 'Google Reader'}
              </span>
            </span>
          </NavLink>
        </div>
      )}
    </nav>
  )
}
