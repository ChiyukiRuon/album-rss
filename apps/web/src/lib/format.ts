const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

const pad = (value: number) => String(value).padStart(2, '0')

/** 相对时间：刚刚 / 5 分钟前 / 3 小时前 / 昨天 21:04 / 10月3日 / 2025年10月3日 */
export function relativeTime(timestamp: number, now: number): string {
  const diff = now - timestamp
  if (diff < MINUTE) return '刚刚'
  if (diff < HOUR) return `${Math.floor(diff / MINUTE)} 分钟前`
  const date = new Date(timestamp)
  const today = new Date(now)
  const startOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime()
  if (timestamp >= startOfToday) return `${Math.floor(diff / HOUR)} 小时前`
  if (timestamp >= startOfToday - DAY)
    return `昨天 ${pad(date.getHours())}:${pad(date.getMinutes())}`
  if (date.getFullYear() === today.getFullYear())
    return `${date.getMonth() + 1}月${date.getDate()}日`
  return `${date.getFullYear()}年${date.getMonth() + 1}月${date.getDate()}日`
}

export function fullTime(timestamp: number): string {
  const d = new Date(timestamp)
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日 ${pad(d.getHours())}:${pad(d.getMinutes())}`
}

/** 网站的显示名：去掉 www. 的主机名；地址无效时为空 */
export function siteName(url: string): string {
  try {
    return new URL(url).host.replace(/^www\./, '')
  } catch {
    return ''
  }
}

export function hostOf(url: string): string {
  try {
    return new URL(url).host
  } catch {
    return url
  }
}
