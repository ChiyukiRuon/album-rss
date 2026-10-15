import { useState } from 'react'
import { cx } from '../../lib/cx'
import { useImageSrc } from '../../lib/imageSource'
import styles from './Avatar.module.css'

interface AvatarProps {
  src?: string
  name: string
  size?: number
  className?: string
}

/** 订阅图标；没有图标或加载失败时显示名字的第一个字 */
export function Avatar({ src, name, size = 20, className }: AvatarProps) {
  const resolved = useImageSrc(src)
  const [failedSrc, setFailedSrc] = useState<string | null>(null)
  const showImage = resolved && failedSrc !== resolved
  return (
    <span
      className={cx(styles.avatar, className)}
      style={{ width: size, height: size, fontSize: Math.round(size * 0.46) }}
      aria-hidden
    >
      {showImage ? (
        <img src={resolved} alt="" onError={() => setFailedSrc(resolved)} />
      ) : (
        Array.from(name)[0]?.toUpperCase()
      )}
    </span>
  )
}
