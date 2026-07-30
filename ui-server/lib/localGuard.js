// vt record 会用 AppleScript 真实操控这台 Mac 的屏幕/Terminal/浏览器窗口——
// 发公网后绝不能允许任何公网来源远程点"开始录制"，哪怕鉴权过了也不行，
// 否则等于任何登录进来的人都能远程摆弄这台机器的真实画面。
// 限制成只有本机 loopback 或私网网段（内网）能触发，公网请求一律拒绝。
function ipInPrivateRange(ip) {
  if (!ip) return false;
  const v4 = ip.replace('::ffff:', '');
  if (v4 === '127.0.0.1' || ip === '::1') return true;
  const parts = v4.split('.').map(Number);
  if (parts.length !== 4 || parts.some(Number.isNaN)) return false;
  const [a, b] = parts;
  if (a === 10) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  return false;
}

// 只对"会真实控制屏幕"的命令生效，其余命令（dub/burn/mix/srt 等纯后台合成）不受限。
// codegen 弹出的是一个要人工操作的真实浏览器窗口，跟 record 同一类风险。
const SCREEN_CONTROL_COMMANDS = new Set(['record', 'codegen']);

export function guardScreenCommand(req, res, next) {
  const cmd = req.body?.cmd || req.params?.cmd;
  if (!SCREEN_CONTROL_COMMANDS.has(cmd)) return next();
  const ip = req.ip || req.connection?.remoteAddress || '';
  if (ipInPrivateRange(ip)) return next();
  return res.status(403).json({
    error: `${cmd} 会真实操控本机屏幕，只允许本机/内网触发，当前来源: ${ip}`,
  });
}
