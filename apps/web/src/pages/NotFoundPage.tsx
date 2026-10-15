import { CompassIcon } from '@phosphor-icons/react'
import { useNavigate } from 'react-router'
import { EmptyState } from '../components/page/EmptyState'
import { Button } from '../components/ui/Button'

export function NotFoundPage() {
  const navigate = useNavigate()
  return (
    <EmptyState
      icon={<CompassIcon aria-hidden />}
      title="没有这个页面"
      description="地址可能输错了，或者这个页面已经不存在。"
      actions={
        <Button variant="primary" onClick={() => navigate('/')}>
          回到浏览
        </Button>
      }
    />
  )
}
