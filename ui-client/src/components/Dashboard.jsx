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

export default function Dashboard({ projects, project, onSelectProject, features, onOpenFeature, onNewProject, onNewFeature }) {
  const { t } = useLang();
  const [groupCount, setGroupCount] = useState(0);
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
          <button className="btn btn-sm btn-pri" onClick={onNewFeature}>{t('sidebar_new_feature')}</button>
        </div>
        <DataGrid
          columns={featureColumns}
          rows={features}
          rowKey={(f) => f.name}
          onRowClick={(f) => onOpenFeature(f.name)}
          emptyText={t('sidebar_empty')}
        />
      </div>
    </div>
  );
}
