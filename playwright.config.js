import { defineConfig } from '@playwright/test';
// 每个 feature 目录都有自己的 record.spec.js；testDir 默认是本配置文件所在目录，
// 不会向外扫描 feature 目录，所以 cmd_record 会导出 VT_TEST_DIR 指向目标 feature 目录。
export default defineConfig({
  testDir: process.env.VT_TEST_DIR || '.',
  testMatch: '**/record.spec.js',
  use: {
    // 品牌版 Google Chrome（channel:'chrome'）的翻译弹窗是策略锁定的，
    // --disable-translate/--disable-features=Translate 命令行参数实测不生效。
    // 改用 Playwright 自带的 Chromium（同一套 Blink 内核，没有 Google 那层翻译功能，
    // 从源头上不会有这个弹窗），不再依赖不可靠的开关。
    ignoreHTTPSErrors: true,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    // AAS 管控台按 Accept-Language 显示语言（Windows 录制环境是靠把 Edge 首选语言设成中文做到的，
    // 这里用 Playwright locale 达到同样效果）
    locale: 'zh-CN',
    // viewport:null + --start-maximized = 窗口最大化铺满屏幕（任务栏/地址栏仍可见），
    // 不是浏览器 Fullscreen 模式（那样会连地址栏一起隐藏，录制要求里明确要保留浏览器导航栏）
    viewport: null,
    // 用重新签名、改过 CFBundleName/CFBundleDisplayName/CFBundleExecutable 的 Chromium 副本，
    // 菜单栏/进程名显示"Apusic 功能验证"而不是"Google Chrome for Testing"（--window-name 只影响
    // X11 窗口类名，在 macOS 上对菜单栏应用名不起作用，已实测排除）。
    // 副本由 toolkit/rebranded-chromium/build.sh 生成，不随仓库分发。
    launchOptions: {
      // --disable-features=Translate 之前只在品牌版 Chrome 上试过没用，没在自带 Chromium 上试过；
      // 这次录制发现自带 Chromium 也会弹翻译条，补上这个开关防御一下
      args: ['--start-maximized', '--disable-features=Translate,TranslateUI'],
      executablePath: '/Users/martin/Apusic/Product/ApusicAS/Videos/toolkit/rebranded-chromium/Apusic 功能验证.app/Contents/MacOS/Apusic 功能验证',
    },
  },
});
