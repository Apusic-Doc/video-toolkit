import { useEffect, useState } from 'react';
import { api } from '../api.js';

export default function FontPicker({ value, onChange }) {
  const [fonts, setFonts] = useState([]);
  const [zoomed, setZoomed] = useState(null);

  useEffect(() => { api.fonts().then(setFonts).catch(() => {}); }, []);

  return (
    <>
      <div className="picker-grid">
        {fonts.map((f) => (
          <div
            key={f.id}
            className={`picker-card${value === f.name ? ' selected' : ''}`}
            onClick={() => onChange(f.name)}
          >
            <img
              src={f.previewUrl}
              alt={f.label}
              title="点击放大看真实渲染效果"
              onClick={(e) => { e.stopPropagation(); setZoomed(f); }}
            />
            <div className="label">{f.label}</div>
          </div>
        ))}
      </div>

      {zoomed && (
        <div className="modal-overlay" onClick={() => setZoomed(null)}>
          <div className="modal-box" onClick={(e) => e.stopPropagation()}>
            <img src={zoomed.previewUrl} alt={zoomed.label} />
            <div className="modal-close">
              <span style={{ color: 'var(--text2)', fontSize: '0.85rem', marginRight: 12 }}>{zoomed.label}</span>
              <button className="btn btn-sm" onClick={() => setZoomed(null)}>关闭</button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
