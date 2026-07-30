// SRT <-> JSON 互转，字段跟前端表格一一对应: { index, start, end, text }
// 时间格式统一用 "HH:MM:SS,mmm"

const TS = /(\d{2}):(\d{2}):(\d{2}),(\d{3})/;

export function parseSrt(content) {
  const blocks = content.replace(/\r\n/g, '\n').trim().split(/\n\n+/).filter(Boolean);
  const cues = [];
  for (const block of blocks) {
    const lines = block.split('\n');
    if (lines.length < 2) continue;
    const idxLine = lines[0].trim();
    const timeLine = lines[1];
    const m = timeLine.match(new RegExp(`${TS.source}\\s*-->\\s*${TS.source}`));
    if (!m) continue;
    const start = `${m[1]}:${m[2]}:${m[3]},${m[4]}`;
    const end = `${m[5]}:${m[6]}:${m[7]},${m[8]}`;
    const text = lines.slice(2).join('\n');
    cues.push({ index: parseInt(idxLine, 10) || cues.length + 1, start, end, text });
  }
  return cues;
}

function validTs(ts) {
  return typeof ts === 'string' && TS.test(ts);
}

export function serializeSrt(cues) {
  return cues
    .filter(c => validTs(c.start) && validTs(c.end) && typeof c.text === 'string')
    .map((c, i) => `${i + 1}\n${c.start} --> ${c.end}\n${c.text}`)
    .join('\n\n') + '\n';
}

export function tsToSeconds(ts) {
  const m = ts.match(TS);
  if (!m) return 0;
  return (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]) + (+m[4]) / 1000;
}
