import { createStore } from '../../lib/createStore'

export interface ToastAction {
  label: string
  run: () => void
}

export interface Toast {
  id: number
  message: string
  detail?: string
  tone: 'neutral' | 'success' | 'warning'
  action?: ToastAction
}

export const toastStore = createStore<Toast[]>([])

let nextId = 1

export function showToast(toast: Omit<Toast, 'id' | 'tone'> & { tone?: Toast['tone'] }): number {
  const id = nextId++
  const entry: Toast = { tone: 'neutral', ...toast, id }
  // 同时最多保留三条，旧的先出
  toastStore.set((list) => [...list.slice(-2), entry])
  const lifetime = toast.action || toast.detail ? 6500 : 3200
  window.setTimeout(() => dismissToast(id), lifetime)
  return id
}

export function dismissToast(id: number) {
  toastStore.set((list) => (list.some((t) => t.id === id) ? list.filter((t) => t.id !== id) : list))
}
