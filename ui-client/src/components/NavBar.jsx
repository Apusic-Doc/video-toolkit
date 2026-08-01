import { useLang } from '../i18n.jsx';

const PAGES = [
  { id: 'features', key: 'nav_features' },
  { id: 'groups', key: 'nav_groups' },
  { id: 'settings', key: 'nav_settings' },
];

export default function NavBar({ projects, project, onProject, onNewProject, page, onPage, theme, onToggleTheme }) {
  const { t, lang, setLang } = useLang();
  return (
    <div className="topnav">
      <div className="brand">🎬 video-toolkit</div>
      <select className="project-select" value={project} onChange={(e) => onProject(e.target.value)}>
        {projects.map((p) => <option key={p.name} value={p.name}>{p.name}</option>)}
      </select>
      <button className="icon-btn" title={t('sidebar_new_project')} onClick={onNewProject}>+</button>
      <div className="pages">
        {PAGES.map((p) => (
          <div key={p.id} className={`page-link${page === p.id ? ' active' : ''}`} onClick={() => onPage(p.id)}>
            {t(p.key)}
          </div>
        ))}
      </div>
      <div className="spacer" />
      <button className="icon-btn" title="Toggle theme" onClick={onToggleTheme}>{theme === 'dark' ? '☀' : '🌙'}</button>
      <button className="icon-btn" title="Switch language" onClick={() => setLang(lang === 'zh' ? 'en' : 'zh')}>🌐</button>
    </div>
  );
}
