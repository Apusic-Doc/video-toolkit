import { useEffect, useState } from 'react';
import { api } from '../api.js';

export default function FontPicker({ value, onChange }) {
  const [fonts, setFonts] = useState([]);

  useEffect(() => { api.fonts().then(setFonts).catch(() => {}); }, []);

  return (
    <div className="picker-grid">
      {fonts.map((f) => (
        <div
          key={f.id}
          className={`picker-card${value === f.name ? ' selected' : ''}`}
          onClick={() => onChange(f.name)}
        >
          <img src={f.previewUrl} alt={f.label} />
          <div className="label">{f.label}</div>
        </div>
      ))}
    </div>
  );
}
