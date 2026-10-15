import { useSyncExternalStore } from 'react'

/**
 * 极小的外部状态容器。组件通过 selector 订阅其中一部分；
 * selector 必须返回已有的引用或原始值，不要在里面构造新对象。
 */
export interface Store<T> {
  get(): T
  set(update: (state: T) => T): void
  subscribe(listener: () => void): () => void
  use<S>(selector: (state: T) => S): S
}

export function createStore<T>(initial: T): Store<T> {
  let state = initial
  const listeners = new Set<() => void>()

  const store: Store<T> = {
    get: () => state,
    set(update) {
      const next = update(state)
      if (next === state) return
      state = next
      listeners.forEach((listener) => listener())
    },
    subscribe(listener) {
      listeners.add(listener)
      return () => listeners.delete(listener)
    },
    use(selector) {
      return useSyncExternalStore(store.subscribe, () => selector(state))
    },
  }
  return store
}
