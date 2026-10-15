import { ArrowSquareOutIcon, GithubLogoIcon, PlusIcon, TrashIcon } from '@phosphor-icons/react'
import { useId, useState, type ReactNode } from 'react'
import { useNavigate } from 'react-router'
import { openEndpointDialog } from '../components/endpoint/endpointDialogStore'
import { PageHeader } from '../components/page/PageHeader'
import { Button } from '../components/ui/Button'
import { ConfirmButton } from '../components/ui/ConfirmButton'
import { Segmented } from '../components/ui/Segmented'
import { Switch } from '../components/ui/Switch'
import { showToast } from '../components/ui/toast'
import { endpointHost, endpointLabel, SERVICE_LABEL } from '../lib/endpoint'
import { actions, useApp } from '../prototype/store'
import type { Endpoint } from '../prototype/types'
import styles from './SettingsPage.module.css'

export function SettingsPage() {
  const settings = useApp((s) => s.settings)
  const endpoint = useApp((s) => s.endpoint)
  const endpoints = useApp((s) => s.endpoints)
  const navigate = useNavigate()

  return (
    <>
      <PageHeader
        title="设置"
        subtitle="这些设置只保存在这台设备上；已读和收藏会同步到你的 RSS 服务。"
      />
      <div className={styles.page}>
        <Section title="API 端点">
          {endpoint?.kind === 'demo' && (
            <Row label="演示数据" description="本地生成的示例，没有连接任何服务器。">
              <CurrentBadge />
              <Button
                size="sm"
                onClick={() => {
                  actions.exitDemo()
                  navigate('/connect', { replace: true })
                }}
              >
                退出演示
              </Button>
            </Row>
          )}
          {endpoints.map((item) => (
            <EndpointRow key={item.id} endpoint={item} current={item.id === endpoint?.id} />
          ))}
          <Row
            label="添加 API 端点"
            description="每个端点分别保存地址、凭据，以及是否把凭据保存在这个浏览器里。"
          >
            <Button
              size="sm"
              icon={<PlusIcon aria-hidden />}
              onClick={() => openEndpointDialog({ mode: 'add' })}
            >
              添加
            </Button>
          </Row>
        </Section>

        <Section title="浏览">
          <SwitchRow
            label="打开图集时标为已读"
            description="至少一张图片显示成功后才标记；滚动列表和预加载不会标记。"
            checked={settings.autoRead}
            onChange={(autoRead) => actions.updateSettings({ autoRead })}
          />
          <SwitchRow
            label="下载成功后标为已读"
            description="本次下载的图片全部成功后，将所属图集标为已读；下载失败时不标记。"
            checked={settings.downloadRead}
            onChange={(downloadRead) => actions.updateSettings({ downloadRead })}
          />
          <SwitchRow
            label="显示没有图片的文章"
            description="包括确认没有图片的文章，和图片还没解析出来的文章。"
            checked={settings.showImageless}
            onChange={(showImageless) => actions.updateSettings({ showImageless })}
          />
          <Row label="默认显示" description="打开“浏览”时先看到的范围。">
            <Segmented
              label="默认显示"
              size="sm"
              value={settings.defaultStatus}
              onChange={(defaultStatus) => actions.updateSettings({ defaultStatus })}
              options={[
                { value: 'unread', label: '未读' },
                { value: 'all', label: '全部' },
              ]}
            />
          </Row>
          <Row label="卡片大小" description="窄屏上分别是三列、两列和一列。">
            <Segmented
              label="卡片大小"
              size="sm"
              value={settings.density}
              onChange={(density) => actions.updateSettings({ density })}
              options={[
                { value: 'compact', label: '紧凑' },
                { value: 'standard', label: '标准' },
                { value: 'roomy', label: '宽松' },
              ]}
            />
          </Row>
        </Section>

        <Section title="外观">
          <Row label="主题" description="查看器始终使用深色背景。">
            <Segmented
              label="主题"
              size="sm"
              value={settings.theme}
              onChange={(theme) => actions.updateSettings({ theme })}
              options={[
                { value: 'system', label: '跟随系统' },
                { value: 'light', label: '浅色' },
                { value: 'dark', label: '深色' },
              ]}
            />
          </Row>
        </Section>

        {endpoint?.kind === 'demo' ? (
          <Section title="图片缓存">
            <div className={styles.usage}>
              <div className={styles.usageHead}>
                <span className={styles.usageValue}>186 MB</span>
                <span className={styles.usageLimit}>上限 1 GB</span>
              </div>
              <div
                className={styles.bar}
                role="img"
                aria-label="自动缓存 162 MB，手动下载 24 MB，上限 1 GB"
              >
                <span className={styles.barAuto} style={{ width: '15.8%' }} />
                <span className={styles.barManual} style={{ width: '2.4%' }} />
              </div>
              <ul className={styles.legend}>
                <li>
                  <span className={styles.swatchAuto} aria-hidden />
                  浏览时自动缓存 162 MB
                </li>
                <li>
                  <span className={styles.swatchManual} aria-hidden />
                  手动下载的图集 24 MB
                </li>
              </ul>
            </div>
            <Row
              label="清除图片缓存"
              description="浏览器空间不足时可能自行清理缓存，网页版的缓存不作为长期存档。图片能否离线保存，取决于图片来源是否允许网页读取。"
            >
              <Button
                size="sm"
                icon={<TrashIcon aria-hidden />}
                onClick={() =>
                  showToast({
                    message: '已清除图片缓存',
                    detail: '演示数据，没有实际清除。',
                    tone: 'success',
                  })
                }
              >
                清除
              </Button>
            </Row>
          </Section>
        ) : (
          <Section title="图片保存">
            <Row
              label="保存到设备"
              description="下载按钮会尝试直接保存原图；来源限制跨域读取时，可打开原图后右键或长按保存。当前尚未提供离线图片缓存。"
            />
          </Section>
        )}

        {endpoint?.kind === 'demo' && (
          <Section title="原型调试">
            <SwitchRow
              label="模拟图片加载耗时"
              description="用来观察网点占位，以及瀑布流“先测量尺寸再放入”的过程。"
              checked={settings.simulateLatency}
              onChange={(simulateLatency) => actions.updateSettings({ simulateLatency })}
            />
            <Row
              label="模拟后台同步"
              description="相当于切回这个标签页时同步到了新内容：只提示数量，不打乱正在看的列表。"
            >
              <Button size="sm" onClick={() => void actions.sync({ explicit: false })}>
                立即模拟
              </Button>
            </Row>
            <Row label="重置演示数据" description="恢复初始的已读、收藏状态和设置。">
              <Button size="sm" onClick={actions.resetDemo}>
                重置
              </Button>
            </Row>
          </Section>
        )}

        <footer className={styles.about}>
          <p>Album RSS · 直接连接你的 RSS 服务，不经过任何中转服务器。</p>
          <a
            className={styles.repo}
            href="https://github.com/ChiyukiRuon/album-rss"
            target="_blank"
            rel="noopener noreferrer"
          >
            <GithubLogoIcon className={styles.repoIcon} aria-hidden />
            <span className="visually-hidden">GitHub：</span>
            ChiyukiRuon/album-rss
            <ArrowSquareOutIcon className={styles.repoArrow} aria-hidden />
          </a>
        </footer>
      </div>
    </>
  )
}

function CurrentBadge() {
  return (
    <span className={styles.status}>
      <span className={styles.statusDot} aria-hidden />
      当前使用
    </span>
  )
}

function EndpointRow({ endpoint, current }: { endpoint: Endpoint; current: boolean }) {
  const [switching, setSwitching] = useState(false)
  const description = [
    SERVICE_LABEL[endpoint.service],
    endpoint.name ? endpointHost(endpoint) : null,
    endpoint.remember ? '凭据已保存在此浏览器' : '仅本次会话，刷新后移除',
  ]
    .filter(Boolean)
    .join(' · ')
  return (
    <Row label={endpointLabel(endpoint)} description={description}>
      {current ? (
        <CurrentBadge />
      ) : (
        <Button
          size="sm"
          disabled={switching}
          onClick={async () => {
            setSwitching(true)
            try {
              await actions.switchEndpoint(endpoint.id)
            } catch (error) {
              showToast({
                message: `无法切换到「${endpointLabel(endpoint)}」`,
                detail: error instanceof Error ? error.message : undefined,
                tone: 'warning',
              })
            } finally {
              setSwitching(false)
            }
          }}
        >
          {switching ? '正在切换…' : '切换'}
        </Button>
      )}
      <Button size="sm" onClick={() => openEndpointDialog({ mode: 'edit', id: endpoint.id })}>
        编辑
      </Button>
      <ConfirmButton
        label="删除"
        icon={<TrashIcon aria-hidden />}
        variant="danger"
        message={
          current
            ? '删除正在使用的端点及其在浏览器中保存的凭据？之后会切换到下一个端点；已同步到服务器的已读和收藏不受影响。'
            : '删除这个端点及其在浏览器中保存的凭据？已同步到服务器的已读和收藏不受影响。'
        }
        confirmLabel="删除端点"
        onConfirm={() => void actions.removeEndpoint(endpoint.id)}
      />
    </Row>
  )
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  const id = useId()
  return (
    <section className={styles.section} aria-labelledby={id}>
      <h2 id={id} className={styles.sectionTitle}>
        {title}
      </h2>
      <div className={styles.card}>{children}</div>
    </section>
  )
}

function Row({
  label,
  description,
  labelId,
  descriptionId,
  children,
}: {
  label: string
  description?: string
  labelId?: string
  descriptionId?: string
  children?: ReactNode
}) {
  return (
    <div className={styles.row}>
      <div className={styles.rowText}>
        <p id={labelId} className={styles.rowLabel}>
          {label}
        </p>
        {description && (
          <p id={descriptionId} className={styles.rowDescription}>
            {description}
          </p>
        )}
      </div>
      {children && <div className={styles.rowControl}>{children}</div>}
    </div>
  )
}

function SwitchRow({
  label,
  description,
  checked,
  onChange,
}: {
  label: string
  description: string
  checked: boolean
  onChange: (checked: boolean) => void
}) {
  const id = useId()
  return (
    <Row
      label={label}
      description={description}
      labelId={`${id}-label`}
      descriptionId={`${id}-desc`}
    >
      <Switch
        checked={checked}
        onChange={onChange}
        labelledBy={`${id}-label`}
        describedBy={`${id}-desc`}
      />
    </Row>
  )
}
