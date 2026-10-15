import {
  ArrowClockwiseIcon,
  ArrowSquareOutIcon,
  HourglassSimpleIcon,
  ImageBrokenIcon,
  StackIcon,
  StarIcon,
  TextAlignLeftIcon,
} from '@phosphor-icons/react'
import type { MouseEvent } from 'react'
import { Link } from 'react-router'
import { cx } from '../../lib/cx'
import { feedPath } from '../../lib/paths'
import type { Entry, Feed, ImageAsset } from '../../prototype/types'
import type { TileInfo } from '../masonry/Masonry'
import { Tone } from '../tone/Tone'
import { Avatar } from '../ui/Avatar'
import { IconButton } from '../ui/Button'
import { cardKeyOf } from './cardKey'
import { DownloadButton } from './DownloadButton'
import { useCardImage } from './useCardImage'
import styles from './GalleryCard.module.css'

export interface CardTarget {
  entry: Entry
  index: number
}

interface GalleryCardProps {
  entry: Entry
  feed: Feed | undefined
  /** 订阅所属的分类名，显示在作者旁边；不需要显示时为空 */
  category?: string
  /** 单图模式下这张卡片对应的图片序号；图集模式为 null */
  imageIndex: number | null
  info: TileInfo
  setSize: number
  /** 已读：在列表里变暗 */
  dimmed: boolean
  href: string
  onOpen: (target: CardTarget, image: HTMLImageElement | null) => void
}

export function GalleryCard({
  entry,
  feed,
  category,
  imageIndex,
  info,
  setSize,
  dimmed,
  href,
  onOpen,
}: GalleryCardProps) {
  const index = imageIndex ?? 0
  const image = entry.images[index]
  const author = feed?.author ?? entry.author
  const cardKey = cardKeyOf(entry.id, imageIndex)

  return (
    <article
      className={cx(styles.card, dimmed && styles.dimmed)}
      data-card-key={cardKey}
      aria-posinset={info.position}
      aria-setsize={setSize}
    >
      {image ? (
        <CoverMedia
          entry={entry}
          image={image}
          index={index}
          single={imageIndex !== null}
          author={author}
          info={info}
          href={href}
          onOpen={onOpen}
        />
      ) : (
        <TextMedia entry={entry} height={info.mediaHeight} />
      )}
      <footer className={styles.meta}>
        <Link to={feedPath(entry.feedId)} className={styles.author}>
          <Avatar src={feed?.iconUrl} name={author} size={20} />
          <span className={styles.name}>{author}</span>
          {category && <span className={styles.category}>{category}</span>}
        </Link>
        {image && (
          <DownloadButton
            downloadKey={cardKey}
            entry={entry}
            images={imageIndex === null ? entry.images : [image]}
            fallback={{ label: '在查看器中打开', run: () => onOpen({ entry, index }, null) }}
          />
        )}
      </footer>
    </article>
  )
}

interface CoverMediaProps {
  entry: Entry
  image: ImageAsset
  index: number
  single: boolean
  author: string
  info: TileInfo
  href: string
  onOpen: GalleryCardProps['onOpen']
}

function CoverMedia({ entry, image, index, single, author, info, href, onOpen }: CoverMediaProps) {
  const { src, imageKey, status, onLoad, onError, retry } = useCardImage(image.url, info.failed)
  const count = entry.images.length
  const title = entry.title.trim()

  const handleClick = (event: MouseEvent<HTMLAnchorElement>) => {
    // 带修饰键或中键时交给浏览器（新标签页打开等）
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
      return
    event.preventDefault()
    onOpen({ entry, index }, event.currentTarget.querySelector('img'))
  }

  const label = single
    ? `${author}：${title || '无标题'}，第 ${index + 1} 张，共 ${count} 张`
    : `${author}：${title || '无标题'}，${count} 张图片`

  return (
    <div className={styles.mediaWrap} style={{ height: info.mediaHeight }} data-status={status}>
      <a className={styles.media} href={href} onClick={handleClick} aria-label={label}>
        <Tone
          loading={status === 'loading'}
          className={cx(styles.fill, status === 'loaded' && styles.toneDone)}
        >
          {status === 'error' && (
            <span className={styles.failed}>
              <ImageBrokenIcon aria-hidden />
              图片加载失败
            </span>
          )}
        </Tone>
        {src && status !== 'error' && (
          <img
            key={imageKey}
            src={src}
            alt=""
            draggable={false}
            decoding="async"
            className={cx(
              styles.image,
              status === 'loaded' && styles.loaded,
              info.long && styles.long,
            )}
            onLoad={onLoad}
            onError={onError}
          />
        )}
        {!single && title && status !== 'error' && (
          <span className={styles.hoverTitle}>{title}</span>
        )}
      </a>
      {entry.starred && (
        <span className={styles.star} title="已收藏">
          <StarIcon weight="fill" aria-hidden />
        </span>
      )}
      {/* 角标都在右上角：张数在最右，长图在它左边；底部留给悬停时的标题 */}
      <span className={cx(styles.badges, entry.starred && styles.besideStar)} aria-hidden>
        {single ? (
          count > 1 && (
            <span className={styles.badge}>
              {index + 1}/{count}
            </span>
          )
        ) : count > 1 ? (
          <span className={styles.badge}>
            <StackIcon weight="fill" />
            {count}
          </span>
        ) : null}
        {info.long && status !== 'error' && <span className={styles.badge}>长图</span>}
      </span>
      {status === 'error' && (
        <IconButton
          className={styles.retry}
          label="重新加载图片"
          icon={<ArrowClockwiseIcon aria-hidden />}
          variant="glass"
          size="sm"
          onClick={retry}
        />
      )}
    </div>
  )
}

function TextMedia({ entry, height }: { entry: Entry; height: number }) {
  const pending = entry.parseState === 'pending'
  return (
    <div className={styles.mediaWrap} style={{ height }}>
      <a
        className={styles.media}
        href={entry.url}
        target="_blank"
        rel="noopener noreferrer"
        aria-label={`${entry.title}（${pending ? '图片待解析' : '没有图片'}），在新标签页打开原文`}
      >
        <Tone loading={pending} className={styles.fill}>
          <span className={styles.textLabel}>
            {pending ? <HourglassSimpleIcon aria-hidden /> : <TextAlignLeftIcon aria-hidden />}
            {pending ? '图片待解析' : '没有图片'}
          </span>
          <span className={styles.textBody}>
            <span className={styles.textTitle}>{entry.title}</span>
            {entry.paragraphs[0] && (
              <span className={styles.textExcerpt}>{entry.paragraphs[0]}</span>
            )}
            <span className={styles.textLink}>
              原文 <ArrowSquareOutIcon aria-hidden />
            </span>
          </span>
        </Tone>
      </a>
    </div>
  )
}
