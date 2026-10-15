import { createStore } from '../../lib/createStore'

/** 添加 / 编辑端点的弹窗；任何地方都可以打开 */
export type EndpointDialogState = { mode: 'add' } | { mode: 'edit'; id: string } | null

export const endpointDialog = createStore<EndpointDialogState>(null)

export function openEndpointDialog(state: Exclude<EndpointDialogState, null>) {
  endpointDialog.set(() => state)
}

export function closeEndpointDialog() {
  endpointDialog.set(() => null)
}
