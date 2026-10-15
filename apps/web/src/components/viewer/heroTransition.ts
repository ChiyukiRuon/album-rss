/*
 * 卡片与查看器之间的放大 / 缩回过渡。浏览器支持 View Transitions 时启用，
 * 否则直接切换；系统开启“减少动态效果”时也直接切换。
 */
const HERO = 'album-hero'

type TransitionDocument = Document & {
  startViewTransition?: (update: () => Promise<void>) => { finished: Promise<void> }
}

// 过渡回调期间页面暂停渲染，requestAnimationFrame 不会触发，所以用定时器轮询
const wait = (ms: number) => new Promise((resolve) => window.setTimeout(resolve, ms))

async function waitFor(check: () => boolean, timeout: number) {
  const start = performance.now()
  while (!check() && performance.now() - start < timeout) await wait(16)
}

function canAnimate(doc: TransitionDocument) {
  return (
    typeof doc.startViewTransition === 'function' &&
    !window.matchMedia('(prefers-reduced-motion: reduce)').matches
  )
}

function inViewport(element: Element) {
  const rect = element.getBoundingClientRect()
  return rect.bottom > 0 && rect.top < window.innerHeight && rect.width > 0
}

const viewerOpen = () => document.querySelector('[data-viewer-root]') !== null

export function findCardImage(cardKeys: string[]): HTMLImageElement | null {
  for (const key of cardKeys) {
    const image = document.querySelector<HTMLImageElement>(
      `[data-card-key="${CSS.escape(key)}"] img`,
    )
    if (image) return image
  }
  return null
}

function focusCard(cardKeys: string[]) {
  for (const key of cardKeys) {
    const link = document.querySelector<HTMLElement>(`[data-card-key="${CSS.escape(key)}"] a`)
    if (link) {
      link.focus({ preventScroll: true })
      return
    }
  }
}

export function heroOpen(from: HTMLImageElement | null, update: () => unknown) {
  const doc = document as TransitionDocument
  if (!from?.complete || !inViewport(from) || !canAnimate(doc)) {
    void update()
    return
  }
  from.style.viewTransitionName = HERO
  const transition = doc.startViewTransition!(async () => {
    from.style.viewTransitionName = ''
    await update()
    await waitFor(viewerOpen, 300)
    const hero = document.querySelector<HTMLImageElement>('[data-viewer-hero]')
    if (hero && !hero.complete) {
      await Promise.race([hero.decode().catch(() => undefined), wait(180)])
    }
  })
  void transition.finished.finally(() => {
    from.style.viewTransitionName = ''
  })
}

/** cardKeys 按优先级排列：单图模式的卡片键在前，图集卡片键在后 */
export function heroClose(cardKeys: string[], update: () => unknown) {
  const doc = document as TransitionDocument
  const hero = document.querySelector<HTMLImageElement>('[data-viewer-hero]')
  if (!hero?.complete || !canAnimate(doc)) {
    void Promise.resolve(update())
      .then(() => waitFor(() => !viewerOpen(), 400))
      .then(() => focusCard(cardKeys))
    return
  }
  let target: HTMLImageElement | null = null
  const transition = doc.startViewTransition!(async () => {
    await update()
    await waitFor(() => !viewerOpen(), 400)
    target = findCardImage(cardKeys)
    if (target && inViewport(target)) target.style.viewTransitionName = HERO
    else target = null
  })
  void transition.finished.finally(() => {
    if (target) target.style.viewTransitionName = ''
    focusCard(cardKeys)
  })
}
