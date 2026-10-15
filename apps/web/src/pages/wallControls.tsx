import { ArrowClockwiseIcon, ArrowUpIcon, ImagesIcon, StackIcon } from '@phosphor-icons/react'
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
