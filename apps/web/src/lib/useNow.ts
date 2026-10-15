import { useSyncExternalStore } from 'react'

// 所有相对时间共用一个半分钟的时钟，渲染期间不直接调用 Date.now()
let now = Date.now()
const listeners = new Set<() => void>()
let timer: number | undefined

function subscribe(listener: () => void) {
  listeners.add(listener)
  if (timer === undefined) {
    timer = window.setInterval(() => {
      now = Date.now()
      listeners.forEach((l) => l())
    }, 30_000)
  }
  return () => {
    listeners.delete(listener)
    if (listeners.size === 0 && timer !== undefined) {
      window.clearInterval(timer)
      timer = undefined
    }
  }
}

export function useNow(): number {
  return useSyncExternalStore(subscribe, () => now)
}

/** 状态刚变化（例如同步完成）时让时钟立即前进，避免显示“1 分钟前” */
export function touchNow() {
  now = Date.now()
  listeners.forEach((l) => l())
}
