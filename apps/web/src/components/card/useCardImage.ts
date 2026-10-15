import { useState, type SyntheticEvent } from 'react'
import { recordLoadedSize } from '../../lib/imageProbe'
import { useImageSrc } from '../../lib/imageSource'

export type CardImageStatus = 'loading' | 'loaded' | 'error'

/** 卡片里一张图的加载状态；失败后可以重试 */
export function useCardImage(url: string | undefined, failedEarlier: boolean) {
  const src = useImageSrc(url)
  const [attempt, setAttempt] = useState(0)
  const [result, setResult] = useState<{ key: string; status: CardImageStatus } | null>(null)
  const key = `${src ?? ''}#${attempt}`
  const status: CardImageStatus =
    result?.key === key ? result.status : failedEarlier && attempt === 0 ? 'error' : 'loading'

  return {
    src: status === 'error' && attempt === 0 && failedEarlier ? undefined : src,
    imageKey: key,
    status,
    onLoad: (event: SyntheticEvent<HTMLImageElement>) => {
      const image = event.currentTarget
      if (url) recordLoadedSize(url, image.naturalWidth, image.naturalHeight)
      setResult({ key, status: 'loaded' })
    },
    onError: () => setResult({ key, status: 'error' }),
    retry: () => setAttempt((n) => n + 1),
  }
}
