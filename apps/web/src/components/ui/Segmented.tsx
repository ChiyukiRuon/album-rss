import { useRef, type KeyboardEvent, type ReactNode } from 'react'
import { cx } from '../../lib/cx'
import styles from './Segmented.module.css'

export interface SegmentedOption<V extends string> {
  value: V
  label: ReactNode
  /** 选项后面的小号数字 */
  count?: number
}

interface SegmentedProps<V extends string> {
  label: string
  options: readonly SegmentedOption<V>[]
  value: V
  onChange: (value: V) => void
  size?: 'sm' | 'md'
  className?: string
}

/** 分段选择，键盘上用左右方向键切换 */
export function Segmented<V extends string>({
  label,
  options,
  value,
  onChange,
  size = 'md',
  className,
}: SegmentedProps<V>) {
  const groupRef = useRef<HTMLDivElement>(null)

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return
    event.preventDefault()
    const index = options.findIndex((o) => o.value === value)
    const step = event.key === 'ArrowRight' ? 1 : -1
    const next = options[(index + step + options.length) % options.length]
    if (!next) return
    onChange(next.value)
    const buttons = groupRef.current?.querySelectorAll<HTMLButtonElement>('[role="radio"]')
    buttons?.[options.indexOf(next)]?.focus()
  }

  return (
    <div
      ref={groupRef}
      role="radiogroup"
      aria-label={label}
      className={cx(styles.group, styles[size], className)}
      onKeyDown={onKeyDown}
    >
      {options.map((option) => {
        const selected = option.value === value
        return (
          <button
            key={option.value}
            type="button"
            role="radio"
            aria-checked={selected}
            tabIndex={selected ? 0 : -1}
            className={cx(styles.option, selected && styles.selected)}
            onClick={() => onChange(option.value)}
          >
            {option.label}
            {option.count !== undefined && <span className={styles.count}>{option.count}</span>}
          </button>
        )
      })}
    </div>
  )
}
