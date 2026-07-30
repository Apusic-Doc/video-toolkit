// ASS 字幕颜色格式是 &HAABBGGRR（透明度 + 蓝绿红倒序），跟网页/取色器习惯的
// #RRGGBB 不是一回事，这里做双向转换，好让用户用普通取色器选，存回 meta.json
// 的时候还是写成 libass 认得的格式。
export function assToRgbHex(ass, fallback = '#FFFFFF') {
  if (typeof ass !== 'string') return fallback;
  const m = ass.match(/&H([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})/);
  if (!m) return fallback;
  const [, , bb, gg, rr] = m;
  return `#${rr}${gg}${bb}`.toUpperCase();
}

export function rgbHexToAss(hex, alpha = '00') {
  const m = /^#?([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$/.exec(hex || '');
  if (!m) return '&H00FFFFFF';
  const [, rr, gg, bb] = m;
  return `&H${alpha}${bb}${gg}${rr}`.toUpperCase();
}
