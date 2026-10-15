import { ArrowClockwiseIcon, ArrowUpIcon, ImagesIcon, StackIcon } from '@phosphor-icons/react'
import { useEffect, useLayoutEffect, useRef } from 'react'
import { Button } from '../components/ui/Button'
import { Segmented } from '../components/ui/Segmented'
import { cx } from '../lib/cx'
import { actions, useApp } from '../prototype/store'
import type { ListStatus, WallMode } from '../prototype/types'
import styles from './pages.module.css'

export function StatusSwitch({
  status,
  unread,
  onChange,
}: {
  status: ListStatus
  unread: number
  onChange: (status: ListStatus) => void
}) {
  return (
    <Segmented
      label="显示范围"
      value={status}
      onChange={onChange}
      options={[
        { value: 'unread', label: '未读', count: unread },
        { value: 'all', label: '全部' },
      ]}
    />
  )
}

export function ModeSwitch({
  mode,
  onChange,
}: {
  mode: WallMode
  onChange: (mode: WallMode) => void
}) {
  return (
    <Segmented
      label="展示方式"
      value={mode}
      onChange={onChange}
      options={[
        {
          value: 'albums',
          label: (
            <>
              <StackIcon aria-hidden /> 图集
            </>
          ),
        },
        {
          value: 'images',
          label: (
            <>
              <ImagesIcon aria-hidden /> 图片流
            </>
          ),
        },
      ]}
    />
  )
}

export interface FolderChip {
  id: string
  title: string
  /** 按钮里的小号数字；为 0 或不传时不显示 */
  count?: number
}

/** 分隔线所占宽度：线 1px、左右各 4px，加上与分类按钮之间的 10px */
const DIVIDER_SPACE = 19

/**
 * 按分类筛选。分类来自 RSS 服务；不到两个分类时由调用方隐藏。
 * 按钮始终只占一行，放不下时横向滚动（桌面端可用鼠标滚轮）。
 * inline：桌面端先尝试和工具栏里前面的选项排在同一行，放不下时单独一行；移动端总是单独一行。
 */
export function FolderChips({
  chips,
  value,
  onChange,
  inline = false,
}: {
  chips: readonly FolderChip[]
  value: string | undefined
  onChange: (folderId: string | null) => void
  inline?: boolean
}) {
  const blockRef = useRef<HTMLDivElement>(null)
  const scrollerRef = useRef<HTMLDivElement>(null)
  const layoutKey = chips.map((chip) => `${chip.id}:${chip.title}:${chip.count ?? ''}`).join('|')

  // 量出按钮排成一行所需的宽度，决定和前面的选项同一行还是单独一行
  useLayoutEffect(() => {
    const block = blockRef.current
    const scroller = scrollerRef.current
    const toolbar = block?.parentElement
    if (!block || !scroller || !toolbar) return
    const measure = () => {
      let ownRow = !inline || !window.matchMedia('(min-width: 900px)').matches
      if (!ownRow) {
        const first = scroller.firstElementChild as HTMLElement | null
        const last = scroller.lastElementChild as HTMLElement | null
        const needed = first && last ? last.offsetLeft + last.offsetWidth - first.offsetLeft : 0
        const style = getComputedStyle(toolbar)
        const box = toolbar.getBoundingClientRect()
        const previous = block.previousElementSibling
        const start = previous
          ? previous.getBoundingClientRect().right + (Number.parseFloat(style.columnGap) || 0)
          : box.left + Number.parseFloat(style.paddingLeft)
        const available = box.right - Number.parseFloat(style.paddingRight) - start
        ownRow = needed + DIVIDER_SPACE > available - 2
      }
      block.dataset.ownRow = String(ownRow)
    }
    measure()
    const observer = new ResizeObserver(measure)
    observer.observe(toolbar)
    Array.from(scroller.children).forEach((chip) => observer.observe(chip))
    return () => observer.disconnect()
  }, [inline, layoutKey])

  // 选中的分类不在可视范围内时（例如从地址打开），把它滚到中间
  useLayoutEffect(() => {
    const scroller = scrollerRef.current
    const selected = scroller?.querySelector<HTMLElement>('[aria-pressed="true"]')
    if (!scroller || !selected) return
    const box = scroller.getBoundingClientRect()
    const chip = selected.getBoundingClientRect()
    if (chip.left >= box.left && chip.right <= box.right) return
    scroller.scrollLeft += chip.left - box.left - (box.width - chip.width) / 2
  }, [value, layoutKey])

  // 还能往哪边滚就在哪边渐隐；鼠标滚轮的竖向滚动换成横向，滚到头后交还页面
  useEffect(() => {
    const scroller = scrollerRef.current
    if (!scroller) return
    const update = () => {
      const max = scroller.scrollWidth - scroller.clientWidth
      const start = scroller.scrollLeft > 1
      const end = scroller.scrollLeft < max - 1
      if (start || end) scroller.dataset.fade = start && end ? 'both' : start ? 'start' : 'end'
      else delete scroller.dataset.fade
    }
    const onWheel = (event: WheelEvent) => {
      if (event.ctrlKey || Math.abs(event.deltaY) <= Math.abs(event.deltaX)) return
      const delta =
        event.deltaMode === 1
          ? event.deltaY * 16
          : event.deltaMode === 2
            ? event.deltaY * scroller.clientWidth
            : event.deltaY
      const max = scroller.scrollWidth - scroller.clientWidth
      const target = Math.min(max, Math.max(0, scroller.scrollLeft + delta))
      if (Math.abs(target - scroller.scrollLeft) < 1) return
      event.preventDefault()
      scroller.scrollLeft = target
    }
    update()
    scroller.addEventListener('scroll', update, { passive: true })
    scroller.addEventListener('wheel', onWheel, { passive: false })
    const observer = new ResizeObserver(update)
    observer.observe(scroller)
    return () => {
      scroller.removeEventListener('scroll', update)
      scroller.removeEventListener('wheel', onWheel)
      observer.disconnect()
    }
  }, [layoutKey])

  return (
    <div ref={blockRef} className={styles.chipsBlock}>
      {inline && <span className={styles.divider} aria-hidden />}
      <div ref={scrollerRef} className={styles.chips} role="group" aria-label="按分类筛选">
        <button
          type="button"
          className={styles.chip}
          aria-pressed={!value}
          onClick={() => onChange(null)}
        >
          全部订阅
        </button>
        {chips.map((chip) => (
          <button
            key={chip.id}
            type="button"
            className={styles.chip}
            aria-pressed={value === chip.id}
            onClick={() => onChange(chip.id)}
          >
            {chip.title}
            {chip.count ? <span className={styles.chipCount}>{chip.count}</span> : null}
          </button>
        ))}
      </div>
    </div>
  )
}

export function SyncButton() {
  const syncing = useApp((s) => s.sync.status === 'syncing')
  return (
    <Button
      variant="secondary"
      size="sm"
      icon={<ArrowClockwiseIcon aria-hidden className={cx(syncing && styles.spin)} />}
      onClick={() => void actions.sync({ explicit: true })}
      disabled={syncing}
      aria-label={syncing ? '正在同步' : '同步'}
    >
      <span className={styles.hideNarrow}>{syncing ? '正在同步' : '同步'}</span>
    </Button>
  )
}

/** 后台同步到的新内容：由用户决定何时放进列表，正在看的列表不会自己跳动 */
export function NewItemsPill() {
  const pending = useApp((s) => s.sync.pendingIds.length)
  if (pending === 0) return null
  return (
    <div className={styles.pillDock}>
      <button
        type="button"
        className={styles.newPill}
        onClick={() => {
          actions.applyPending()
          window.scrollTo({ top: 0 })
        }}
      >
        <ArrowUpIcon weight="bold" aria-hidden />
        {pending} 个新图集
      </button>
    </div>
  )
}
