import { ArrowClockwiseIcon, ArrowSquareOutIcon, ImageBrokenIcon } from '@phosphor-icons/react'
import {
  useCallback,
  useEffect,
  useEffectEvent,
  useRef,
  useState,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
} from 'react'
import { useVideoAutoplay } from '../../lib/videoAutoplay'
import { useApp } from '../../prototype/store'
import { cx } from '../../lib/cx'
import { getLoadedSize, recordLoadedSize } from '../../lib/imageProbe'
import { openImage, useImageSrc } from '../../lib/imageSource'
import type { ImageAsset } from '../../prototype/types'
import { Tone } from '../tone/Tone'
import { Button } from '../ui/Button'
import styles from './Stage.module.css'

interface StageProps {
  image: ImageAsset
  entryUrl: string
  /** 图片成功显示：用于“看过即已读” */
  onShown: () => void
  onPrev: () => void
  onNext: () => void
  /** 播完切换按组跳转，不使用组内翻页 */
  onNextGroup?: () => void
  /** 触屏下滑关闭 */
  onDismiss: () => void
  /** 触屏单击：显示 / 隐藏界面 */
  onTap: () => void
}

interface View {
  scale: number
  x: number
  y: number
}

type Gesture =
  | { kind: 'pinch'; distance: number; mid: Point; start: View }
  | {
      kind: 'pan' | 'swipe'
      startX: number
      startY: number
      startTime: number
      start: View
      touch: boolean
      moved: boolean
      axis: 'x' | 'y' | null
    }

interface Point {
  x: number
  y: number
}

const IDENTITY: View = { scale: 1, x: 0, y: 0 }
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value))
const distance = (a: Point, b: Point) => Math.hypot(a.x - b.x, a.y - b.y)

export function Stage(props: StageProps) {
  return props.image.kind === 'video' ? <VideoStage {...props} /> : <ImageStage {...props} />
}

function VideoStage({ image, entryUrl, onShown, onNextGroup }: StageProps) {
  const [failed, setFailed] = useState(false)
  const settings = useApp((state) => state.settings)
  const autoplay = useVideoAutoplay(settings.videoAutoplay, settings.videoAutoplayCellular)
  const videoRef = useRef<HTMLVideoElement>(null)
  useEffect(() => {
    const video = videoRef.current
    if (!autoplay || !video) return
    // 自动播放被浏览器拦截时，保留系统播放按钮。
    void video.play().catch(() => undefined)
    return () => video.pause()
  }, [autoplay])
  return (
    <div className={styles.stage} style={{ display: 'grid', placeItems: 'center' }}>
      {failed ? (
        <div role="alert">
          <p>视频无法播放，可能是格式不受支持或源站限制。</p>
          <a href={image.url} target="_blank" rel="noopener noreferrer">
            打开视频
          </a>
          {' · '}
          <a href={entryUrl} target="_blank" rel="noopener noreferrer">
            查看原文
          </a>
        </div>
      ) : (
        <video
          ref={videoRef}
          src={image.url}
          poster={image.poster}
          controls
          playsInline
          loop={settings.videoEndBehavior === 'loop'}
          onEnded={() => {
            if (settings.videoEndBehavior === 'nextGroup') onNextGroup?.()
          }}
          preload="metadata"
          aria-label="视频播放器"
          onPlaying={onShown}
          onError={() => setFailed(true)}
          style={{
            width: '100%',
            height: '100%',
            maxHeight: 'calc(100dvh - 240px)',
            objectFit: 'contain',
          }}
        />
      )}
    </div>
  )
}

function ImageStage({ image, entryUrl, onShown, onPrev, onNext, onDismiss, onTap }: StageProps) {
  const src = useImageSrc(image.url)
  const [attempt, setAttempt] = useState(0)
  const [status, setStatus] = useState<'loading' | 'loaded' | 'error'>('loading')
  const [natural, setNatural] = useState(() =>
    image.width && image.height
      ? { width: image.width, height: image.height }
      : (getLoadedSize(image.url) ?? null),
  )
  const [box, setBox] = useState({ width: 0, height: 0 })
  const [view, setView] = useState<View>(IDENTITY)
  const [smooth, setSmooth] = useState(false)
  const [swipe, setSwipe] = useState<Point | null>(null)
  const [grabbing, setGrabbing] = useState(false)
  const stageRef = useRef<HTMLDivElement>(null)
  const frameRef = useRef<HTMLDivElement | null>(null)
  const pointers = useRef(new Map<number, Point>())
  const gesture = useRef<Gesture | null>(null)
  const tapTimer = useRef<number | undefined>(undefined)
  const lastTap = useRef(0)
  const lastPointer = useRef('mouse')

  const attachFrame = useCallback((node: HTMLDivElement | null) => {
    if (!node) return
    frameRef.current = node
    const observer = new ResizeObserver(([entry]) => {
      if (entry) setBox({ width: entry.contentRect.width, height: entry.contentRect.height })
    })
    observer.observe(node)
    return () => {
      observer.disconnect()
      frameRef.current = null
    }
  }, [])

  // 适应窗口显示，不放大小图
  const fit =
    natural && box.width > 0
      ? Math.min(box.width / natural.width, box.height / natural.height, 1)
      : 0
  const shownWidth = natural ? natural.width * fit : 0
  const shownHeight = natural ? natural.height * fit : 0
  const maxScale = fit > 0 ? Math.max(3, 1 / fit) : 3

  const limit = (next: View): View => {
    const scale = clamp(next.scale, 1, maxScale)
    const limitX = Math.max(0, (shownWidth * scale - box.width) / 2)
    const limitY = Math.max(0, (shownHeight * scale - box.height) / 2)
    return { scale, x: clamp(next.x, -limitX, limitX), y: clamp(next.y, -limitY, limitY) }
  }

  /** 以 point（相对画框中心）为不动点缩放 */
  const zoomAt = (point: Point, scale: number, from: View): View => {
    const next = clamp(scale, 1, maxScale)
    const k = next / from.scale
    return limit({
      scale: next,
      x: point.x - (point.x - from.x) * k,
      y: point.y - (point.y - from.y) * k,
    })
  }

  const toLocal = (clientX: number, clientY: number): Point => {
    const rect = frameRef.current?.getBoundingClientRect()
    if (!rect) return { x: 0, y: 0 }
    return { x: clientX - (rect.left + rect.width / 2), y: clientY - (rect.top + rect.height / 2) }
  }

  const toggleZoom = (point: Point) => {
    setSmooth(true)
    if (view.scale > 1.01) {
      setView(IDENTITY)
      return
    }
    // 长图（条漫）：放大到撑满宽度，从顶部开始，之后拖动往下看
    if (shownWidth > 0 && shownWidth < box.width * 0.6) {
      const scale = Math.min(maxScale, box.width / shownWidth)
      setView(limit({ scale, x: 0, y: (shownHeight * scale - box.height) / 2 }))
      return
    }
    setView(zoomAt(point, fit > 0 && fit < 0.4 ? Math.min(1 / fit, 4) : 2.5, view))
  }

  const onWheel = useEffectEvent((event: WheelEvent) => {
    event.preventDefault()
    setSmooth(false)
    setView((current) =>
      zoomAt(
        toLocal(event.clientX, event.clientY),
        current.scale * Math.exp(-event.deltaY * 0.0018),
        current,
      ),
    )
  })

  const onKey = useEffectEvent((event: KeyboardEvent) => {
    if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey) return
    const center = { x: 0, y: 0 }
    if (event.key === '+' || event.key === '=') {
      setSmooth(true)
      setView(zoomAt(center, view.scale * 1.5, view))
    } else if (event.key === '-') {
      setSmooth(true)
      setView(zoomAt(center, view.scale / 1.5, view))
    } else if (event.key === '0' || (event.key === 'Escape' && view.scale > 1.01)) {
      setSmooth(true)
      setView(IDENTITY)
    } else return
    event.preventDefault()
  })

  useEffect(() => {
    const stage = stageRef.current
    if (!stage) return
    const wheel = (event: WheelEvent) => onWheel(event)
    const key = (event: KeyboardEvent) => onKey(event)
    stage.addEventListener('wheel', wheel, { passive: false })
    // 捕获阶段注册：缩放状态下的 Esc 先由这里处理，查看器不会因此关闭
    window.addEventListener('keydown', key, true)
    return () => {
      stage.removeEventListener('wheel', wheel)
      window.removeEventListener('keydown', key, true)
      window.clearTimeout(tapTimer.current)
    }
  }, [])

  const onPointerDown = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (event.pointerType === 'mouse' && event.button !== 0) return
    if ((event.target as HTMLElement).closest('button, a')) return
    lastPointer.current = event.pointerType
    event.currentTarget.setPointerCapture(event.pointerId)
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY })
    setSmooth(false)
    const [a, b] = [...pointers.current.values()]
    if (a && b) {
      gesture.current = {
        kind: 'pinch',
        distance: Math.max(1, distance(a, b)),
        mid: toLocal((a.x + b.x) / 2, (a.y + b.y) / 2),
        start: view,
      }
      setSwipe(null)
      return
    }
    gesture.current = {
      kind: view.scale > 1.01 ? 'pan' : 'swipe',
      startX: event.clientX,
      startY: event.clientY,
      startTime: event.timeStamp,
      start: view,
      touch: event.pointerType !== 'mouse',
      moved: false,
      axis: null,
    }
    if (view.scale > 1.01) setGrabbing(true)
  }

  const onPointerMove = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!pointers.current.has(event.pointerId)) return
    pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY })
    const g = gesture.current
    if (!g) return
    if (g.kind === 'pinch') {
      const [a, b] = [...pointers.current.values()]
      if (!a || !b) return
      const mid = toLocal((a.x + b.x) / 2, (a.y + b.y) / 2)
      const zoomed = zoomAt(g.mid, (g.start.scale * distance(a, b)) / g.distance, g.start)
      setView(limit({ ...zoomed, x: zoomed.x + mid.x - g.mid.x, y: zoomed.y + mid.y - g.mid.y }))
      return
    }
    const dx = event.clientX - g.startX
    const dy = event.clientY - g.startY
    if (!g.moved && Math.hypot(dx, dy) < 6) return
    g.moved = true
    if (g.kind === 'pan') {
      setView(limit({ ...g.start, x: g.start.x + dx, y: g.start.y + dy }))
      return
    }
    // 只有触屏允许下滑关闭；鼠标拖动只用于左右翻页
    g.axis ??= Math.abs(dx) >= Math.abs(dy) || !g.touch ? 'x' : 'y'
    setSwipe(g.axis === 'x' ? { x: dx, y: 0 } : { x: 0, y: Math.max(0, dy) })
  }

  const onPointerUp = (event: ReactPointerEvent<HTMLDivElement>) => {
    if (!pointers.current.delete(event.pointerId)) return
    const g = gesture.current
    setGrabbing(false)
    if (!g) return
    if (g.kind === 'pinch') {
      if (pointers.current.size === 0) gesture.current = null
      if (view.scale < 1.03) {
        setSmooth(true)
        setView(IDENTITY)
      }
      return
    }
    gesture.current = null
    if (g.kind === 'pan') return
    setSwipe(null)
    const dx = event.clientX - g.startX
    const dy = event.clientY - g.startY
    if (!g.moved) {
      // 长按留给系统的“保存图片”菜单，不当作单击
      const longPress = event.timeStamp - g.startTime > 450
      if (g.touch && !longPress) handleTouchTap(event.clientX, event.clientY)
      return
    }
    const velocity = dx / Math.max(1, event.timeStamp - g.startTime)
    if (g.axis === 'x' && (dx < -70 || velocity < -0.5)) onNext()
    else if (g.axis === 'x' && (dx > 70 || velocity > 0.5)) onPrev()
    else if (g.axis === 'y' && dy > 110) onDismiss()
  }

  // 触屏：双击缩放，单击延迟一下再切换界面，避免和双击冲突
  const handleTouchTap = (clientX: number, clientY: number) => {
    const now = performance.now()
    if (now - lastTap.current < 300) {
      window.clearTimeout(tapTimer.current)
      lastTap.current = 0
      toggleZoom(toLocal(clientX, clientY))
      return
    }
    lastTap.current = now
    tapTimer.current = window.setTimeout(onTap, 280)
  }

  const placeholder: CSSProperties =
    natural && fit > 0
      ? { width: shownWidth, height: shownHeight }
      : {
          width: Math.min(box.width, box.height * 0.75),
          height: Math.min(box.height, box.width / 0.75),
        }

  const imageStyle: CSSProperties = {
    width: natural && fit > 0 ? shownWidth : undefined,
    height: natural && fit > 0 ? shownHeight : undefined,
    transform: `translate(${view.x}px, ${view.y}px) scale(${view.scale})`,
  }

  const frameStyle: CSSProperties | undefined = swipe
    ? {
        transform: `translate(${swipe.x}px, ${swipe.y}px)`,
        opacity: swipe.y > 0 ? 1 - Math.min(swipe.y / 500, 0.5) : undefined,
      }
    : undefined

  return (
    <div
      ref={stageRef}
      className={cx(styles.stage, view.scale > 1.01 && styles.zoomed, grabbing && styles.grabbing)}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
      onDoubleClick={(event) => {
        // 触屏的双击已在 handleTouchTap 里处理
        if (lastPointer.current !== 'mouse') return
        toggleZoom(toLocal(event.clientX, event.clientY))
      }}
    >
      <div
        ref={attachFrame}
        className={cx(styles.frame, swipe && styles.dragging)}
        style={frameStyle}
      >
        {status === 'loading' && (
          <Tone loading className={styles.placeholder} style={placeholder} />
        )}
        {status !== 'error' && src && (
          <img
            key={attempt}
            data-viewer-hero
            src={src}
            alt={image.alt ?? ''}
            draggable={false}
            className={cx(styles.image, smooth && styles.smooth)}
            style={imageStyle}
            onLoad={(event) => {
              const element = event.currentTarget
              recordLoadedSize(image.url, element.naturalWidth, element.naturalHeight)
              setNatural({ width: element.naturalWidth, height: element.naturalHeight })
              setStatus('loaded')
              onShown()
            }}
            onError={() => setStatus('error')}
          />
        )}
        {status === 'error' && (
          <div className={styles.error} role="alert">
            <ImageBrokenIcon aria-hidden className={styles.errorIcon} />
            <p className={styles.errorTitle}>这张图片加载失败</p>
            <p className={styles.errorHint}>可能是源站暂时无法访问，或者图片地址已经失效。</p>
            <div className={styles.errorActions}>
              <Button
                size="sm"
                variant="secondary"
                icon={<ArrowClockwiseIcon aria-hidden />}
                onClick={() => {
                  setStatus('loading')
                  setAttempt((n) => n + 1)
                }}
              >
                重试
              </Button>
              <Button
                size="sm"
                variant="ghost"
                icon={<ArrowSquareOutIcon aria-hidden />}
                onClick={() => void openImage(image.url)}
              >
                打开原图
              </Button>
              <Button
                size="sm"
                variant="ghost"
                onClick={() => window.open(entryUrl, '_blank', 'noopener,noreferrer')}
              >
                查看原文
              </Button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
