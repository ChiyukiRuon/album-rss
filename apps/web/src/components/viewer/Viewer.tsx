import {
  ArrowSquareOutIcon,
  CaretLeftIcon,
  CaretRightIcon,
  DotsThreeIcon,
  EyeIcon,
  EyeSlashIcon,
  InfoIcon,
  LinkIcon,
  ShareNetworkIcon,
  StarIcon,
  XIcon,
} from '@phosphor-icons/react'
import { useEffect, useEffectEvent, useMemo, useRef, useState, type PointerEvent } from 'react'
import { Link, useSearchParams } from 'react-router'
import { cx } from '../../lib/cx'
import { relativeTime } from '../../lib/format'
import { openImage, whenImageSrc } from '../../lib/imageSource'
import { useNow } from '../../lib/useNow'
import { hasImages, useCategoryLabel, useFeedMap } from '../../prototype/selectors'
import { actions, appStore, useApp } from '../../prototype/store'
import { feedPath } from '../../lib/paths'
import type { Entry } from '../../prototype/types'
import { DownloadButton } from '../card/DownloadButton'
import { Avatar } from '../ui/Avatar'
import { Button, IconButton } from '../ui/Button'
import { ImageThumb } from '../ui/ImageThumb'
import { Menu } from '../ui/Menu'
import { showToast } from '../ui/toast'
import { InfoPanel } from './InfoPanel'
import { Stage } from './Stage'
import { INDEX_PARAM, useViewerControls, VIEW_PARAM } from './useViewerControls'
import styles from './Viewer.module.css'

const INFO_KEY = 'album-rss:viewer-info'

export function Viewer() {
  const [params] = useSearchParams()
  const entryId = params.get(VIEW_PARAM)
  if (!entryId) return null
  const index = Math.max(0, Number.parseInt(params.get(INDEX_PARAM) ?? '0', 10) || 0)
  return <ViewerOverlay entryId={entryId} index={index} />
}

interface Notice {
  key: number
  kind: 'next' | 'prev' | 'end' | 'start'
  entry?: Entry
}

function ViewerOverlay({ entryId, index: requestedIndex }: { entryId: string; index: number }) {
  const entries = useApp((s) => s.entries)
  const order = useApp((s) => s.order)
  const storedSequence = useApp((s) => s.viewerSequence)
  const feeds = useFeedMap()
  const categoryOf = useCategoryLabel()
  const controls = useViewerControls()
  const now = useNow()
  // 只在宽屏记住信息面板的开关；窄屏上它是盖住图片的底部弹层，每次都从收起开始
  const [infoOpen, setInfoOpen] = useState(
    () => localStorage.getItem(INFO_KEY) === '1' && window.matchMedia('(min-width: 900px)').matches,
  )
  const [chromeHidden, setChromeHidden] = useState(false)
  const [notice, setNotice] = useState<Notice | null>(null)
  const rootRef = useRef<HTMLDivElement>(null)
  const stripRef = useRef<HTMLDivElement>(null)
  const idleTimer = useRef<number | undefined>(undefined)

  const entry = entries[entryId]
  // 翻页顺序取自打开查看器的那个列表；直接打开链接时退回到全部有图文章
  const sequence = useMemo(
    () => storedSequence ?? order.filter((id) => entries[id] && hasImages(entries[id])),
    [storedSequence, order, entries],
  )
  const position = sequence.indexOf(entryId)
  const prevEntry = position > 0 ? entries[sequence[position - 1] ?? ''] : undefined
  const nextEntry = position >= 0 ? entries[sequence[position + 1] ?? ''] : undefined
  const count = entry?.images.length ?? 0
  const index = Math.min(requestedIndex, Math.max(0, count - 1))
  const image = entry?.images[index]

  useEffect(() => {
    const root = document.documentElement
    root.dataset.viewerOpen = ''
    rootRef.current?.focus({ preventScroll: true })
    return () => {
      delete root.dataset.viewerOpen
      window.clearTimeout(idleTimer.current)
    }
  }, [])

  // 预取前后各一张，换图时放弃旧的预取
  const neighbors = [
    entry?.images[index + 1] ?? nextEntry?.images[0],
    entry?.images[index - 1] ?? prevEntry?.images.at(-1),
  ]
    .filter((asset) => asset && asset.kind !== 'video')
    .map((asset) => asset?.url)
    .join('\n')
  useEffect(() => {
    if (!neighbors) return
    let cancelled = false
    const loading: HTMLImageElement[] = []
    for (const url of neighbors.split('\n')) {
      void whenImageSrc(url).then((src) => {
        if (cancelled) return
        const preload = new Image()
        preload.decoding = 'async'
        preload.src = src
        loading.push(preload)
      })
    }
    return () => {
      cancelled = true
      loading.forEach((preload) => preload.removeAttribute('src'))
    }
  }, [neighbors])

  // 当前缩略图保持在缩略图条中间；只滚动缩略图条本身，不牵动背后的列表
  useEffect(() => {
    const strip = stripRef.current
    const current = strip?.querySelector<HTMLElement>('[aria-current="true"]')
    if (!strip || !current) return
    const left = current.offsetLeft - strip.clientWidth / 2 + current.offsetWidth / 2
    strip.scrollTo({ left, behavior: 'smooth' })
  }, [entryId, index])

  const flash = (kind: Notice['kind'], target?: Entry) =>
    setNotice({ key: performance.now(), kind, entry: target })

  // 在当前图集里跳转。多于两张的图集向后翻到最后一张时预告下一组，往回翻到第一张时预告上一组；
  // 一两张的图集翻得快，不再每组都提示
  const goTo = (i: number) => {
    if (!entry) return
    controls.go(entry.id, i)
    if (count <= 2) return
    if (i > index && i === count - 1 && nextEntry) flash('next', nextEntry)
    else if (i < index && i === 0 && prevEntry) flash('prev', prevEntry)
  }

  // 看完当前图集后继续翻页，直接进入相邻的图集
  const next = () => {
    if (!entry) return
    if (index < count - 1) goTo(index + 1)
    else if (nextEntry) controls.go(nextEntry.id, 0)
    else flash('end')
  }

  const prev = () => {
    if (!entry) return
    if (index > 0) goTo(index - 1)
    else if (prevEntry) controls.go(prevEntry.id, prevEntry.images.length - 1)
    else flash('start')
  }

  const close = () => controls.close(entryId, index)

  const toggleInfo = () => {
    const next = !infoOpen
    if (window.matchMedia('(min-width: 900px)').matches) {
      localStorage.setItem(INFO_KEY, next ? '1' : '0')
    }
    setInfoOpen(next)
  }

  const toggleStar = () => {
    if (entry) actions.setStarred(entry.id, !entry.starred)
  }

  const scheduleHide = () => {
    window.clearTimeout(idleTimer.current)
    idleTimer.current = window.setTimeout(() => setChromeHidden(true), 2600)
  }

  const showChrome = () => {
    setChromeHidden(false)
    scheduleHide()
  }

  // 鼠标停在工具栏上时不自动隐藏
  const onPointerMove = (event: PointerEvent) => {
    if (event.pointerType !== 'mouse') return
    setChromeHidden(false)
    if ((event.target as HTMLElement).closest('[data-chrome]'))
      window.clearTimeout(idleTimer.current)
    else scheduleHide()
  }

  const onKey = useEffectEvent((event: KeyboardEvent) => {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    if ((event.target as HTMLElement).closest('input, textarea, [contenteditable="true"]')) return
    if ((event.target as HTMLElement).closest('video') && event.key !== 'Escape') return
    switch (event.key) {
      case 'ArrowRight':
      case 'PageDown':
        next()
        break
      case 'ArrowLeft':
      case 'PageUp':
        prev()
        break
      case 'Escape':
        close()
        break
      case 'i':
      case 'I':
        toggleInfo()
        break
      case 's':
      case 'S':
        toggleStar()
        break
      default:
        return
    }
    event.preventDefault()
    showChrome()
  })

  useEffect(() => {
    const handler = (event: KeyboardEvent) => onKey(event)
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [])

  // 至少一张图片显示成功后标为已读（可在设置中关闭）
  const markShown = (id: string) => {
    const state = appStore.get()
    if (state.settings.autoRead && state.entries[id]?.read === false) actions.setRead([id], true)
  }

  if (!entry || !image) {
    return (
      <div
        ref={rootRef}
        className={styles.viewer}
        data-viewer-root
        role="dialog"
        aria-modal="true"
        aria-label="图集查看器"
        tabIndex={-1}
      >
        <div className={styles.missing}>
          <p className={styles.missingTitle}>这个图集不在本地了</p>
          <p className={styles.missingHint}>它可能已被服务器删除，或者还没有同步到这台设备。</p>
          <Button variant="secondary" onClick={close}>
            返回列表
          </Button>
        </div>
      </div>
    )
  }

  const feed = feeds.get(entry.feedId)
  const category = categoryOf(feed)
  const author = feed?.author ?? entry.author
  const atStart = index === 0
  const atEnd = index === count - 1
  const showStrip = count > 1 || Boolean(nextEntry)

  const menuItems = [
    {
      label: image.kind === 'video' ? '打开视频' : '打开原图',
      icon: <ArrowSquareOutIcon aria-hidden />,
      onSelect: () =>
        image.kind === 'video'
          ? window.open(image.url, '_blank', 'noopener,noreferrer')
          : void openImage(image.url),
    },
    {
      label: '查看原文',
      icon: <ArrowSquareOutIcon aria-hidden />,
      onSelect: () => window.open(entry.url, '_blank', 'noopener,noreferrer'),
    },
    {
      label: '复制媒体地址',
      icon: <LinkIcon aria-hidden />,
      onSelect: () =>
        void navigator.clipboard
          .writeText(image.url)
          .then(() => showToast({ message: '已复制媒体地址', tone: 'success' }))
          .catch(() => showToast({ message: '无法访问剪贴板', tone: 'warning' })),
    },
    {
      label: '分享…',
      icon: <ShareNetworkIcon aria-hidden />,
      hidden: typeof navigator.share !== 'function',
      onSelect: () =>
        void navigator.share({ title: entry.title, url: entry.url }).catch(() => undefined),
    },
    {
      label: entry.read ? '标为未读' : '标为已读',
      icon: entry.read ? <EyeSlashIcon aria-hidden /> : <EyeIcon aria-hidden />,
      onSelect: () => actions.setRead([entry.id], !entry.read),
    },
  ]

  return (
    <div
      ref={rootRef}
      className={cx(styles.viewer, chromeHidden && image.kind !== 'video' && styles.chromeHidden)}
      data-viewer-root
      role="dialog"
      aria-modal="true"
      aria-label={`图集查看器：${author}`}
      tabIndex={-1}
      onPointerMove={onPointerMove}
    >
      <div className={styles.main}>
        <Stage
          key={`${entry.id}:${index}`}
          image={image}
          entryUrl={entry.url}
          onShown={() => markShown(entry.id)}
          onPrev={prev}
          onNext={next}
          onNextGroup={() => {
            if (nextEntry) controls.go(nextEntry.id, 0)
          }}
          onDismiss={close}
          onTap={() => setChromeHidden((hidden) => !hidden)}
        />

        <header className={styles.topbar} data-chrome>
          <IconButton
            label="关闭（Esc）"
            icon={<XIcon aria-hidden />}
            variant="viewer"
            onClick={close}
          />
          <Link to={feedPath(entry.feedId)} className={styles.author}>
            <Avatar src={feed?.iconUrl} name={author} size={32} />
            <span className={styles.authorText}>
              <span className={styles.authorName}>
                {author}
                {category && <span className={styles.category}>{category}</span>}
              </span>
              <span className={styles.authorSub}>
                {entry.title ? `${entry.title} · ` : ''}
                {relativeTime(entry.publishedAt, now)}
              </span>
            </span>
          </Link>
          <span className={styles.spacer} />
          <span className={styles.counter} aria-label={`第 ${index + 1} 张，共 ${count} 张`}>
            {index + 1}
            <span className={styles.counterSlash}>/</span>
            {count}
          </span>
          {/* 窄屏上这组按钮移到底部，方便单手点按 */}
          <div className={styles.actions}>
            <IconButton
              label={entry.starred ? '取消收藏（S）' : '收藏（S）'}
              icon={<StarIcon weight={entry.starred ? 'fill' : 'regular'} aria-hidden />}
              variant="viewer"
              aria-pressed={entry.starred}
              className={entry.starred ? styles.starred : undefined}
              onClick={toggleStar}
            />
            <DownloadButton
              downloadKey={`${entry.id}:${index}`}
              entry={entry}
              images={[image]}
              variant="viewer"
              size="md"
            />
            <IconButton
              label="文章信息（I）"
              icon={<InfoIcon aria-hidden />}
              variant="viewer"
              aria-pressed={infoOpen}
              className={infoOpen ? styles.pressed : undefined}
              onClick={toggleInfo}
            />
            <Menu
              dark
              label="更多操作"
              icon={<DotsThreeIcon weight="bold" aria-hidden />}
              items={menuItems}
            />
          </div>
        </header>

        <button
          type="button"
          className={cx(
            styles.arrow,
            styles.arrowPrev,
            atStart && prevEntry && styles.arrowGallery,
          )}
          data-chrome
          onClick={prev}
          disabled={atStart && !prevEntry}
          aria-label={atStart && prevEntry ? `上一组：${prevEntry.author}` : '上一张'}
        >
          <CaretLeftIcon aria-hidden weight="bold" />
          {atStart && prevEntry && (
            <>
              <Avatar
                src={feeds.get(prevEntry.feedId)?.iconUrl}
                name={prevEntry.author}
                size={24}
              />
              <span>上一组</span>
            </>
          )}
        </button>
        <button
          type="button"
          className={cx(styles.arrow, styles.arrowNext, atEnd && nextEntry && styles.arrowGallery)}
          data-chrome
          onClick={next}
          disabled={atEnd && !nextEntry}
          aria-label={atEnd && nextEntry ? `下一组：${nextEntry.author}` : '下一张'}
        >
          {atEnd && nextEntry && (
            <>
              <span>下一组</span>
              <Avatar
                src={feeds.get(nextEntry.feedId)?.iconUrl}
                name={nextEntry.author}
                size={24}
              />
            </>
          )}
          <CaretRightIcon aria-hidden weight="bold" />
        </button>

        {showStrip && (
          <nav className={styles.strip} data-chrome aria-label="图集缩略图">
            <div ref={stripRef} className={styles.stripInner}>
              {entry.images.map((thumb, i) => (
                <ThumbButton
                  key={thumb.key}
                  url={thumb.kind === 'video' ? thumb.poster : thumb.url}
                  label={thumb.kind === 'video' ? `第 ${i + 1} 项：视频` : `第 ${i + 1} 张`}
                  video={thumb.kind === 'video'}
                  current={i === index}
                  onClick={() => goTo(i)}
                />
              ))}
              {nextEntry && (
                <button
                  type="button"
                  className={styles.nextTile}
                  onClick={() => controls.go(nextEntry.id, 0)}
                  aria-label={`下一组：${nextEntry.author}，${nextEntry.images.length} 张`}
                >
                  <Thumb
                    url={
                      nextEntry.images[0]?.kind === 'video'
                        ? nextEntry.images[0]?.poster
                        : nextEntry.images[0]?.url
                    }
                  />
                  <span className={styles.nextText}>
                    <span className={styles.nextLabel}>下一组</span>
                    <span className={styles.nextAuthor}>{nextEntry.author}</span>
                  </span>
                </button>
              )}
            </div>
          </nav>
        )}

        {notice && (
          <div
            key={notice.key}
            className={styles.notice}
            role="status"
            onAnimationEnd={() => setNotice(null)}
          >
            {notice.entry ? (
              <>
                <Avatar
                  src={feeds.get(notice.entry.feedId)?.iconUrl}
                  name={notice.entry.author}
                  size={22}
                />
                <span className={styles.noticeLabel}>
                  {notice.kind === 'next' ? '下一组' : '上一组'}
                </span>
                <strong>{notice.entry.author}</strong>
                <span className={styles.noticeLabel}>{notice.entry.images.length} 张</span>
              </>
            ) : (
              <span>{notice.kind === 'end' ? '已经是最后一组了' : '已经是第一组了'}</span>
            )}
          </div>
        )}
      </div>

      {infoOpen && (
        <InfoPanel
          entry={entry}
          feed={feed}
          category={category}
          image={image}
          index={index}
          onClose={toggleInfo}
        />
      )}
    </div>
  )
}

function Thumb({ url }: { url: string | undefined }) {
  return <ImageThumb url={url} className={styles.thumbImage} lazy />
}

function ThumbButton({
  url,
  label,
  current,
  video,
  onClick,
}: {
  url: string | undefined
  label: string
  current: boolean
  video?: boolean
  onClick: () => void
}) {
  return (
    <button
      type="button"
      className={styles.thumb}
      aria-label={label}
      aria-current={current}
      onClick={onClick}
    >
      <Thumb url={url} />
      {video && (
        <span className={styles.videoMarker} aria-hidden>
          ▶
        </span>
      )}
    </button>
  )
}
