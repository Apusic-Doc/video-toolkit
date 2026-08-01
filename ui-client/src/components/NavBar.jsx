import { useLang } from '../i18n.jsx';
import { PALETTES } from '../palettes.js';
import NewMenu from './NewMenu.jsx';

const PAGES = [
  { id: 'dashboard', key: 'nav_dashboard' },
  { id: 'features', key: 'nav_features' },
  { id: 'groups', key: 'nav_groups' },
  { id: 'settings', key: 'nav_settings' },
];

export default function NavBar({ projects, project, onProject, onNewProject, onNewFeature, onNewGroup, page, onPage, theme, onToggleTheme, palette, onPalette }) {
  const { t, lang, setLang } = useLang();
  return (
    <div className="topnav">
      <div className="brand">🎬 Video Toolkit</div>
      <div className="pages">
        {PAGES.map((p) => (
          <div key={p.id} className={`page-link${page === p.id ? ' active' : ''}`} onClick={() => onPage(p.id)}>
            {t(p.key)}
          </div>
        ))}
      </div>
      <div className="spacer" />
      <select className="project-select" value={project} onChange={(e) => onProject(e.target.value)}>
        {projects.map((p) => <option key={p.name} value={p.name}>{p.displayName || p.name}</option>)}
      </select>
      <NewMenu onNewProject={onNewProject} onNewFeature={onNewFeature} onNewGroup={onNewGroup} />
      {theme === 'light' && (
        <select className="project-select" title="配色方案" value={palette} onChange={(e) => onPalette(e.target.value)}>
          {Object.entries(PALETTES).map(([id, p]) => <option key={id} value={id}>{p.label}</option>)}
        </select>
      )}
      <button className="icon-btn" title="Toggle theme" onClick={onToggleTheme}>{theme === 'dark' ? '☀' : '🌙'}</button>
      <button className="icon-btn" title="Switch language" onClick={() => setLang(lang === 'zh' ? 'en' : 'zh')}>🌐</button>
    </div>
  );
}
