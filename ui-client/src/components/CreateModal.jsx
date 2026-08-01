import { useState } from 'react';
import { useLang } from '../i18n.jsx';

// 通用的"输入一个名字然后创建"弹层，新建项目/新建 Feature 共用同一个壳
export default function CreateModal({ title, placeholder, hint, onSubmit, onClose }) {
  const { t } = useLang();
  const [value, setValue] = useState('');
  const [error, setError] = useState('');
  const [saving, setSaving] = useState(false);

  async function submit() {
    if (!value.trim()) return;
    setSaving(true);
    setError('');
    try {
      await onSubmit(value.trim());
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
        <h1 style={{ fontSize: '1.05rem', margin: '0 0 12px' }}>{title}</h1>
        {hint && <p style={{ color: 'var(--text2)', fontSize: '0.8rem', margin: '0 0 12px' }}>{hint}</p>}
        <input
          autoFocus value={value} placeholder={placeholder}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') submit(); }}
          style={{ width: '100%', background: 'var(--bg3)', border: '1px solid var(--border)', color: 'var(--text)', padding: '8px 10px', borderRadius: 'var(--radius-sm)' }}
        />
        {error && <div style={{ color: 'var(--red)', fontSize: '0.8rem', marginTop: 8 }}>{error}</div>}
        <div className="form-actions" style={{ justifyContent: 'flex-end' }}>
          <button className="btn" onClick={onClose}>{t('btn_cancel')}</button>
          <button className="btn btn-pri" onClick={submit} disabled={saving || !value.trim()}>
            {saving ? t('saving') : t('btn_create')}
          </button>
        </div>
      </div>
    </div>
  );
}
