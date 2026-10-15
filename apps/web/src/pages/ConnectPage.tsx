import {
  CheckIcon,
  CircleNotchIcon,
  EyeIcon,
  EyeSlashIcon,
  WarningCircleIcon,
  XIcon,
} from '@phosphor-icons/react'
import { useId, useMemo, useState, type FormEvent } from 'react'
import { Navigate, useNavigate, useSearchParams } from 'react-router'
import { Wordmark } from '../components/shell/Logo'
import { EndpointSelect } from '../components/shell/EndpointSelect'
import { Button } from '../components/ui/Button'
import { ImageThumb } from '../components/ui/ImageThumb'
import { Segmented } from '../components/ui/Segmented'
import { cx } from '../lib/cx'
import { demoSize } from '../prototype/art'
import { hasImages } from '../prototype/selectors'
import { actions, useApp } from '../prototype/store'
import type { ImageAsset, ServiceKind } from '../prototype/types'
import styles from './ConnectPage.module.css'

type StepStatus = 'waiting' | 'running' | 'done' | 'failed'

interface Attempt {
  host: string
  origin: string
  insecure: boolean
  statuses: StepStatus[]
  error?: string
}

function stepLabels(service: ServiceKind) {
  return ['连接服务', service === 'miniflux' ? '验证 API 密钥' : '登录并换取访问令牌', '读取订阅']
}

export function ConnectPage() {
  const session = useApp((s) => s.session)
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const endpoints = useApp((s) => s.endpoints)
  const editing = endpoints.find((endpoint) => endpoint.id === params.get('edit'))
  const managing = params.has('add') || Boolean(editing)
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
  const ids = { server: useId(), secret: useId(), user: useId(), remember: useId(), error: useId() }

  if (session && !managing) return <Navigate to="/" replace />

  const busy = attempt?.statuses.some((s) => s === 'running') ?? false
  const failed = attempt?.statuses.includes('failed') ?? false

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
    const statuses: StepStatus[] = ['waiting', 'waiting', 'waiting']
    let current = 0
    statuses[0] = 'running'
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
          setAttempt({ ...base, statuses: [...statuses] })
        },
      })
      setPassword('')
      setApiKey('')
      navigate(managing ? '/settings' : '/', { replace: true })
    } catch (error) {
      statuses[current] = 'failed'
      setAttempt({
        ...base,
        statuses: [...statuses],
        error: error instanceof Error ? error.message : '连接失败，请重试',
      })
    }
  }

  return (
    <div className={styles.page}>
      <div className={styles.formSide}>
        <Wordmark />
        <h1 className={styles.title}>
          {editing ? '编辑 API 端点' : managing ? '添加 API 端点' : '连接你的 RSS 服务'}
        </h1>
        <p className={styles.lead}>
          Album RSS 把订阅里的插画和照片整理成图集。它直接在浏览器里连接你已有的 Miniflux 或 Google
          Reader 兼容服务，不经过任何中转服务器。
        </p>

        {!session && endpoints.length > 0 && <EndpointSelect />}

        <form className={styles.form} onSubmit={onSubmit} noValidate>
          <fieldset
            disabled={busy}
            style={{ border: 0, padding: 0, margin: 0, display: 'contents' }}
          >
            <div className={styles.field}>
              <label className={styles.label} htmlFor={`${ids.server}-name`}>
                端点名称（可选）
              </label>
              <input
                id={`${ids.server}-name`}
                className={styles.input}
                value={name}
                placeholder="例如：插画订阅"
                onChange={(event) => setName(event.target.value)}
              />
            </div>
            <div className={styles.field}>
              <span className={styles.label} id={`${ids.server}-kind`}>
                服务类型
              </span>
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

            {service === 'miniflux' && (
              <div className={styles.field}>
                <label className={styles.label} htmlFor={`${ids.server}-media`}>
                  服务公开地址（可选）
                </label>
                <input
                  id={`${ids.server}-media`}
                  className={styles.input}
                  type="url"
                  placeholder="https://rss.example.com"
                  value={mediaOrigin}
                  onChange={(event) => setMediaOrigin(event.target.value)}
                />
                <p className={styles.help}>
                  通过本机地址连接时，可填写 Miniflux 配置的公开地址，将其 /proxy/
                  图片指向当前服务。
                </p>
              </div>
            )}

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
                placeholder="https://rss.example.com"
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
                    : '密码只用来换取访问令牌，不会被保存。服务地址需包含 API 路径，例如 https://rss.example.com/api/greader.php。'}
              </p>
            </div>

            <label className={styles.check} htmlFor={ids.remember}>
              <input
                id={ids.remember}
                type="checkbox"
                checked={remember}
                onChange={(event) => setRemember(event.target.checked)}
              />
              <span>
                <span className={styles.checkLabel}>在这个浏览器上记住登录</span>
                <span className={styles.help}>
                  令牌会保存在本机浏览器里，直到你退出登录。不勾选时只保存在内存中，刷新页面后需要重新连接。
                </span>
              </span>
            </label>

            {fieldError && (
              <p id={ids.error} className={styles.fieldError} role="alert">
                {fieldError}
              </p>
            )}

            <Button
              type="submit"
              variant="primary"
              size="lg"
              disabled={busy}
              className={styles.submit}
            >
              {busy ? '正在连接…' : editing ? '保存并连接' : '连接'}
            </Button>
            {managing && (
              <Button disabled={busy} onClick={() => navigate('/settings')}>
                取消
              </Button>
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
              <div className={styles.failure} role="alert">
                <p className={styles.failureTitle}>
                  <WarningCircleIcon weight="fill" aria-hidden />
                  无法连接到 {attempt.host}
                </p>
                <p className={styles.failureText}>{attempt.error}</p>
                <ul className={styles.causes}>
                  <li>这台设备访问不到这个地址。可以在新标签页打开 {attempt.origin} 确认。</li>
                  <li>服务器证书无效或已过期。</li>
                  <li>
                    服务没有允许这个页面跨域访问（CORS）。Miniflux 的原生 API 默认允许；Google
                    Reader 兼容接口通常需要在服务入口另外配置。
                  </li>
                  {attempt.insecure && (
                    <li>这个页面使用 HTTPS，浏览器可能会阻止它连接 HTTP 地址。</li>
                  )}
                </ul>
              </div>
            )}
          </fieldset>
        </form>

        {!managing && (
          <button
            type="button"
            className={styles.demo}
            disabled={busy}
            onClick={() => {
              actions.enterDemo()
              navigate('/', { replace: true })
            }}
          >
            先用演示数据看看
          </button>
        )}
        <p className={styles.footnote}>连接后将读取服务里的订阅和文章；已读与收藏会回写到服务。</p>
      </div>

      <PreviewWall />
    </div>
  )
}

function StepIcon({ status }: { status: StepStatus }) {
  if (status === 'running')
    return <CircleNotchIcon aria-label="进行中" className={styles.spinner} />
  if (status === 'done') return <CheckIcon aria-label="完成" weight="bold" />
  if (status === 'failed') return <XIcon aria-label="失败" weight="bold" />
  return <span className={styles.pending} aria-label="等待" />
}

/** 右侧的展示墙：演示数据里最新的一批封面 */
function PreviewWall() {
  const entries = useApp((s) => s.entries)
  const order = useApp((s) => s.order)
  const covers = useMemo(() => {
    const list: ImageAsset[] = []
    for (const id of order) {
      const entry = entries[id]
      if (entry && hasImages(entry) && entry.images[0]) list.push(entry.images[0])
      if (list.length === 15) break
    }
    return list
  }, [order, entries])

  return (
    <div className={styles.wallSide} aria-hidden>
      <div className={styles.wall}>
        {[0, 1, 2].map((column) => (
          <div key={column} className={styles.wallColumn}>
            {covers
              .filter((_, i) => i % 3 === column)
              .map((cover) => (
                <WallTile key={cover.key} cover={cover} />
              ))}
          </div>
        ))}
      </div>
    </div>
  )
}

function WallTile({ cover }: { cover: ImageAsset }) {
  const size = demoSize(cover.url)
  const ratio = size ? Math.min(1.8, Math.max(0.6, size.height / size.width)) : 1.33
  return (
    <div className={styles.tile} style={{ aspectRatio: `1 / ${ratio}` }}>
      <ImageThumb url={cover.url} className={styles.tileImage} />
    </div>
  )
}
