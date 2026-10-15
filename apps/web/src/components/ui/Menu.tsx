import { useEffect, useEffectEvent, useId, useRef, useState, type ReactNode } from 'react'
import { cx } from '../../lib/cx'
import { IconButton } from './Button'
import styles from './Menu.module.css'

export interface MenuItem {
  label: string
  icon?: ReactNode
  onSelect: () => void
  hidden?: boolean
}

interface MenuProps {
  label: string
  icon: ReactNode
  items: MenuItem[]
  /** 深色查看器里使用 */
  dark?: boolean
}

export function Menu({ label, icon, items, dark }: MenuProps) {
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)
  const menuId = useId()

  const onOutside = useEffectEvent((event: PointerEvent) => {
    if (!wrapRef.current?.contains(event.target as Node)) setOpen(false)
  })
  const onKey = useEffectEvent((event: KeyboardEvent) => {
    if (event.key !== 'Escape') return
    // 先于查看器处理 Esc，只关闭菜单
    event.preventDefault()
    event.stopPropagation()
    setOpen(false)
    wrapRef.current?.querySelector<HTMLButtonElement>('button')?.focus()
  })

  useEffect(() => {
    if (!open) return
    const outside = (event: PointerEvent) => onOutside(event)
    const key = (event: KeyboardEvent) => onKey(event)
    document.addEventListener('pointerdown', outside)
    window.addEventListener('keydown', key, true)
    wrapRef.current?.querySelector<HTMLButtonElement>('[role="menuitem"]')?.focus()
    return () => {
      document.removeEventListener('pointerdown', outside)
      window.removeEventListener('keydown', key, true)
    }
  }, [open])

  return (
    <div ref={wrapRef} className={styles.wrap}>
      <IconButton
        label={label}
        icon={icon}
        variant={dark ? 'viewer' : 'ghost'}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        onClick={() => setOpen((value) => !value)}
      />
      {open && (
        <div
          id={menuId}
          role="menu"
          aria-label={label}
          className={cx(styles.menu, dark && styles.dark)}
        >
          {items
            .filter((item) => !item.hidden)
            .map((item) => (
              <button
                key={item.label}
                type="button"
                role="menuitem"
                className={styles.item}
                onClick={() => {
                  setOpen(false)
                  item.onSelect()
                }}
              >
                {item.icon}
                {item.label}
              </button>
            ))}
        </div>
      )}
    </div>
  )
}
