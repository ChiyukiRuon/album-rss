import type { Endpoint, ServiceKind } from '../prototype/types'

export const SERVICE_LABEL: Record<ServiceKind, string> = {
  miniflux: 'Miniflux',
  greader: 'Google Reader',
}

/** 服务地址去掉协议，保留子路径：同一主机上的多个服务也能区分 */
export function endpointHost(endpoint: Pick<Endpoint, 'server'>): string {
  try {
    const url = new URL(endpoint.server)
    return url.host + url.pathname.replace(/\/+$/, '')
  } catch {
    return endpoint.server
  }
}

/** 端点的主名称：自定义名称，没有时用地址 */
export function endpointLabel(endpoint: Endpoint): string {
  if (endpoint.kind === 'demo') return '演示数据'
  return endpoint.name || endpointHost(endpoint)
}

/** 端点的第二行：服务类型，有自定义名称时再加上地址 */
export function endpointDetail(endpoint: Endpoint): string {
  if (endpoint.kind === 'demo') return '本地示例数据'
  const service = SERVICE_LABEL[endpoint.service]
  return endpoint.name ? `${service} · ${endpointHost(endpoint)}` : service
}
