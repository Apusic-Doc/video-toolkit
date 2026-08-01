import { useState } from 'react';
import { useLang } from '../i18n.jsx';
import { slugify } from '../slug.js';

export default function NewGroupModal({ onSubmit, onClose }) {
  const { t } = useLang();
  const [title, setTitle] = useState('');
  const [id, setId] = useState('');
  const [idTouched, setIdTouched] = useState(false);
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  function onTitleChange(v) {
    setTitle(v);
    if (!idTouched) setId(slugify(v));
  }

  async function submit() {
    if (!id.trim()) return;
    setSaving(true);
    setError('');
    try {
      await onSubmit({ id: id.trim(), title: title.trim() });
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
        <h1 style={{ fontSize: '1.05rem', margin: '0 0 12px' }}>{t('new_group_title')}</h1>

        <div className="form-field" style={{ marginBottom: 12 }}>
          <label>{t('field_title')}</label>
          <input type="text" autoFocus value={title} onChange={(e) => onTitleChange(e.target.value)} />
        </div>
        <div className="form-field">
          <label>{t('field_slug_group')}</label>
          <input
            type="text" value={id}
            onChange={(e) => { setId(slugify(e.target.value)); setIdTouched(true); }}
          />
        </div>

        {error && <div style={{ color: 'var(--red)', fontSize: '0.8rem', marginTop: 8 }}>{error}</div>}
        <div className="form-actions" style={{ justifyContent: 'flex-end' }}>
          <button className="btn" onClick={onClose}>{t('btn_cancel')}</button>
          <button className="btn btn-pri" onClick={submit} disabled={saving || !id.trim()}>
            {saving ? t('saving') : t('btn_create')}
          </button>
        </div>
      </div>
    </div>
  );
}
