import {
  CheckIcon,
  CircleNotchIcon,
  EyeIcon,
  EyeSlashIcon,
  WarningCircleIcon,
  XIcon,
} from '@phosphor-icons/react'
import { useEffect, useId, useRef, useState, type FormEvent } from 'react'
import { cx } from '../../lib/cx'
import { actions } from '../../prototype/store'
import type { Endpoint, ServiceKind } from '../../prototype/types'
import { Button } from '../ui/Button'
import { Segmented } from '../ui/Segmented'
import styles from './EndpointForm.module.css'

type StepStatus = 'waiting' | 'running' | 'done' | 'failed'

interface Attempt {
  host: string
  origin: string
  insecure: boolean
  statuses: StepStatus[]
  error?: string
}

function stepLabels(service: ServiceKind) {
  return [
    '连接服务',
    service === 'miniflux' ? '验证 API 密钥' : '登录并换取访问令牌',
    '读取订阅和最新文章',
  ]
}

interface EndpointFormProps {
  /** 编辑已有端点；不传时添加新端点 */
  editing?: Endpoint
  /** page：首次连接的整页表单；dialog：弹窗里，按钮靠右 */
  layout: 'page' | 'dialog'
  onDone: () => void
  /** 提供时显示“取消” */
  onCancel?: () => void
  onBusyChange?: (busy: boolean) => void
}

/** 添加或编辑 API 端点：验证连接、读取订阅后切换到这个端点 */
export function EndpointForm({
  editing,
  layout,
  onDone,
  onCancel,
  onBusyChange,
}: EndpointFormProps) {
  const [name, setName] = useState(editing?.name ?? '')
  const [service, setService] = useState<ServiceKind>(editing?.service ?? 'miniflux')
  const [server, setServer] = useState(editing?.server ?? '')
  const [apiKey, setApiKey] = useState(editing?.service === 'miniflux' ? (editing.token ?? '') : '')
  const [username, setUsername] = useState(editing?.username ?? '')
  const [password, setPassword] = useState('')
  const [showSecret, setShowSecret] = useState(false)
  const [remember, setRemember] = useState(editing?.remember ?? false)
  const [mediaOrigin, setMediaOrigin] = useState(editing?.mediaOrigin ?? '')
  const [fieldError, setFieldError] = useState<string | null>(null)
  const [attempt, setAttempt] = useState<Attempt | null>(null)
  const id = useId()
  const ids = {
    name: `${id}-name`,
    server: `${id}-server`,
    media: `${id}-media`,
    secret: `${id}-secret`,
    user: `${id}-user`,
    remember: `${id}-remember`,
    error: `${id}-error`,
  }
  const mountedRef = useRef(true)
  useEffect(() => {
    mountedRef.current = true
    return () => {
      mountedRef.current = false
    }
  }, [])

  const busy = attempt?.statuses.some((s) => s === 'running') ?? false
  const failed = attempt?.statuses.includes('failed') ?? false
  useEffect(() => onBusyChange?.(busy), [busy, onBusyChange])

  // 失败说明出现在表单末尾，滚动到能看到它的位置
  const failureRef = useRef<HTMLDivElement>(null)
  const failure = failed ? attempt?.error : undefined
  useEffect(() => {
    if (failure) failureRef.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
  }, [failure])

  const onSubmit = async (event: FormEvent) => {
    event.preventDefault()
    let url: URL
    try {
      url = new URL(server.trim())
    } catch {
      setFieldError('请输入完整的地址，例如 https://rss.example.com')
      return
    }
    if (url.protocol !== 'https:' && url.protocol !== 'http:') {
      setFieldError('地址需要以 http:// 或 https:// 开头')
      return
    }
    // Google Reader：地址和用户名不变、没填新密码时沿用已保存的令牌
    const token =
      editing?.service === service &&
      editing.server === server.trim().replace(/\/+$/, '') &&
      editing.username === username.trim() &&
      !password
        ? editing.token
        : undefined
    if (service === 'miniflux' ? !apiKey.trim() : !username.trim() || (!password && !token)) {
      setFieldError(service === 'miniflux' ? '请填写 API 密钥' : '请填写用户名和密码')
      return
    }
    setFieldError(null)

    const base = {
      host: url.host,
      origin: url.origin,
      insecure: window.location.protocol === 'https:' && url.protocol === 'http:',
    }
    const statuses: StepStatus[] = ['running', 'waiting', 'waiting']
    let current = 0
    setAttempt({ ...base, statuses: [...statuses] })
    try {
      await actions.connect({
        id: editing?.id,
        name,
        token,
        service,
        server: url.href,
        username,
        remember,
        apiKey,
        password,
        mediaOrigin: service === 'miniflux' ? mediaOrigin.trim() : undefined,
        onStep: (step) => {
          current = step
          for (let i = 0; i < statuses.length; i++)
            statuses[i] = i < step ? 'done' : i === step ? 'running' : 'waiting'
          if (mountedRef.current) setAttempt({ ...base, statuses: [...statuses] })
        },
      })
      if (!mountedRef.current) return
      setPassword('')
      setApiKey('')
      setAttempt(null)
      onDone()
    } catch (error) {
      if (!mountedRef.current) return
      statuses[current] = 'failed'
      setAttempt({
        ...base,
        statuses: [...statuses],
        error: error instanceof Error ? error.message : '连接失败，请重试',
      })
    }
  }

  return (
    <form className={cx(styles.form, styles[layout])} onSubmit={onSubmit} noValidate>
      <div className={styles.scroll}>
        <fieldset disabled={busy} className={styles.fieldset}>
          <div className={styles.field}>
            <span className={styles.label}>服务类型</span>
            <Segmented
              label="服务类型"
              value={service}
              onChange={(value) => {
                setService(value)
                setAttempt(null)
              }}
              options={[
                { value: 'miniflux', label: 'Miniflux' },
                { value: 'greader', label: 'Google Reader 兼容' },
              ]}
            />
          </div>

          <div className={styles.field}>
            <label className={styles.label} htmlFor={ids.server}>
              服务地址
            </label>
            <input
              id={ids.server}
              className={styles.input}
              type="url"
              inputMode="url"
              autoComplete="url"
              autoFocus={layout === 'dialog' && !editing}
              placeholder={
                service === 'miniflux'
                  ? 'https://rss.example.com'
                  : 'https://rss.example.com/api/greader.php'
              }
              value={server}
              onChange={(event) => setServer(event.target.value)}
              aria-describedby={fieldError ? ids.error : undefined}
              aria-invalid={Boolean(fieldError)}
            />
          </div>

          {service === 'greader' && (
            <div className={styles.field}>
              <label className={styles.label} htmlFor={ids.user}>
                用户名
              </label>
              <input
                id={ids.user}
                className={styles.input}
                autoComplete="username"
                value={username}
                onChange={(event) => setUsername(event.target.value)}
              />
            </div>
          )}

          <div className={styles.field}>
            <label className={styles.label} htmlFor={ids.secret}>
              {service === 'miniflux' ? 'API 密钥' : '密码'}
            </label>
            <div className={styles.secret}>
              <input
                id={ids.secret}
                className={styles.input}
                type={showSecret ? 'text' : 'password'}
                autoComplete={service === 'miniflux' ? 'off' : 'current-password'}
                spellCheck={false}
                value={service === 'miniflux' ? apiKey : password}
                onChange={(event) =>
                  service === 'miniflux'
                    ? setApiKey(event.target.value)
                    : setPassword(event.target.value)
                }
              />
              <button
                type="button"
                className={styles.reveal}
                aria-label={showSecret ? '隐藏' : '显示'}
                aria-pressed={showSecret}
                onClick={() => setShowSecret((value) => !value)}
              >
                {showSecret ? <EyeSlashIcon aria-hidden /> : <EyeIcon aria-hidden />}
              </button>
            </div>
            <p className={styles.help}>
              {service === 'miniflux'
                ? '在 Miniflux 的“设置 → API 密钥”里创建。'
                : editing
                  ? '地址和用户名不变时，可留空以保留现有令牌；密码不会被保存。'
                  : '密码只用来换取访问令牌，不会被保存。服务地址需包含 API 路径。'}
            </p>
          </div>

          <div className={styles.field}>
            <label className={styles.label} htmlFor={ids.name}>
              端点名称（可选）
            </label>
            <input
              id={ids.name}
              className={styles.input}
              value={name}
              placeholder="例如：插画订阅"
              onChange={(event) => setName(event.target.value)}
            />
          </div>

          {service === 'miniflux' && (
            <div className={styles.field}>
              <label className={styles.label} htmlFor={ids.media}>
                服务公开地址（可选）
              </label>
              <input
                id={ids.media}
                className={styles.input}
                type="url"
                placeholder="https://rss.example.com"
                value={mediaOrigin}
                onChange={(event) => setMediaOrigin(event.target.value)}
              />
              <p className={styles.help}>
                通过本机地址连接时，可填写 Miniflux 配置的公开地址，将其 /proxy/ 图片指向当前服务。
              </p>
            </div>
          )}

          <label className={styles.check} htmlFor={ids.remember}>
            <input
              id={ids.remember}
              type="checkbox"
              checked={remember}
              onChange={(event) => setRemember(event.target.checked)}
            />
            <span>
              <span className={styles.checkLabel}>在此浏览器保存凭据</span>
              <span className={styles.help}>
                凭据保存在本机浏览器里，删除这个端点时清除。不勾选时只保存在内存中，刷新页面后这个端点会被移除。
              </span>
            </span>
          </label>

          {fieldError && (
            <p id={ids.error} className={styles.fieldError} role="alert">
              {fieldError}
            </p>
          )}

          {attempt && (
            <ol className={styles.steps} aria-label="连接进度">
              {stepLabels(service).map((label, i) => (
                <li
                  key={label}
                  className={cx(styles.step, styles[attempt.statuses[i] ?? 'waiting'])}
                >
                  <StepIcon status={attempt.statuses[i] ?? 'waiting'} />
                  {label}
                </li>
              ))}
            </ol>
          )}

          {attempt && failed && (
            <div ref={failureRef} className={styles.failure} role="alert">
              <p className={styles.failureTitle}>
                <WarningCircleIcon weight="fill" aria-hidden />
                无法连接到 {attempt.host}
              </p>
              <p className={styles.failureText}>{attempt.error}</p>
              <ul className={styles.causes}>
                <li>这台设备访问不到这个地址。可以在新标签页打开 {attempt.origin} 确认。</li>
                <li>服务器证书无效或已过期。</li>
                <li>
                  服务没有允许这个页面跨域访问（CORS）。Miniflux 的原生 API 默认允许；Google Reader
                  兼容接口通常需要在服务入口另外配置。
                </li>
                {attempt.insecure && (
                  <li>这个页面使用 HTTPS，浏览器可能会阻止它连接 HTTP 地址。</li>
                )}
              </ul>
            </div>
          )}
        </fieldset>
      </div>

      <div className={styles.actions}>
        {onCancel && (
          <Button size={layout === 'page' ? 'lg' : 'md'} onClick={onCancel}>
            取消
          </Button>
        )}
        <Button
          type="submit"
          variant="primary"
          size={layout === 'page' ? 'lg' : 'md'}
          disabled={busy}
          className={styles.submit}
        >
          {busy ? '正在连接…' : editing ? '保存并连接' : '连接'}
        </Button>
      </div>
    </form>
  )
}

function StepIcon({ status }: { status: StepStatus }) {
  if (status === 'running')
    return <CircleNotchIcon aria-label="进行中" className={styles.spinner} />
  if (status === 'done') return <CheckIcon aria-label="完成" weight="bold" />
  if (status === 'failed') return <XIcon aria-label="失败" weight="bold" />
  return <span className={styles.pending} aria-label="等待" />
}
