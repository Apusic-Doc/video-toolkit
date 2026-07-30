import { useState } from 'react';
import { api } from '../api.js';

export default function Login({ onLoggedIn }) {
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true); setError('');
    try {
      await api.login(password);
      onLoggedIn();
    } catch (e) {
      setError(e.message || '登录失败');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-screen">
      <form className="login-box" onSubmit={submit}>
        <h1>video-toolkit 控制台</h1>
        {error && <div className="login-error">{error}</div>}
        <input
          type="password" placeholder="密码" autoFocus
          value={password} onChange={(e) => setPassword(e.target.value)}
        />
        <button className="btn btn-pri" type="submit" disabled={busy} style={{ width: '100%', justifyContent: 'center' }}>
          {busy ? '登录中…' : '登录'}
        </button>
      </form>
    </div>
  );
}
