// Light 主题的配色方案库——只影响 light，dark 主题维持原样（没人抱怨过 dark）。
// 每个方案是一组 CSS 变量的具体值，运行时用 element.style.setProperty 直接
// 写到 :root 上覆盖 index.css 里 [data-theme="light"] 定义的默认值，不需要
// 为每个方案单独写一份 CSS 规则块。
export const PALETTES = {
  material: {
    label: 'Google Material 3',
    vars: {
      '--bg': '#fef7ff', '--bg2': '#ffffff', '--bg3': '#f3edf7',
      '--border': '#cac4d0', '--border-hover': '#79747e',
      '--text': '#1d1b20', '--text2': '#49454f', '--text3': '#79747e',
      '--accent': '#6750a4', '--accent2': '#4f378b', '--accent-tint': 'rgba(103,80,164,0.12)',
      '--green': '#146c2e', '--orange': '#8c5000', '--red': '#ba1a1a',
    },
  },
  github: {
    label: 'GitHub Primer',
    vars: {
      '--bg': '#ffffff', '--bg2': '#ffffff', '--bg3': '#f6f8fa',
      '--border': '#d0d7de', '--border-hover': '#8c959f',
      '--text': '#1f2328', '--text2': '#59636e', '--text3': '#8c959f',
      '--accent': '#0969da', '--accent2': '#0550ae', '--accent-tint': 'rgba(9,105,218,0.12)',
      '--green': '#1a7f37', '--orange': '#9a6700', '--red': '#cf222e',
    },
  },
  minimal: {
    label: 'Linear 极简',
    vars: {
      '--bg': '#fafafa', '--bg2': '#ffffff', '--bg3': '#f2f2f3',
      '--border': '#e4e4e7', '--border-hover': '#c7c7cc',
      '--text': '#18181b', '--text2': '#52525b', '--text3': '#a1a1aa',
      '--accent': '#4f46e5', '--accent2': '#4338ca', '--accent-tint': 'rgba(79,70,229,0.12)',
      '--green': '#16794f', '--orange': '#b45309', '--red': '#dc2626',
    },
  },
  warm: {
    label: '暖调赤陶',
    vars: {
      '--bg': '#faf9f5', '--bg2': '#ffffff', '--bg3': '#f0ede5',
      '--border': '#e5e1d8', '--border-hover': '#cbc4b4',
      '--text': '#2b2621', '--text2': '#6b6358', '--text3': '#a39c8f',
      '--accent': '#c96442', '--accent2': '#b0532f', '--accent-tint': 'rgba(201,100,66,0.12)',
      '--green': '#0f9d72', '--orange': '#c47a10', '--red': '#d94040',
    },
  },
};

export const DEFAULT_PALETTE = 'material';

export function applyPalette(paletteId) {
  const root = document.documentElement.style;
  const palette = PALETTES[paletteId] || PALETTES[DEFAULT_PALETTE];
  for (const [k, v] of Object.entries(palette.vars)) root.setProperty(k, v);
}

export function clearPaletteOverrides() {
  const root = document.documentElement.style;
  for (const p of Object.values(PALETTES)) {
    for (const k of Object.keys(p.vars)) root.removeProperty(k);
  }
}
