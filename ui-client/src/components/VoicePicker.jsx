import { useEffect, useRef, useState } from 'react';
import { api } from '../api.js';

export default function VoicePicker({ value, onChange, lang }) {
  const [voices, setVoices] = useState([]);
  const audioRef = useRef(null);
  const [playing, setPlaying] = useState(null);

  useEffect(() => { api.voices().then(setVoices).catch(() => {}); }, []);

  function play(v) {
    if (!audioRef.current) audioRef.current = new Audio();
    const a = audioRef.current;
    a.src = v.sampleUrl;
    a.onended = () => setPlaying(null);
    a.play();
    setPlaying(v.id);
  }

  const filtered = lang ? voices.filter((v) => v.lang === lang) : voices;

  return (
    <div className="picker-grid">
      {filtered.map((v) => (
        <div
          key={v.id}
          className={`picker-card${value === v.id ? ' selected' : ''}`}
          onClick={() => onChange(v.id)}
        >
          <div className="label" style={{ marginTop: 0 }}>{v.label}</div>
          <button
            type="button"
            className="btn btn-sm play-btn"
            onClick={(e) => { e.stopPropagation(); play(v); }}
          >
            {playing === v.id ? '▶ 播放中…' : '▶ 试听'}
          </button>
        </div>
      ))}
    </div>
  );
}
