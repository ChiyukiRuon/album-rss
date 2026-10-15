import { CaretRightIcon, CircleNotchIcon } from '@phosphor-icons/react'
import { useMemo, useState } from 'react'
import { Navigate, useNavigate } from 'react-router'
import { EndpointForm } from '../components/endpoint/EndpointForm'
import { Wordmark } from '../components/shell/Logo'
import { ImageThumb } from '../components/ui/ImageThumb'
import { endpointDetail, endpointLabel } from '../lib/endpoint'
import { demoSize } from '../prototype/art'
import { hasImages } from '../prototype/selectors'
import { actions, useApp } from '../prototype/store'
import type { ImageAsset } from '../prototype/types'
import styles from './ConnectPage.module.css'

/** 还没有正在使用的端点时的入口：选择已保存的端点，或添加一个新的 */
export function ConnectPage() {
  const endpoint = useApp((s) => s.endpoint)
  const endpoints = useApp((s) => s.endpoints)
  const navigate = useNavigate()
  const [busy, setBusy] = useState(false)

  if (endpoint) return <Navigate to="/" replace />

  return (
    <div className={styles.page}>
      <div className={styles.formSide}>
        <Wordmark />
        <h1 className={styles.title}>连接你的 RSS 服务</h1>
        <p className={styles.lead}>
          Album RSS 把订阅里的插画和照片整理成图集。它直接在浏览器里连接你已有的 Miniflux 或 Google
          Reader 兼容服务，不经过任何中转服务器。
        </p>

        {endpoints.length > 0 && <SavedEndpoints disabled={busy} />}

        {endpoints.length > 0 && <h2 className={styles.sectionTitle}>添加 API 端点</h2>}
        <EndpointForm
          layout="page"
          onBusyChange={setBusy}
          onDone={() => navigate('/', { replace: true })}
        />

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
        <p className={styles.footnote}>
          连接后先读取订阅和最新一页文章，更早的文章在浏览时按需读取；已读与收藏会回写到服务。
        </p>
      </div>

      <PreviewWall />
    </div>
  )
}

/** 浏览器里保存过的端点，点一下直接连接 */
function SavedEndpoints({ disabled }: { disabled: boolean }) {
  const endpoints = useApp((s) => s.endpoints)
  const navigate = useNavigate()
  const [connecting, setConnecting] = useState<string | null>(null)
  const [error, setError] = useState('')

  return (
    <section className={styles.saved} aria-labelledby="saved-endpoints">
      <h2 id="saved-endpoints" className={styles.sectionTitle}>
        已保存的端点
      </h2>
      <ul className={styles.savedList}>
        {endpoints.map((item) => (
          <li key={item.id}>
            <button
              type="button"
              className={styles.savedItem}
              disabled={disabled || (connecting !== null && connecting !== item.id)}
              onClick={async () => {
                setConnecting(item.id)
                setError('')
                try {
                  await actions.switchEndpoint(item.id)
                  navigate('/', { replace: true })
                } catch (reason) {
                  setError(reason instanceof Error ? reason.message : '连接失败，请重试')
                } finally {
                  setConnecting(null)
                }
              }}
            >
              <span className={styles.savedTile} aria-hidden>
                {Array.from(endpointLabel(item))[0]?.toUpperCase()}
              </span>
              <span className={styles.savedText}>
                <span className={styles.savedName}>{endpointLabel(item)}</span>
                <span className={styles.savedDetail}>{endpointDetail(item)}</span>
              </span>
              {connecting === item.id ? (
                <CircleNotchIcon className={styles.spinner} aria-label="正在连接" />
              ) : (
                <CaretRightIcon aria-hidden />
              )}
            </button>
          </li>
        ))}
      </ul>
      {error && (
        <p className={styles.savedError} role="alert">
          {error}
        </p>
      )}
    </section>
  )
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
