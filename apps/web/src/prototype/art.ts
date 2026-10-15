/*
 * 演示用占位插画：在本地按种子生成 SVG，不访问任何图片站点。
 * 演示数据里只保存 demo: 伪地址，显示时再生成，避免数据本身过大。
 */
import { between, intBetween, mulberry32, pick, type Rng } from './random'

export type PaletteName = 'dusk' | 'sea' | 'citrus' | 'ink' | 'sakura' | 'autumn' | 'night' | 'mint'

type Palette = readonly [string, string, string, string, string]

// 每组：背景起点、背景终点、高光、深色、点缀
const PALETTES: Record<PaletteName, Palette> = {
  dusk: ['#f9cdbf', '#9b8bd8', '#fff1e4', '#4f3f86', '#f48fa0'],
  sea: ['#c4e9f3', '#3f7db4', '#effaf7', '#1c4672', '#7fd3c8'],
  citrus: ['#fff3b0', '#93cf6a', '#fffbe6', '#3f8f37', '#ffa26e'],
  ink: ['#f6f6f4', '#d6d6d6', '#ffffff', '#141414', '#7a7a7a'],
  sakura: ['#ffe4ee', '#f39abb', '#fffaf6', '#b74f78', '#fcd2c9'],
  autumn: ['#f7d9a8', '#c76a3b', '#fdf0dc', '#6f3726', '#eaa65a'],
  night: ['#22306a', '#6d5aa8', '#f4c4d5', '#0d1230', '#8db4ea'],
  mint: ['#dff7ef', '#78c6ae', '#f8fcfa', '#2a7865', '#b6e2f0'],
}

export function artUrl(palette: PaletteName, seed: number, width: number, height: number): string {
  return `demo:art/${palette}/${seed}/${width}x${height}`
}

/** 一个注定加载失败的地址，用来展示“加载失败”状态 */
export function brokenUrl(seed: number): string {
  return `demo:broken/${seed}`
}

export function isDemoUrl(url: string): boolean {
  return url.startsWith('demo:')
}

/** 演示地址里带着尺寸；只用于装饰性的展示墙，列表仍按真实流程测量 */
export function demoSize(url: string): { width: number; height: number } | null {
  const match = /\/(\d+)x(\d+)$/.exec(url)
  return match ? { width: Number(match[1]), height: Number(match[2]) } : null
}

const BROKEN_SRC = 'data:image/png;base64,AAAA'
const rendered = new Map<string, string>()

/** 把 demo: 地址换成可以直接交给 img 的 data URI */
export function renderDemoUrl(url: string): string {
  const cached = rendered.get(url)
  if (cached) return cached
  const match = /^demo:art\/(\w+)\/(\d+)\/(\d+)x(\d+)$/.exec(url)
  let src = BROKEN_SRC
  if (match) {
    const [, name, seed, w, h] = match
    const palette = PALETTES[name as PaletteName]
    if (palette) {
      const svg = renderArt(name as PaletteName, palette, Number(seed), Number(w), Number(h))
      src = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
    }
  }
  rendered.set(url, src)
  return src
}

function renderArt(name: PaletteName, p: Palette, seed: number, w: number, h: number): string {
  const rng = mulberry32(seed)
  const content = name === 'ink' ? manga(rng, w, h) : illustration(rng, p, w, h)
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${content}</svg>`
}

const n = (value: number) => Math.round(value)
const f = (value: number) => value.toFixed(2)

function illustration(rng: Rng, p: Palette, w: number, h: number): string {
  const m = Math.min(w, h)
  const angle = n(rng() * 360)
  let defs = `<linearGradient id="g" gradientTransform="rotate(${angle} .5 .5)"><stop offset="0" stop-color="${p[0]}"/><stop offset="1" stop-color="${p[1]}"/></linearGradient>`
  let body = `<rect width="${w}" height="${h}" fill="url(#g)"/>`

  // 柔和的色块，像插画背景里的光和氛围
  const blobs = intBetween(rng, 4, 7)
  for (let i = 0; i < blobs; i++) {
    const color = pick(rng, p)
    const rx = m * between(rng, 0.25, 0.7)
    const ry = rx * between(rng, 0.55, 1.4)
    defs += `<radialGradient id="b${i}"><stop offset="0" stop-color="${color}" stop-opacity="${f(between(rng, 0.5, 0.95))}"/><stop offset="1" stop-color="${color}" stop-opacity="0"/></radialGradient>`
    body += `<ellipse cx="${n(rng() * w)}" cy="${n(rng() * h)}" rx="${n(rx)}" ry="${n(ry)}" fill="url(#b${i})"/>`
  }

  // 地平线
  if (rng() < 0.6) {
    const y = h * between(rng, 0.62, 0.84)
    const bend = h * between(rng, -0.08, 0.08)
    body += `<path d="M0 ${n(y)} Q ${n(w / 2)} ${n(y + bend)} ${w} ${n(y - bend)} V ${h} H 0 Z" fill="${p[3]}" fill-opacity="${f(between(rng, 0.16, 0.32))}"/>`
  }

  // 人物剪影：头与肩，暗示这是一张角色插画
  if (rng() < 0.72) {
    const cx = w * between(rng, 0.34, 0.66)
    const r = m * between(rng, 0.085, 0.13)
    const headY = h * between(rng, 0.4, 0.56)
    const half = r * between(rng, 1.7, 2.2)
    const top = headY + r * 2.1
    body += `<g fill="${p[3]}" fill-opacity="${f(between(rng, 0.5, 0.78))}">`
    body += `<circle cx="${n(cx)}" cy="${n(headY)}" r="${n(r)}"/>`
    body += `<path d="M ${n(cx - half)} ${h} C ${n(cx - half)} ${n(top)} ${n(cx + half)} ${n(top)} ${n(cx + half)} ${h} Z"/>`
    body += `</g>`
  }

  // 光点
  const dots = intBetween(rng, 6, 16)
  body += `<g fill="${p[2]}">`
  for (let i = 0; i < dots; i++) {
    body += `<circle cx="${n(rng() * w)}" cy="${n(rng() * h)}" r="${n(m * between(rng, 0.004, 0.018))}" fill-opacity="${f(between(rng, 0.45, 0.95))}"/>`
  }
  body += `</g>`

  return `<defs>${defs}</defs>${body}`
}

/** 黑白漫画页：分格、网点和速度线；长图时排成条漫 */
function manga(rng: Rng, w: number, h: number): string {
  const m = Math.min(w, h)
  const margin = m * 0.06
  const gutter = m * 0.03
  const stroke = Math.max(2, m * 0.006)
  const dot = m * 0.016
  let defs =
    `<pattern id="tone" width="${f(dot)}" height="${f(dot)}" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><circle cx="${f(dot / 2)}" cy="${f(dot / 2)}" r="${f(dot * 0.27)}" fill="#1a1a1a"/></pattern>` +
    `<linearGradient id="fade" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a2a2a"/><stop offset="1" stop-color="#2a2a2a" stop-opacity="0"/></linearGradient>`
  let body = `<rect width="${w}" height="${h}" fill="#fbfbf9"/>`

  const strip = h / w > 2.2
  const rows = strip ? Math.max(3, n((h / w) * 1.4)) : intBetween(rng, 3, 4)
  const weights = Array.from({ length: rows }, () => between(rng, 0.7, 1.3))
  const total = weights.reduce((a, b) => a + b, 0)
  const rowGap = strip ? gutter * 4 : gutter
  const usable = h - margin * 2 - rowGap * (rows - 1)
  let y = margin
  let panel = 0
  for (const weight of weights) {
    const rowH = (usable * weight) / total
    const split = !strip && rng() < 0.55 ? 2 : 1
    const ratio = split === 2 ? between(rng, 0.35, 0.65) : 1
    const widths = split === 2 ? [ratio, 1 - ratio] : [1]
    let x = margin
    const rowW = w - margin * 2 - gutter * (split - 1)
    for (const share of widths) {
      const pw = rowW * share
      const id = `p${panel++}`
      defs += `<clipPath id="${id}"><rect x="${f(x)}" y="${f(y)}" width="${f(pw)}" height="${f(rowH)}"/></clipPath>`
      body += `<g clip-path="url(#${id})">${panelFill(rng, x, y, pw, rowH, m)}</g>`
      body += `<rect x="${f(x)}" y="${f(y)}" width="${f(pw)}" height="${f(rowH)}" fill="none" stroke="#141414" stroke-width="${f(stroke)}"/>`
      x += pw + gutter
    }
    y += rowH + rowGap
  }
  return `<defs>${defs}</defs>${body}`
}

function panelFill(rng: Rng, x: number, y: number, w: number, h: number, m: number): string {
  const kind = pick(rng, ['tone', 'speed', 'fade', 'plain'] as const)
  let out = ''
  if (kind === 'tone')
    out += `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h)}" fill="url(#tone)" opacity="0.55"/>`
  if (kind === 'fade')
    out += `<rect x="${f(x)}" y="${f(y)}" width="${f(w)}" height="${f(h * 0.6)}" fill="url(#fade)" opacity="0.4"/>`
  if (kind === 'speed') {
    const cx = x + w * between(rng, 0.3, 0.7)
    const cy = y + h * between(rng, 0.3, 0.7)
    const reach = Math.hypot(w, h)
    out += `<g stroke="#1a1a1a" stroke-width="${f(Math.max(1, m * 0.0025))}" opacity="0.7">`
    for (let i = 0; i < 36; i++) {
      const a = (i / 36) * Math.PI * 2 + rng() * 0.08
      const inner = reach * between(rng, 0.12, 0.22)
      out += `<line x1="${f(cx + Math.cos(a) * inner)}" y1="${f(cy + Math.sin(a) * inner)}" x2="${f(cx + Math.cos(a) * reach)}" y2="${f(cy + Math.sin(a) * reach)}"/>`
    }
    out += `</g>`
  }
  // 部分分格里放一个角色轮廓
  if (rng() < 0.55) {
    const r = Math.min(w, h) * between(rng, 0.14, 0.22)
    const cx = x + w * between(rng, 0.3, 0.7)
    const cy = y + h * between(rng, 0.35, 0.6)
    out += `<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(r)}" fill="#ffffff" stroke="#141414" stroke-width="${f(Math.max(2, m * 0.005))}"/>`
    out += `<path d="M ${f(cx - r * 1.9)} ${f(y + h)} C ${f(cx - r * 1.9)} ${f(cy + r * 1.6)} ${f(cx + r * 1.9)} ${f(cy + r * 1.6)} ${f(cx + r * 1.9)} ${f(y + h)} Z" fill="#ffffff" stroke="#141414" stroke-width="${f(Math.max(2, m * 0.005))}"/>`
  }
  return out
}
