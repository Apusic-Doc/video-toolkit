import { useEffect, useRef, useState } from 'react';
import { api, openTaskSocket } from '../api.js';
import { useLang } from '../i18n.jsx';
import NewGroupModal from './NewGroupModal.jsx';

// 分组只是"元数据 + 合并任务"，不碰任何 feature-*/ 目录下的文件——
// 增删分组、调整顺序都是安全的，原始成片永远不受影响，参照 lib/groups.sh 顶部注释。
// 独立页面（不是弹层）：点"分组"导航进来就是这个列表，新建走单独的弹窗，
// 不在列表页常驻一行输入框——跟 Dashboard 的"新建 Feature/Project"是同一个交互习惯。
export default function GroupManager({ project, projectLabel, features, onToast }) {
  const { t } = useLang();
  const [groups, setGroups] = useState(null);
  const [openId, setOpenId] = useState(null);
  const [showNewGroup, setShowNewGroup] = useState(false);

  useEffect(() => {
    api.groups(project).then(setGroups).catch(() => setGroups([]));
  }, [project]);

  function refresh() {
    return api.groups(project).then(setGroups);
  }

  async function createGroup({ id, title }) {
    await api.createGroup(project, id, title);
    await refresh();
    setOpenId(id);
  }

  async function removeGroup(id) {
    if (!confirm(`删除分组「${id}」？只删分组定义，不影响任何 feature 视频文件。`)) return;
    try {
      await api.deleteGroup(project, id);
      if (openId === id) setOpenId(null);
      await refresh();
    } catch (e) {
      onToast(`删除失败: ${e.message}`, 'err');
    }
  }

  return (
    <div>
      <div className="dash-section-head">
        <div>
          <h3 style={{ marginBottom: 4 }}>{t('groups_title')} · {projectLabel}</h3>
          <p style={{ color: 'var(--text2)', fontSize: '0.82rem', margin: 0, maxWidth: 640 }}>{t('groups_desc')}</p>
        </div>
        <button className="btn btn-pri" onClick={() => setShowNewGroup(true)}>+ {t('new_group_title')}</button>
      </div>

      {groups === null ? <div className="empty-state">{t('loading')}</div> : (
        <>
          {groups.map((g) => (
            <GroupRow
              key={g.id} project={project} group={g} features={features}
              open={openId === g.id}
              onToggleOpen={() => setOpenId(openId === g.id ? null : g.id)}
              onChanged={refresh}
              onDelete={() => removeGroup(g.id)}
              onToast={onToast}
            />
          ))}
          {groups.length === 0 && <div className="empty-state">{t('groups_empty')}</div>}
        </>
      )}

      {showNewGroup && (
        <NewGroupModal onSubmit={createGroup} onClose={() => setShowNewGroup(false)} />
      )}
    </div>
  );
}

function GroupRow({ project, group, features, open, onToggleOpen, onChanged, onDelete, onToast }) {
  const [order, setOrder] = useState(group.features);
  const [addPick, setAddPick] = useState('');
  const [saving, setSaving] = useState(false);
  const [merging, setMerging] = useState(false);
  const [lines, setLines] = useState([]);
  const [nonce, setNonce] = useState(0);
  const wsRef = useRef(null);

  useEffect(() => { setOrder(group.features); }, [group.features]);
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
  function addFeature() {
    if (!addPick) return;
    setOrder((prev) => [...prev, addPick]);
    setAddPick('');
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
      const { id } = await api.mergeGroup(project, group.id);
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
    <div style={{ border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '10px 14px', marginBottom: 10 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', cursor: 'pointer' }} onClick={onToggleOpen}>
        <div>
          <strong>{group.title || group.id}</strong>
          <span style={{ color: 'var(--text3)', fontSize: '0.8rem', marginLeft: 8 }}>{group.id} · {group.features.length} 个 feature</span>
        </div>
        <span style={{ color: 'var(--text3)' }}>{open ? '▾' : '▸'}</span>
      </div>

      {open && (
        <div style={{ marginTop: 12 }}>
          {order.length === 0 && <div style={{ color: 'var(--text3)', fontSize: '0.85rem', marginBottom: 8 }}>还没有加入任何 feature</div>}
          {order.map((name, i) => {
            const f = features.find((x) => x.name === name);
            return (
              <div key={name} style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '4px 0' }}>
                <span style={{ width: 20, color: 'var(--text3)', fontSize: '0.8rem' }}>{i + 1}</span>
                <span style={{ flex: 1 }}>{f?.title || name}</span>
                <button className="btn btn-sm" disabled={i === 0} onClick={() => move(i, -1)}>↑</button>
                <button className="btn btn-sm" disabled={i === order.length - 1} onClick={() => move(i, 1)}>↓</button>
                <button className="btn btn-sm" onClick={() => removeAt(i)}>✕</button>
              </div>
            );
          })}

          <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
            <select value={addPick} onChange={(e) => setAddPick(e.target.value)} style={{ flex: 1 }}>
              <option value="">+ 选择要加入的 feature…</option>
              {notIncluded.map((f) => <option key={f.name} value={f.name}>{f.title || f.name}</option>)}
            </select>
            <button className="btn btn-sm" onClick={addFeature} disabled={!addPick}>加入</button>
          </div>

          <div className="form-actions">
            <button className="btn" onClick={save} disabled={saving}>{saving ? '保存中…' : '仅保存顺序'}</button>
            <button className="btn btn-pri" onClick={merge} disabled={merging || order.length === 0}>
              {merging ? '合并中…' : '生成合并视频'}
            </button>
            <button className="btn" style={{ marginLeft: 'auto', color: 'var(--red, #d94040)' }} onClick={onDelete}>删除分组</button>
          </div>

          {lines.length > 0 && (
            <div className="log-panel" style={{ marginTop: 10, maxHeight: 160 }}>
              {lines.map((l, i) => <div key={i} className="log-line">{l}</div>)}
            </div>
          )}

          {!merging && lines.some((l) => l.includes(`groups/${group.id}.mp4`)) && (
            <video key={nonce} controls style={{ marginTop: 10, maxWidth: '100%' }} src={`${api.groupFileUrl(project, group.id)}?v=${nonce}`} />
          )}
        </div>
      )}
    </div>
  );
}
