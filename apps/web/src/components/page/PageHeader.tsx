import type { ReactNode } from 'react'
import styles from './PageHeader.module.css'

interface PageHeaderProps {
  title: ReactNode
  subtitle?: ReactNode
  /** 标题左侧，例如画师头像 */
  leading?: ReactNode
  actions?: ReactNode
  /** 吸顶的筛选栏 */
  toolbar?: ReactNode
  wrapToolbar?: boolean
}

export function PageHeader({
  title,
  subtitle,
  leading,
  actions,
  toolbar,
  wrapToolbar,
}: PageHeaderProps) {
  return (
    <>
      <header className={styles.header}>
        {leading}
        <div className={styles.titles}>
          <h1 className={styles.title}>{title}</h1>
          {subtitle && <p className={styles.subtitle}>{subtitle}</p>}
        </div>
        {actions && <div className={styles.actions}>{actions}</div>}
      </header>
      {toolbar && (
        <div className={`${styles.toolbar} ${wrapToolbar ? styles.wrapToolbar : ''}`}>
          {toolbar}
        </div>
      )}
    </>
  )
}
