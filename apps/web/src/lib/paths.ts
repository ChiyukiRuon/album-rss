/** 订阅页地址。Google Reader 的订阅 ID 形如 feed/https://…，必须编码 */
export function feedPath(feedId: string): string {
  return `/feeds/${encodeURIComponent(feedId)}`
}
