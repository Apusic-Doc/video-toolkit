import { useEffect, useRef, useState } from 'react';
import { useLang } from '../i18n.jsx';

// GitHub 风格的顶栏 "+" 下拉——新建项目/功能/分组这几个入口分散在各自页面里已经够用，
// 这里只是多加一个全局快捷入口，不依赖当前在哪个页面（点了先自动切页面再开对应弹层）
export default function NewMenu({ onNewProject, onNewFeature, onNewGroup }) {
  const { t } = useLang();
  const [open, setOpen] = useState(false);
  const ref = useRef(null);

  useEffect(() => {
    if (!open) return;
    function onDocClick(e) {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    }
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, [open]);

  function pick(fn) {
    setOpen(false);
    fn();
  }

  return (
    <div className="new-menu" ref={ref}>
      <button className="icon-btn" title={t('new_menu_title')} onClick={() => setOpen((v) => !v)}>+</button>
      {open && (
        <div className="new-menu-dropdown">
          <div className="new-menu-item" onClick={() => pick(onNewProject)}>{t('new_project_title')}</div>
          <div className="new-menu-item" onClick={() => pick(onNewFeature)}>{t('new_feature_title')}</div>
          <div className="new-menu-item" onClick={() => pick(onNewGroup)}>{t('new_group_title')}</div>
        </div>
      )}
    </div>
  );
}
