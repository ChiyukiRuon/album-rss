import { useSyncExternalStore } from 'react'

interface Connection extends EventTarget {
  type?: string
}

function connection() {
  return (navigator as Navigator & { connection?: Connection }).connection
}

export function permitsVideoAutoplay(enabled: boolean, cellular: boolean, type?: string) {
  return enabled && type !== 'none' && (cellular || type === 'wifi' || type === 'ethernet')
}

function subscribe(onChange: () => void) {
  const network = connection()
  network?.addEventListener('change', onChange)
  window.addEventListener('online', onChange)
  window.addEventListener('offline', onChange)
  return () => {
    network?.removeEventListener('change', onChange)
    window.removeEventListener('online', onChange)
    window.removeEventListener('offline', onChange)
  }
}

export function useVideoAutoplay(enabled: boolean, cellular: boolean) {
  const type = useSyncExternalStore(subscribe, () =>
    navigator.onLine ? connection()?.type : 'none',
  )
  return permitsVideoAutoplay(enabled, cellular, type)
}
