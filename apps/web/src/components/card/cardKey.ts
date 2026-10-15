/** 卡片键：图集卡片用文章 ID，图片流里的卡片用“文章 ID:图片序号” */
export function cardKeyOf(entryId: string, imageIndex: number | null): string {
  return imageIndex === null ? entryId : `${entryId}:${imageIndex}`
}
