import type { ReactNode } from 'react'
import { Tone } from '../tone/Tone'
import styles from './EmptyState.module.css'

interface EmptyStateProps {
  icon: ReactNode
  title: string
  description: ReactNode
  actions?: ReactNode
}

export function EmptyState({ icon, title, description, actions }: EmptyStateProps) {
  return (
    <section className={styles.empty}>
      <Tone className={styles.badge}>
        <span className={styles.icon}>{icon}</span>
      </Tone>
      <h2 className={styles.title}>{title}</h2>
      <p className={styles.description}>{description}</p>
      {actions && <div className={styles.actions}>{actions}</div>}
    </section>
  )
}
