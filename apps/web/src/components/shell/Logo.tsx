import styles from './Logo.module.css'

/** 标志：一小块瀑布流，其中一格是品红 */
export function LogoMark({ size = 22 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 22 22" aria-hidden className={styles.mark}>
      <rect x="1" y="1" width="9" height="12" rx="2.5" fill="currentColor" />
      <rect x="1" y="15" width="9" height="6" rx="2.5" fill="currentColor" />
      <rect x="12" y="1" width="9" height="7" rx="2.5" className={styles.spot} />
      <rect x="12" y="10" width="9" height="11" rx="2.5" fill="currentColor" />
    </svg>
  )
}

export function Wordmark() {
  return (
    <span className={styles.wordmark}>
      <LogoMark />
      <span className={styles.text}>
        Album<span className={styles.rss}>RSS</span>
      </span>
    </span>
  )
}
