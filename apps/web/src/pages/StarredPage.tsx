import { StarIcon } from '@phosphor-icons/react'
import { EmptyState } from '../components/page/EmptyState'
import { PageHeader } from '../components/page/PageHeader'
import { EntryWall } from '../components/wall/EntryWall'
import { useListSnapshot } from '../prototype/selectors'
import { ModeSwitch } from './wallControls'
import { useWallParams } from './useWallParams'

export function StarredPage() {
  const { mode, update } = useWallParams()
  const ids = useListSnapshot({ status: 'starred' })
  return (
    <>
      <PageHeader
        title="收藏"
        subtitle={`${ids.length} 个图集 · 收藏会同步到你的 RSS 服务`}
        toolbar={
          <ModeSwitch
            mode={mode}
            onChange={(value) => update({ mode: value === 'albums' ? null : value })}
          />
        }
      />
      <EntryWall
        ids={ids}
        mode={mode}
        label="收藏的图集"
        dimRead={false}
        empty={
          <EmptyState
            icon={<StarIcon aria-hidden />}
            title="还没有收藏"
            description="在查看器里点星标或按 S，就能收藏整个图集。收藏会同步到你的 RSS 服务，其他设备上也能看到。"
          />
        }
      />
    </>
  )
}
