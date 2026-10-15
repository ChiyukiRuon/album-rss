import { useState } from 'react'
import { useLocation, useNavigate } from 'react-router'
import { actions, useApp } from '../../prototype/store'
import styles from './EndpointSelect.module.css'

export function EndpointSelect() {
  const endpoints = useApp((state) => state.endpoints)
  const session = useApp((state) => state.session)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const navigate = useNavigate()
  const location = useLocation()

  return (
    <div className={styles.control}>
      <select
        className={styles.select}
        aria-label="切换 API 端点"
        value={session?.id ?? ''}
        disabled={busy}
        onChange={async (event) => {
          const id = event.target.value
          if (id === 'add') {
            navigate('/connect?add')
            return
          }
          setBusy(true)
          setError('')
          try {
            await actions.switchEndpoint(id)
            navigate(location.pathname === '/settings' ? '/settings' : '/', { replace: true })
          } catch (error) {
            setError(error instanceof Error ? error.message : '切换失败，请重试')
          } finally {
            setBusy(false)
          }
        }}
      >
        {!session?.id && (
          <option value="">{session?.kind === 'demo' ? '演示数据' : '选择端点'}</option>
        )}
        {endpoints.map((endpoint) => (
          <option key={endpoint.id} value={endpoint.id}>
            {endpoint.name || endpoint.server}
          </option>
        ))}
        <option value="add">＋ 添加 API 端点</option>
      </select>
      {busy && <p role="status">正在连接…</p>}
      {error && (
        <p className={styles.error} role="alert">
          {error}
        </p>
      )}
    </div>
  )
}
