import { GearSixIcon, RssIcon, SquaresFourIcon, StarIcon, type Icon } from '@phosphor-icons/react'

export interface NavItem {
  to: string
  label: string
  icon: Icon
}

/** 与 iOS 底部入口一致：浏览、收藏、订阅、设置 */
export const NAV_ITEMS: NavItem[] = [
  { to: '/', label: '浏览', icon: SquaresFourIcon },
  { to: '/starred', label: '收藏', icon: StarIcon },
  { to: '/feeds', label: '订阅', icon: RssIcon },
  { to: '/settings', label: '设置', icon: GearSixIcon },
]
