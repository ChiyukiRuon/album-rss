import { useState } from 'react'
import { useImageSrc } from '../../lib/imageSource'
import { Tone } from '../tone/Tone'

interface ImageThumbProps {
  url: string | undefined
  className?: string
  lazy?: boolean
}

/** 装饰性的小图：加载中显示网点，加载失败也只留网点，不出现浏览器的破图标记 */
export function ImageThumb({ url, className, lazy }: ImageThumbProps) {
  const src = useImageSrc(url)
  const [failedSrc, setFailedSrc] = useState<string | null>(null)
  if (!src || failedSrc === src) {
    return <Tone loading={Boolean(url) && failedSrc === null} className={className} />
  }
  return (
    <img
      className={className}
      src={src}
      alt=""
      draggable={false}
      loading={lazy ? 'lazy' : undefined}
      onError={() => setFailedSrc(src)}
    />
  )
}
