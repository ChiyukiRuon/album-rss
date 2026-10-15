import { useEffect, useEffectEvent, useRef, useState, type ReactNode } from 'react'
import { Button } from './Button'
import styles from './ConfirmButton.module.css'

interface ConfirmButtonProps {
  label: string
  icon?: ReactNode
  /** 弹出确认时的说明 */
  message: ReactNode
  confirmLabel: string
  variant?: 'secondary' | 'danger'
  disabled?: boolean
  onConfirm: () => void
}

/** 需要二次确认的操作：在按钮下方弹出简短说明 */
export function ConfirmButton({
  label,
  icon,
  message,
  confirmLabel,
  variant = 'secondary',
  disabled,
  onConfirm,
}: ConfirmButtonProps) {
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)

  const onOutside = useEffectEvent((event: PointerEvent) => {
    if (!wrapRef.current?.contains(event.target as Node)) setOpen(false)
  })
  const onKey = useEffectEvent((event: KeyboardEvent) => {
    if (event.key === 'Escape') setOpen(false)
  })

  useEffect(() => {
    if (!open) return
    const outside = (event: PointerEvent) => onOutside(event)
    const key = (event: KeyboardEvent) => onKey(event)
    document.addEventListener('pointerdown', outside)
    window.addEventListener('keydown', key)
    return () => {
      document.removeEventListener('pointerdown', outside)
      window.removeEventListener('keydown', key)
    }
  }, [open])

  return (
    <div ref={wrapRef} className={styles.wrap}>
      <Button
        size="sm"
        variant={variant}
        icon={icon}
        disabled={disabled}
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
      >
        {label}
      </Button>
      {open && (
        <div className={styles.pop} role="dialog" aria-label={label}>
          <p className={styles.message}>{message}</p>
          <div className={styles.actions}>
            <Button size="sm" variant="ghost" onClick={() => setOpen(false)}>
              取消
            </Button>
            <Button
              size="sm"
              variant={variant === 'danger' ? 'danger' : 'primary'}
              onClick={() => {
                setOpen(false)
                onConfirm()
              }}
            >
              {confirmLabel}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
