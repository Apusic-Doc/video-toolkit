import { useMemo, useState } from 'react';

// 全站通用的表格组件——列定义 { key, label, sortable, render(row), sortValue(row) }，
// 排序/空状态/行点击这几件事集中在一处实现，Dashboard 的项目表/feature 表都用它，
// 以后要加别的表格（比如历史任务列表）也应该优先复用这个，而不是每页各写一套 <table>。
export default function DataGrid({ columns, rows, rowKey, onRowClick, emptyText, toolbar }) {
  const [sortKey, setSortKey] = useState(null);
  const [sortDir, setSortDir] = useState(1); // 1 asc, -1 desc

  const sorted = useMemo(() => {
    if (!sortKey) return rows;
    const col = columns.find((c) => c.key === sortKey);
    const getVal = col?.sortValue || ((row) => row[sortKey]);
    return [...rows].sort((a, b) => {
      const va = getVal(a); const vb = getVal(b);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      if (typeof va === 'number' && typeof vb === 'number') return (va - vb) * sortDir;
      return String(va).localeCompare(String(vb)) * sortDir;
    });
  }, [rows, sortKey, sortDir, columns]);

  function toggleSort(col) {
    if (!col.sortable) return;
    if (sortKey === col.key) setSortDir((d) => -d);
    else { setSortKey(col.key); setSortDir(1); }
  }

  return (
    <div>
      {toolbar && <div className="datagrid-toolbar">{toolbar}</div>}
      <div className="datagrid-wrap">
        <table className="datagrid">
          <thead>
            <tr>
              {columns.map((c) => (
                <th key={c.key} className={c.sortable ? 'sortable' : ''} onClick={() => toggleSort(c)}>
                  {c.label}
                  {sortKey === c.key && <span className="arrow">{sortDir === 1 ? '▲' : '▼'}</span>}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {sorted.map((row) => (
              <tr key={rowKey(row)} onClick={() => onRowClick?.(row)}>
                {columns.map((c) => <td key={c.key}>{c.render ? c.render(row) : row[c.key]}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
        {sorted.length === 0 && <div className="datagrid-empty">{emptyText}</div>}
      </div>
    </div>
  );
}
