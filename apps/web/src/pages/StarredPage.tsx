import { StarIcon } from '@phosphor-icons/react'
import { EmptyState } from '../components/page/EmptyState'
import { PageHeader } from '../components/page/PageHeader'
import { EntryWall } from '../components/wall/EntryWall'
import { useScopeList } from '../prototype/selectors'
import { ModeSwitch } from './wallControls'
import { useWallParams } from './useWallParams'

export function StarredPage() {
  const { mode, update } = useWallParams()
  const list = useScopeList({ status: 'starred' })
  return (
    <>
      <PageHeader
        title="收藏"
        subtitle={`${list.ids.length}${list.hasMore ? '+' : ''} 个图集`}
        toolbar={
          <ModeSwitch
            mode={mode}
            onChange={(value) => update({ mode: value === 'albums' ? null : value })}
          />
        }
      />
      <EntryWall
        list={list}
        mode={mode}
        label="收藏的图集"
        dimRead={false}
        empty={
          <EmptyState
            icon={<StarIcon aria-hidden />}
            title="还没有收藏"
            description="在查看图片时点击星标或按 S 以收藏图集。收藏会同步到你的 RSS 服务。"
          />
        }
      />
    </>
  )
}
