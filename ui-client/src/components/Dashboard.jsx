import { useEffect, useState } from 'react';
import { api } from '../api.js';
import { useLang } from '../i18n.jsx';
import DataGrid from './DataGrid.jsx';

function featureStatusLabel(f, t) {
  if (f.subMp4) return t('status_done');
  if (f.mp4) return t('status_mixed');
  if (f.recording) return t('status_recorded');
  return t('status_none');
}

const FEATURE_VIEW_KEY = 'vt-ui-feature-view';

export default function Dashboard({ projects, project, onSelectProject, features, onOpenFeature, onNewProject, onNewFeature }) {
  const { t } = useLang();
  const [groupCount, setGroupCount] = useState(0);
  // 两种展示模式都留着，不是二选一删掉另一个——列表信息密度高、适合功能点一多
  // 就要扫状态列；卡片视觉上更直观、适合功能点不多时快速找。默认列表。
  const [featureView, setFeatureView] = useState(() => localStorage.getItem(FEATURE_VIEW_KEY) || 'list');

  function setView(v) {
    setFeatureView(v);
    localStorage.setItem(FEATURE_VIEW_KEY, v);
  }
  const doneCount = features.filter((f) => f.subMp4).length;
  const projectLabel = projects.find((p) => p.name === project)?.displayName || project;

  useEffect(() => {
    if (!project) return;
    api.groups(project).then((gs) => setGroupCount(gs.length)).catch(() => setGroupCount(0));
  }, [project]);

  const projectColumns = [
    { key: 'display', label: t('field_project_name'), sortable: true, sortValue: (p) => p.displayName || p.name, render: (p) => <strong>{p.displayName || p.name}</strong> },
    { key: 'name', label: 'slug', sortable: true },
    { key: 'featureCount', label: t('nav_features'), sortable: true },
    { key: 'company', label: '公司', sortable: true, render: (p) => p.company || '—' },
  ];

  const featureColumns = [
    { key: 'title', label: t('field_title'), sortable: true, sortValue: (f) => f.title || f.name, render: (f) => <strong>{f.title || f.name}</strong> },
    { key: 'name', label: 'slug', sortable: true },
    { key: 'status', label: '状态', sortable: true, sortValue: (f) => featureStatusLabel(f, t), render: (f) => featureStatusLabel(f, t) },
  ];

  return (
    <div>
      <div className="stat-cards">
        <div className="stat-card"><div className="num">{projects.length}</div><div className="label">{t('nav_dashboard_projects')}</div></div>
        <div className="stat-card"><div className="num">{groupCount}</div><div className="label">{projectLabel} · {t('nav_groups')}</div></div>
        <div className="stat-card"><div className="num">{features.length}</div><div className="label">{projectLabel} · {t('nav_features')}</div></div>
        <div className="stat-card"><div className="num">{doneCount}</div><div className="label">{t('status_done')}</div></div>
      </div>

      <div className="dash-section">
        <div className="dash-section-head">
          <h3>{t('nav_dashboard_projects')}</h3>
          <button className="btn btn-sm btn-pri" onClick={onNewProject}>{t('sidebar_new_project')}</button>
        </div>
        <DataGrid
          columns={projectColumns}
          rows={projects}
          rowKey={(p) => p.name}
          onRowClick={(p) => onSelectProject(p.name)}
          emptyText={t('sidebar_empty')}
        />
      </div>

      <div className="dash-section">
        <div className="dash-section-head">
          <h3>{projectLabel} · {t('nav_features')}</h3>
          <div style={{ display: 'flex', gap: 8 }}>
            <div className="view-toggle">
              <button className={featureView === 'list' ? 'active' : ''} title="列表" onClick={() => setView('list')}>☰</button>
              <button className={featureView === 'card' ? 'active' : ''} title="卡片" onClick={() => setView('card')}>▦</button>
            </div>
            <button className="btn btn-sm btn-pri" onClick={onNewFeature}>{t('sidebar_new_feature')}</button>
          </div>
        </div>
        {featureView === 'list' ? (
          <DataGrid
            columns={featureColumns}
            rows={features}
            rowKey={(f) => f.name}
            onRowClick={(f) => onOpenFeature(f.name)}
            emptyText={t('sidebar_empty')}
          />
        ) : (
          <div className="group-grid">
            {features.map((f) => (
              <div key={f.name} className="group-card-summary" onClick={() => onOpenFeature(f.name)}>
                <strong>{f.title || f.name}</strong>
                <div className="meta">{f.name}</div>
                <div className="status-dots" style={{ marginTop: 8 }} title="录制 / 字幕 / 配音 / 成片">
                  <span className={`status-dot${f.recording ? ' on' : ''}`} />
                  <span className={`status-dot${f.subtitles ? ' on' : ''}`} />
                  <span className={`status-dot${f.dub ? ' on' : ''}`} />
                  <span className={`status-dot${f.subMp4 ? ' on' : ''}`} />
                </div>
              </div>
            ))}
            {features.length === 0 && <div className="empty-state">{t('sidebar_empty')}</div>}
          </div>
        )}
      </div>
    </div>
  );
}
