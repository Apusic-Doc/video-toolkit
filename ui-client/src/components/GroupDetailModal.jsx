import { useEffect, useRef, useState } from 'react';
import { api, openTaskSocket } from '../api.js';

// 分组详情：调整组内 feature 顺序、生成合并视频、删除分组。
// 选择要加入的 feature 是"选中即生效"，不需要额外点一次"加入"按钮。
export default function GroupDetailModal({ project, group, features, onClose, onChanged, onDelete, onToast }) {
  const [order, setOrder] = useState(group.features);
  const [saving, setSaving] = useState(false);
  const [merging, setMerging] = useState(false);
  const [lines, setLines] = useState([]);
  const [nonce, setNonce] = useState(0);
  const wsRef = useRef(null);

  useEffect(() => () => wsRef.current?.close(), []);

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
      <div className="modal-box" style={{ width: 560, maxHeight: '85vh', overflowY: 'auto', textAlign: 'left' }} onClick={(e) => e.stopPropagation()}>
        <h1 style={{ fontSize: '1.05rem', margin: '0 0 4px' }}>{group.title || group.id}</h1>
        <p style={{ color: 'var(--text3)', fontSize: '0.8rem', margin: '0 0 16px' }}>{group.id}</p>

        {order.length === 0 && <div style={{ color: 'var(--text3)', fontSize: '0.85rem' }}>还没有加入任何 feature</div>}
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

        {lines.length > 0 && (
          <div className="log-panel" style={{ marginTop: 10, maxHeight: 160 }}>
            {lines.map((l, i) => <div key={i} className="log-line">{l}</div>)}
          </div>
        )}

        {!merging && lines.some((l) => l.includes(`groups/${group.id}.mp4`)) && (
          <video key={nonce} controls style={{ marginTop: 10, maxWidth: '100%' }} src={`${api.groupFileUrl(project, group.id)}?v=${nonce}`} />
        )}

        <div className="form-actions" style={{ justifyContent: 'flex-end' }}>
          <button className="btn" onClick={onClose}>关闭</button>
        </div>
      </div>
    </div>
  );
}
