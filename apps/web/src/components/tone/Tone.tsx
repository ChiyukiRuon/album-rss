import type { CSSProperties, ReactNode } from 'react'
import { cx } from '../../lib/cx'
import styles from './Tone.module.css'

interface ToneProps {
  className?: string
  style?: CSSProperties
  /** 等待中：网点缓慢移动 */
  loading?: boolean
  children?: ReactNode
}

/**
 * 网点底纹。凡是“还不是一张图”的状态——加载中、尺寸未知、加载失败、没有图片——
 * 都用它来呈现，像漫画原稿上的网点纸。
 */
export function Tone({ className, style, loading, children }: ToneProps) {
  return (
    <div className={cx(styles.tone, loading && styles.loading, className)} style={style}>
      {children}
    </div>
  )
}
