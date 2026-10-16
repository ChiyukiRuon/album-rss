import { CheckIcon, DownloadSimpleIcon, WarningCircleIcon } from '@phosphor-icons/react'
import { actions, useApp } from '../../prototype/store'
import type { Entry, ImageAsset } from '../../prototype/types'
import { IconButton } from '../ui/Button'
import type { ToastAction } from '../ui/toast'
import styles from './DownloadButton.module.css'

interface DownloadButtonProps {
  downloadKey: string
  entry: Entry
  images: ImageAsset[]
  variant?: 'ghost' | 'viewer'
  size?: 'sm' | 'md'
  /** 图源不允许网页读取时，提示里给出的操作 */
  fallback?: ToastAction
}

export function DownloadButton({
  downloadKey,
  entry,
  images: assets,
  variant = 'ghost',
  size = 'sm',
  fallback,
}: DownloadButtonProps) {
  const state = useApp((s) => s.downloads[downloadKey])
  const images = assets.filter((image) => image.kind !== 'video')
  if (!images.length) return null
  const idleLabel = images.length > 1 ? `下载图集（${images.length} 张）` : '下载图片'

  let label = idleLabel
  let icon = <DownloadSimpleIcon aria-hidden />
  if (state?.status === 'running') {
    label = `正在下载 ${state.done}/${state.total}`
    icon = <ProgressRing done={state.done} total={state.total} />
  } else if (state?.status === 'done') {
    label = '已下载'
    icon = <CheckIcon aria-hidden weight="bold" className={styles.done} />
  } else if (state?.status === 'blocked') {
    label = images.length > 1 ? '这些图片无法直接下载' : '这张图片无法直接下载'
    icon = <WarningCircleIcon aria-hidden className={styles.blocked} />
  }

  return (
    <IconButton
      label={label}
      icon={icon}
      variant={variant}
      size={size}
      onClick={() => void actions.download(downloadKey, entry, images, fallback)}
    />
  )
}

function ProgressRing({ done, total }: { done: number; total: number }) {
  const radius = 7
  const circumference = 2 * Math.PI * radius
  const progress = total > 0 ? done / total : 0
  return (
    <svg className={styles.ring} viewBox="0 0 18 18" width="1em" height="1em" aria-hidden>
      <circle cx="9" cy="9" r={radius} className={styles.track} />
      <circle
        cx="9"
        cy="9"
        r={radius}
        className={styles.bar}
        strokeDasharray={circumference}
        strokeDashoffset={circumference * (1 - Math.max(progress, 0.08))}
      />
    </svg>
  )
}
