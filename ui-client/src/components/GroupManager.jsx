import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { useLang } from '../i18n.jsx';
import NewGroupModal from './NewGroupModal.jsx';
import GroupDetailModal from './GroupDetailModal.jsx';

// 分组只是"元数据 + 合并任务"，不碰任何 feature-*/ 目录下的文件——
// 增删分组、调整组内顺序都是安全的，原始成片永远不受影响，参照 lib/groups.sh 顶部注释。
// 独立页面（不是弹层），卡片网格展示，点卡片打开详情弹窗调整成员/生成合并视频。
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

  const openGroup = groups?.find((g) => g.id === openId) || null;

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
        <div className="group-grid">
          {groups.map((g) => (
            <div key={g.id} className="group-card-summary" onClick={() => setOpenId(g.id)}>
              <strong>{g.title || g.id}</strong>
              <div className="meta">{g.id}</div>
              <div className="count">{g.features.length} 个 feature</div>
            </div>
          ))}
          {groups.length === 0 && <div className="empty-state">{t('groups_empty')}</div>}
        </div>
      )}

      {showNewGroup && (
        <NewGroupModal onSubmit={createGroup} onClose={() => setShowNewGroup(false)} />
      )}
      {openGroup && (
        <GroupDetailModal
          project={project} group={openGroup} features={features}
          onClose={() => setOpenId(null)}
          onChanged={refresh}
          onDelete={() => { removeGroup(openGroup.id); setOpenId(null); }}
          onToast={onToast}
        />
      )}
    </div>
  );
}
