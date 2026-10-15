import { XIcon } from '@phosphor-icons/react'
import { useEffect, useId, useRef, useState } from 'react'
import { useLocation, useNavigate } from 'react-router'
import { endpointLabel } from '../../lib/endpoint'
import { actions, useApp } from '../../prototype/store'
import type { Endpoint } from '../../prototype/types'
import { IconButton } from '../ui/Button'
import { closeEndpointDialog, endpointDialog } from './endpointDialogStore'
import { EndpointForm } from './EndpointForm'
import styles from './EndpointDialog.module.css'

/** 添加 / 编辑端点的弹窗，挂在应用外壳上 */
export function EndpointDialog() {
  const state = endpointDialog.use((s) => s)
  const endpoints = useApp((s) => s.endpoints)
  if (!state) return null
  const editing =
    state.mode === 'edit' ? endpoints.find((endpoint) => endpoint.id === state.id) : undefined
  if (state.mode === 'edit' && !editing) return null
  return <DialogFrame key={state.mode === 'edit' ? state.id : 'add'} editing={editing} />
}

function DialogFrame({ editing }: { editing?: Endpoint }) {
  const ref = useRef<HTMLDialogElement>(null)
  const [busy, setBusy] = useState(false)
  const titleId = useId()
  const navigate = useNavigate()
  const location = useLocation()

  useEffect(() => {
    const dialog = ref.current
    if (dialog && !dialog.open) dialog.showModal()
    return () => dialog?.close()
  }, [])

  // 连接过程中关闭即放弃这次连接，迟到的结果不会切换端点
  const close = () => {
    if (busy) actions.cancelConnect()
    closeEndpointDialog()
  }

  return (
    <dialog
      ref={ref}
      className={styles.dialog}
      aria-labelledby={titleId}
      onCancel={(event) => {
        event.preventDefault()
        close()
      }}
    >
      <header className={styles.header}>
        <div className={styles.titles}>
          <h2 id={titleId} className={styles.title}>
            {editing ? '编辑 API 端点' : '添加 API 端点'}
          </h2>
          <p className={styles.subtitle}>
            {editing
              ? `修改「${endpointLabel(editing)}」的地址或凭据，保存时会重新验证并切换过去。`
              : '连接 Miniflux 或 Google Reader 兼容服务，验证成功后切换到这个端点。'}
          </p>
        </div>
        <IconButton label="关闭" icon={<XIcon aria-hidden />} onClick={close} />
      </header>
      <EndpointForm
        editing={editing}
        layout="dialog"
        onBusyChange={setBusy}
        onCancel={close}
        onDone={() => {
          closeEndpointDialog()
          // 订阅页的地址属于之前的端点，切换后回到浏览页
          navigate(location.pathname === '/settings' ? '/settings' : '/', { replace: true })
        }}
      />
    </dialog>
  )
}
