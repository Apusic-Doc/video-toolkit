// 中文标题生成不了有意义的英文 slug，遇到非拉丁字符直接丢弃而不是保留——
// 用户十有八九会自己手动改这段自动生成的 slug，这里只是给个还算合理的起点
export function slugify(text) {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
}
