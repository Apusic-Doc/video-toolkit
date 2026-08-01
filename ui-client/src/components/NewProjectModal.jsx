import { useState } from 'react';
import { useLang } from '../i18n.jsx';
import { slugify } from '../slug.js';

// 只收集"名称 + 目录 slug"这两个身份信息；字体/语音/封面这些统一样式属性
// 复用现成的 ProjectSettings 完整表单——创建成功后 App.jsx 会紧接着打开它，
// 不在这里重复造一份表单。
export default function NewProjectModal({ onSubmit, onClose }) {
  const { t } = useLang();
  const [name, setName] = useState('');
  const [slug, setSlug] = useState('');
  const [slugTouched, setSlugTouched] = useState(false);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  function onNameChange(v) {
    setName(v);
    if (!slugTouched) setSlug(slugify(v));
  }

  async function submit() {
    if (!slug.trim()) return;
    setSaving(true);
    setError('');
    try {
      await onSubmit({ slug: slug.trim(), displayName: name.trim() });
      onClose();
    } catch (e) {
      setError(e.message);
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" style={{ width: 420, textAlign: 'left' }} onClick={(e) => e.stopPropagation()}>
        <h1 style={{ fontSize: '1.05rem', margin: '0 0 12px' }}>{t('new_project_title')}</h1>

        <div className="form-field" style={{ marginBottom: 12 }}>
          <label>{t('field_project_name')}</label>
          <input type="text" autoFocus value={name} onChange={(e) => onNameChange(e.target.value)} />
        </div>
        <div className="form-field">
          <label>{t('field_slug_project')}</label>
          <input
            type="text" value={slug}
            onChange={(e) => { setSlug(slugify(e.target.value)); setSlugTouched(true); }}
            placeholder={t('new_project_placeholder')}
          />
        </div>

        {error && <div style={{ color: 'var(--red)', fontSize: '0.8rem', marginTop: 8 }}>{error}</div>}
        <div className="form-actions" style={{ justifyContent: 'flex-end' }}>
          <button className="btn" onClick={onClose}>{t('btn_cancel')}</button>
          <button className="btn btn-pri" onClick={submit} disabled={saving || !slug.trim()}>
            {saving ? t('saving') : t('btn_create')}
          </button>
        </div>
      </div>
    </div>
  );
}
