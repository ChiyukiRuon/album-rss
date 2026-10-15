import { NavLink } from 'react-router'
import { cx } from '../../lib/cx'
import { useApp } from '../../prototype/store'
import { NAV_ITEMS } from './nav'
import styles from './TabBar.module.css'

/** 窄屏底部导航 */
export function TabBar() {
  const pending = useApp((s) => s.sync.pendingIds.length)
  return (
    <nav className={styles.bar} aria-label="主导航">
      {NAV_ITEMS.map(({ to, label, icon: Icon }) => (
        <NavLink
          key={to}
          to={to}
          end={to === '/'}
          className={({ isActive }) => cx(styles.tab, isActive && styles.active)}
        >
          {({ isActive }) => (
            <>
              <span className={styles.iconWrap}>
                <Icon weight={isActive ? 'fill' : 'regular'} aria-hidden />
                {to === '/' && pending > 0 && <span className={styles.dot} aria-label="有新图集" />}
              </span>
              <span className={styles.label}>{label}</span>
            </>
          )}
        </NavLink>
      ))}
    </nav>
  )
}
