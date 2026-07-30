import session from 'express-session';
import crypto from 'crypto';

// 共享密码走 VT_UI_PASSWORD 环境变量。没配置密码时，只允许本机（127.0.0.1/::1）
// 免登录访问，方便本地开发；一旦配了密码，所有来源（含本机）都要登录——
// 这样本地测出来的行为跟发公网后一致，不会出现"本地测着好好的，一上线才发现权限漏了"。
const PASSWORD = process.env.VT_UI_PASSWORD || '';
const SECRET = process.env.VT_UI_SESSION_SECRET || crypto.randomBytes(32).toString('hex');

export const sessionMiddleware = session({
  secret: SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: { httpOnly: true, sameSite: 'lax', maxAge: 7 * 24 * 3600 * 1000 },
});

function isLoopback(req) {
  const ip = req.ip || req.connection?.remoteAddress || '';
  return ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1';
}

export function authStatus(req) {
  if (!PASSWORD) return isLoopback(req) ? 'ok' : 'no-password-remote-denied';
  return req.session?.authed ? 'ok' : 'need-login';
}

export function requireAuth(req, res, next) {
  const status = authStatus(req);
  if (status === 'ok') return next();
  if (status === 'no-password-remote-denied') {
    return res.status(403).json({ error: '未配置 VT_UI_PASSWORD，仅允许本机访问' });
  }
  return res.status(401).json({ error: '需要登录' });
}

export function loginHandler(req, res) {
  const { password } = req.body || {};
  if (!PASSWORD) return res.status(400).json({ error: '服务端未配置密码，无需登录' });
  if (password !== PASSWORD) return res.status(401).json({ error: '密码错误' });
  req.session.authed = true;
  res.json({ ok: true });
}

export function logoutHandler(req, res) {
  req.session.destroy(() => res.json({ ok: true }));
}

export { isLoopback };
