// 手写的小型 markdown 转 HTML，不用 marked 这类第三方库——
// 装过 marked 之后 Vite 8 的 Rolldown 打包器死活把它当外部模块处理，产物里留了一行
// `import{marked}from"marked"` 没打包进去，浏览器直接原生加载就会报 "Failed to resolve
// module specifier"（bare specifier 浏览器自己解析不了）。折腾了一圈没找到这个新打包器的
// 正确配置方式，干脆不用第三方库了——README.md 实际用到的语法就这几种，够用。
function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function inline(text) {
  let t = escapeHtml(text);
  t = t.replace(/`([^`]+)`/g, '<code>$1</code>');
  t = t.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  t = t.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
  return t;
}

export function renderMarkdown(md) {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const out = [];
  let i = 0;
  let inCode = false, codeBuf = [];
  let listBuf = [];

  function flushList() {
    if (listBuf.length) { out.push(`<ul>${listBuf.join('')}</ul>`); listBuf = []; }
  }

  while (i < lines.length) {
    const line = lines[i];

    if (line.startsWith('```')) {
      if (!inCode) { inCode = true; codeBuf = []; }
      else { inCode = false; out.push(`<pre><code>${escapeHtml(codeBuf.join('\n'))}</code></pre>`); }
      i++; continue;
    }
    if (inCode) { codeBuf.push(line); i++; continue; }

    const h = line.match(/^(#{1,4})\s+(.*)/);
    if (h) { flushList(); out.push(`<h${h[1].length}>${inline(h[2])}</h${h[1].length}>`); i++; continue; }

    if (/^-{3,}\s*$/.test(line)) { flushList(); out.push('<hr>'); i++; continue; }

    const li = line.match(/^\s*[-*]\s+(.*)/);
    if (li) { listBuf.push(`<li>${inline(li[1])}</li>`); i++; continue; }
    flushList();

    // 表格：一行表头 + 一行 |---|---| 分隔符
    if (line.includes('|') && lines[i + 1] && /^\s*\|?[\s:|-]+\|[\s:|-]*$/.test(lines[i + 1])) {
      const headCells = line.split('|').map((c) => c.trim()).filter((c) => c !== '');
      out.push('<table><thead><tr>' + headCells.map((c) => `<th>${inline(c)}</th>`).join('') + '</tr></thead><tbody>');
      i += 2;
      while (i < lines.length && lines[i].includes('|')) {
        const cells = lines[i].split('|').map((c) => c.trim()).filter((c, idx, arr) => !(c === '' && (idx === 0 || idx === arr.length - 1)));
        out.push('<tr>' + cells.map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>');
        i++;
      }
      out.push('</tbody></table>');
      continue;
    }

    if (line.trim() === '') { i++; continue; }
    out.push(`<p>${inline(line)}</p>`);
    i++;
  }
  flushList();
  return out.join('\n');
}
