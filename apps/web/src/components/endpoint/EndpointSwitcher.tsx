import { CaretUpDownIcon, CheckIcon, CircleNotchIcon, PlusIcon } from '@phosphor-icons/react'
import { useEffect, useEffectEvent, useId, useRef, useState, type KeyboardEvent } from 'react'
import { useLocation, useNavigate } from 'react-router'
import { cx } from '../../lib/cx'
import { endpointDetail, endpointLabel } from '../../lib/endpoint'
import { actions, useApp } from '../../prototype/store'
import type { Endpoint } from '../../prototype/types'
import { openEndpointDialog } from './endpointDialogStore'
import styles from './EndpointSwitcher.module.css'

/** 名称的第一个字，作为端点的标记 */
function monogram(endpoint: Endpoint) {
  return Array.from(endpointLabel(endpoint))[0]?.toUpperCase() ?? '?'
}

/** 桌面端左下角：显示当前端点，点击后向上弹出切换菜单 */
export function EndpointSwitcher() {
  const endpoint = useApp((s) => s.endpoint)
  const endpoints = useApp((s) => s.endpoints)
  const [open, setOpen] = useState(false)
  const [switching, setSwitching] = useState<string | null>(null)
  const [error, setError] = useState('')
  const wrapRef = useRef<HTMLDivElement>(null)
  const triggerRef = useRef<HTMLButtonElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)
  const menuId = useId()
  const navigate = useNavigate()
  const location = useLocation()

  const dismiss = (restoreFocus: boolean) => {
    setOpen(false)
    setError('')
    if (restoreFocus) triggerRef.current?.focus()
  }
  const onOutside = useEffectEvent((event: PointerEvent) => {
    if (!wrapRef.current?.contains(event.target as Node)) dismiss(false)
  })

  useEffect(() => {
    if (!open) return
    const outside = (event: PointerEvent) => onOutside(event)
    document.addEventListener('pointerdown', outside)
    // 打开时聚焦当前端点，方便直接用方向键选择
    const menu = menuRef.current
    const current = menu?.querySelector<HTMLElement>('[aria-checked="true"]')
    ;(current ?? menu?.querySelector<HTMLElement>('[role^="menuitem"]'))?.focus()
    return () => document.removeEventListener('pointerdown', outside)
  }, [open])

  if (!endpoint) return null

  const choose = async (id: string) => {
    if (id === endpoint.id) {
      dismiss(true)
      return
    }
    setSwitching(id)
    setError('')
    try {
      await actions.switchEndpoint(id)
      setOpen(false)
      // 订阅页的地址属于之前的端点，切换后回到浏览页
      navigate(location.pathname === '/settings' ? '/settings' : '/', { replace: true })
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '切换失败，请重试')
    } finally {
      setSwitching(null)
    }
  }

  const onMenuKey = (event: KeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      dismiss(true)
      return
    }
    if (event.key === 'Tab') {
      dismiss(false)
      return
    }
    const items = [
      ...(menuRef.current?.querySelectorAll<HTMLButtonElement>(
        '[role^="menuitem"]:not(:disabled)',
      ) ?? []),
    ]
    const index = items.indexOf(document.activeElement as HTMLButtonElement)
    const target =
      event.key === 'ArrowDown'
        ? items[(index + 1) % items.length]
        : event.key === 'ArrowUp'
          ? items[(index - 1 + items.length) % items.length]
          : event.key === 'Home'
            ? items[0]
            : event.key === 'End'
              ? items.at(-1)
              : undefined
    if (!target) return
    event.preventDefault()
    target.focus()
  }

  // 演示数据不在端点列表里，正在使用时放在最上面
  const rows = endpoint.kind === 'demo' ? [endpoint, ...endpoints] : endpoints

  return (
    <div ref={wrapRef} className={styles.wrap}>
      {open && (
        <div
          ref={menuRef}
          id={menuId}
          role="menu"
          aria-label="切换 API 端点"
          className={styles.menu}
          onKeyDown={onMenuKey}
        >
          <p className={styles.heading} aria-hidden>
            API 端点
          </p>
          <div className={styles.list}>
            {rows.map((item) => {
              const current = item.id === endpoint.id
              return (
                <button
                  key={item.id}
                  type="button"
                  role="menuitemradio"
                  aria-checked={current}
                  className={styles.item}
                  disabled={switching !== null && switching !== item.id}
                  title={item.kind === 'demo' ? undefined : item.server}
                  onClick={() => void choose(item.id)}
                >
                  <span className={cx(styles.tile, current && styles.tileCurrent)} aria-hidden>
                    {monogram(item)}
                  </span>
                  <span className={styles.text}>
                    <span className={styles.name}>{endpointLabel(item)}</span>
                    <span className={styles.detail}>{endpointDetail(item)}</span>
                  </span>
                  <span className={styles.mark} aria-hidden>
                    {switching === item.id ? (
                      <CircleNotchIcon className={styles.spin} />
                    ) : current ? (
                      <CheckIcon weight="bold" />
                    ) : null}
                  </span>
                </button>
              )
            })}
          </div>
          {switching && (
            <p className={styles.status} role="status">
              正在读取订阅和最新文章…
            </p>
          )}
          {error && (
            <p className={styles.error} role="alert">
              {error}
            </p>
          )}
          <div className={styles.separator} role="separator" />
          <button
            type="button"
            role="menuitem"
            className={styles.item}
            disabled={switching !== null}
            onClick={() => {
              dismiss(false)
              openEndpointDialog({ mode: 'add' })
            }}
          >
            <span className={cx(styles.tile, styles.tileAdd)} aria-hidden>
              <PlusIcon weight="bold" />
            </span>
            <span className={styles.name}>添加 API 端点</span>
          </button>
        </div>
      )}
      <button
        ref={triggerRef}
        type="button"
        className={styles.trigger}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        aria-label={`切换 API 端点，当前：${endpointLabel(endpoint)}`}
        title={endpoint.kind === 'demo' ? undefined : endpoint.server}
        onClick={() => (open ? dismiss(false) : setOpen(true))}
      >
        <span className={cx(styles.dot, endpoint.kind === 'demo' && styles.dotDemo)} aria-hidden />
        <span className={styles.text}>
          <span className={styles.name}>{endpointLabel(endpoint)}</span>
          <span className={styles.detail}>{endpointDetail(endpoint)}</span>
        </span>
        <CaretUpDownIcon className={styles.caret} weight="bold" aria-hidden />
      </button>
    </div>
  )
}
