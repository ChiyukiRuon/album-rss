import type { Feed } from '@album-rss/core'
import { loadServiceIcon, useApp } from '../../prototype/store'
import { loadFeedAvatar } from '../../lib/feedAvatar'
import { useEffect, useState } from 'react'
import { cx } from '../../lib/cx'
import { useImageSrc } from '../../lib/imageSource'
import styles from './Avatar.module.css'

interface AvatarProps {
  feed?: Feed
  name: string
  size?: number
  className?: string
}

/** 订阅图标；没有图标或加载失败时显示名字的第一个字 */
export function Avatar({ feed, name, size = 20, className }: AvatarProps) {
  const source = feed?.feedUrl
  const [original, setOriginal] = useState<{ source: string; url: string }>()
  useEffect(() => {
    if (!source) return
    let active = true
    void loadFeedAvatar(source).then((url) => {
      if (active) setOriginal({ source, url })
    })
    return () => {
      active = false
    }
  }, [source])
  const endpoint = useApp((state) => state.endpoint)
  const iconId = feed?.iconId
  const feedId = feed?.id
  const [service, setService] = useState<{
    endpoint: typeof endpoint
    iconId: number
    url: string
  }>()
  useEffect(() => {
    if (!endpoint || !iconId || !feedId) return
    let active = true
    void loadServiceIcon(endpoint, feedId, iconId)?.then((url) => {
      if (active) setService({ endpoint, iconId, url })
    })
    return () => {
      active = false
    }
  }, [endpoint, feedId, iconId])
  const serviceIcon = useImageSrc(
    (service && service.endpoint === endpoint && service.iconId === iconId && service.url) ||
      feed?.iconUrl,
  )
  const preferred = original?.source === source ? original?.url : undefined
  return (
    <span
      className={cx(styles.avatar, className)}
      style={{ width: size, height: size, fontSize: Math.round(size * 0.46) }}
      aria-hidden
    >
      <span>{Array.from(name)[0]?.toUpperCase()}</span>
      {serviceIcon && <AvatarImage key={serviceIcon} src={serviceIcon} />}
      {preferred && preferred !== serviceIcon && <AvatarImage key={preferred} src={preferred} />}
    </span>
  )
}

function AvatarImage({ src }: { src: string }) {
  const [loaded, setLoaded] = useState(false)
  return (
    <img
      referrerPolicy="no-referrer"
      src={src}
      alt=""
      loading="lazy"
      decoding="async"
      style={{ opacity: loaded ? 1 : 0 }}
      onLoad={() => setLoaded(true)}
      onError={() => setLoaded(false)}
    />
  )
}
