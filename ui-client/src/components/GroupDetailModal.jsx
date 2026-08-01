import { useEffect, useRef, useState } from 'react';
import { api, openTaskSocket } from '../api.js';

function lineClass(l) {
  if (l.includes('✅') || l.includes('passed')) return 'ok';
  if (l.includes('❌') || l.includes('Error') || l.includes('失败')) return 'err';
  if (l.includes('⚠')) return 'warn';
  return '';
}

// 分组详情：调整组内 feature 顺序、生成合并视频、看进度、播放成片、看历史生成记录——
// 跟 feature 详情页的"任务/预览"体验对齐，不是只有一个简陋的合并按钮。
export default function GroupDetailModal({ project, group, features, onClose, onChanged, onDelete, onToast }) {
  const [order, setOrder] = useState(group.features);
  const [saving, setSaving] = useState(false);
  const [merging, setMerging] = useState(false);
  const [lines, setLines] = useState([]);
  const [history, setHistory] = useState([]);
  const [nonce, setNonce] = useState(0);
  const wsRef = useRef(null);

  useEffect(() => {
    api.groupTasks(project, group.id).then(setHistory).catch(() => {});
    return () => wsRef.current?.close();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const notIncluded = features.filter((f) => !order.includes(f.name));

  function move(i, dir) {
    setOrder((prev) => {
      const next = [...prev];
      const j = i + dir;
      if (j < 0 || j >= next.length) return prev;
      [next[i], next[j]] = [next[j], next[i]];
      return next;
    });
  }
  function removeAt(i) {
    setOrder((prev) => prev.filter((_, idx) => idx !== i));
  }
  function addFeature(name) {
    if (!name) return;
    setOrder((prev) => [...prev, name]);
  }

  async function save() {
    setSaving(true);
    try {
      await api.saveGroup(project, group.id, { features: order });
      onToast('分组已保存', 'ok');
      onChanged();
    } catch (e) {
      onToast(`保存失败: ${e.message}`, 'err');
    } finally {
      setSaving(false);
    }
  }

  async function merge() {
    setLines([]);
    setMerging(true);
    try {
      await save();
      await api.mergeGroup(project, group.id);
      const ws = openTaskSocket(project, `group:${group.id}`, (msg) => {
        if (msg.type === 'log') setLines((prev) => [...prev, msg.line]);
        else if (msg.type === 'status' && msg.status !== 'running') {
          setMerging(false);
          setNonce((n) => n + 1);
          onChanged(); // 刷新分组列表，拿到最新的 hasOutput
          api.groupTasks(project, group.id).then(setHistory).catch(() => {});
          ws.close();
        }
      });
      wsRef.current = ws;
    } catch (e) {
      onToast(`合并失败: ${e.message}`, 'err');
      setMerging(false);
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" style={{ width: 620, maxHeight: '85vh', overflowY: 'auto', textAlign: 'left' }} onClick={(e) => e.stopPropagation()}>
        <h1 style={{ fontSize: '1.05rem', margin: '0 0 4px' }}>{group.title || group.id}</h1>
        <p style={{ color: 'var(--text3)', fontSize: '0.8rem', margin: '0 0 16px' }}>{group.id}</p>

        <label style={{ fontSize: '0.78rem', color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: '0.04em' }}>成员</label>
        {order.length === 0 && <div style={{ color: 'var(--text3)', fontSize: '0.85rem', marginTop: 8 }}>还没有加入任何 feature</div>}
        {order.map((name, i) => {
          const f = features.find((x) => x.name === name);
          return (
            <div key={name} className="group-feature-row">
              <span className="seq">{i + 1}</span>
              <div className="name">
                <div>{f?.title || name}</div>
                <div style={{ fontSize: '0.74rem', color: 'var(--text3)', fontFamily: 'var(--mono)' }}>{name}</div>
              </div>
              <button className="btn btn-sm" disabled={i === 0} onClick={() => move(i, -1)}>↑</button>
              <button className="btn btn-sm" disabled={i === order.length - 1} onClick={() => move(i, 1)}>↓</button>
              <button className="btn btn-sm" onClick={() => removeAt(i)}>✕</button>
            </div>
          );
        })}

        <div className="group-add-row">
          <select value="" onChange={(e) => addFeature(e.target.value)}>
            <option value="">+ 选择要加入的 feature（选中即加入）…</option>
            {notIncluded.map((f) => <option key={f.name} value={f.name}>{f.title || f.name}（{f.name}）</option>)}
          </select>
        </div>

        <div className="form-actions">
          <button className="btn" onClick={save} disabled={saving}>{saving ? '保存中…' : '仅保存顺序'}</button>
          <button className="btn btn-pri" onClick={merge} disabled={merging || order.length === 0}>
            {merging ? '合并中…' : '生成合并视频'}
          </button>
          <button className="btn" style={{ marginLeft: 'auto', color: 'var(--red)' }} onClick={onDelete}>删除分组</button>
        </div>

        {(merging || lines.length > 0) && (
          <div className="log-panel" style={{ marginTop: 16, maxHeight: 160 }}>
            {lines.length === 0 && <span style={{ color: 'var(--log-text-dim)' }}>启动中…</span>}
            {lines.map((l, i) => <div key={i} className={`log-line ${lineClass(l)}`}>{l}</div>)}
          </div>
        )}

        {group.hasOutput && (
          <div style={{ marginTop: 20 }}>
            <label style={{ fontSize: '0.78rem', color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: '0.04em', display: 'block', marginBottom: 8 }}>
              成片预览（groups/{group.id}.mp4）
            </label>
            <video key={nonce} controls style={{ maxWidth: '100%' }} src={`${api.groupFileUrl(project, group.id)}?v=${nonce}`} />
          </div>
        )}

        {history.length > 0 && (
          <div style={{ marginTop: 20 }}>
            <label style={{ fontSize: '0.78rem', color: 'var(--text3)', textTransform: 'uppercase', letterSpacing: '0.04em', display: 'block', marginBottom: 8 }}>历史生成记录</label>
            <table className="srt-table">
              <thead><tr><th>状态</th><th>时间</th></tr></thead>
              <tbody>
                {history.map((h) => (
                  <tr key={h.id}>
                    <td className={lineClass(h.status === 'done' ? '✅' : h.status === 'failed' ? '❌' : '')}>{h.status}</td>
                    <td>{h.startedAt ? new Date(h.startedAt).toLocaleString() : '-'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <div className="form-actions" style={{ justifyContent: 'flex-end' }}>
          <button className="btn" onClick={onClose}>关闭</button>
        </div>
      </div>
    </div>
  );
}
