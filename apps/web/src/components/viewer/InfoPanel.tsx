import { ArrowSquareOutIcon, EyeIcon, EyeSlashIcon, StarIcon, XIcon } from '@phosphor-icons/react'
import { Link } from 'react-router'
import { fullTime, relativeTime } from '../../lib/format'
import { useNow } from '../../lib/useNow'
import { feedPath } from '../../lib/paths'
import { actions } from '../../prototype/store'
import type { Entry, Feed, ImageAsset } from '../../prototype/types'
import { Avatar } from '../ui/Avatar'
import { Button, IconButton } from '../ui/Button'
import styles from './InfoPanel.module.css'

interface InfoPanelProps {
  entry: Entry
  feed: Feed | undefined
  category?: string
  image: ImageAsset
  index: number
  onClose: () => void
}

/** 文章信息：桌面端在右侧，窄屏从底部弹出 */
export function InfoPanel({ entry, feed, category, image, index, onClose }: InfoPanelProps) {
  const now = useNow()
  const author = feed?.author ?? entry.author
  return (
    <aside className={styles.panel} aria-label="文章信息">
      <div className={styles.header}>
        <Link to={feedPath(entry.feedId)} className={styles.author}>
          <Avatar src={feed?.iconUrl} name={author} size={40} />
          <span className={styles.authorText}>
            <span className={styles.authorName}>{author}</span>
            <span className={styles.authorSub}>
              {category ? `${category} · ` : ''}
              {relativeTime(entry.publishedAt, now)}
            </span>
          </span>
        </Link>
        <IconButton
          label="收起文章信息"
          icon={<XIcon aria-hidden />}
          variant="viewer"
          onClick={onClose}
        />
      </div>

      <div className={styles.body}>
        <h2 className={styles.title}>{entry.title || '无标题'}</h2>
        {entry.paragraphs.map((paragraph, i) => (
          <p key={i} className={styles.paragraph}>
            {paragraph}
          </p>
        ))}
        {entry.tags.length > 0 && (
          <ul className={styles.tags} aria-label="标签">
            {entry.tags.map((tag) => (
              <li key={tag}>#{tag}</li>
            ))}
          </ul>
        )}
        {image.alt && (
          <p className={styles.caption}>
            图 {index + 1}：{image.alt}
          </p>
        )}
        <dl className={styles.facts}>
          <div>
            <dt>发布时间</dt>
            <dd>{fullTime(entry.publishedAt)}</dd>
          </div>
          <div>
            <dt>来自订阅</dt>
            <dd>{feed?.title ?? '未知订阅'}</dd>
          </div>
          <div>
            <dt>图片</dt>
            <dd>{entry.images.length} 张</dd>
          </div>
        </dl>
      </div>

      <div className={styles.actions}>
        <Button
          variant="secondary"
          className={entry.starred ? styles.starred : undefined}
          icon={<StarIcon weight={entry.starred ? 'fill' : 'regular'} aria-hidden />}
          aria-pressed={entry.starred}
          onClick={() => actions.setStarred(entry.id, !entry.starred)}
        >
          {entry.starred ? '已收藏' : '收藏'}
        </Button>
        <Button
          variant="ghost"
          icon={entry.read ? <EyeSlashIcon aria-hidden /> : <EyeIcon aria-hidden />}
          onClick={() => actions.setRead([entry.id], !entry.read)}
        >
          {entry.read ? '标为未读' : '标为已读'}
        </Button>
        <a className={styles.original} href={entry.url} target="_blank" rel="noopener noreferrer">
          查看原文
          <ArrowSquareOutIcon aria-hidden />
        </a>
      </div>
    </aside>
  )
}
