// eClass's stylesheets assume white paper, in thousands of rules: cells, hovers,
// current-week bars, panels of every plugin. In the dark each one that sets a
// near-white background or near-black text is answered here with the same
// selector on the page's tokens, read from the sheets as loaded so a rule nobody
// listed by hand is covered too. Glass needs the same answers (its tokens have no
// paper), so they hang off html.iut-paint, set in either. moodle.css comes after and wins a tie.

interface Rgba {
  r: number;
  g: number;
  b: number;
  a: number;
}

/** "rgb(245, 245, 246)", "#f5f5f6", "white": what a style declaration may hold. Null for the rest. */
export function parseColor(css: string): Rgba | null {
  const s = css.trim().toLowerCase();
  if (s === 'white') return { r: 255, g: 255, b: 255, a: 1 };
  if (s === 'black') return { r: 0, g: 0, b: 0, a: 1 };
  const rgb = /^rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)(?:[\s,/]+([\d.]+))?\s*\)$/.exec(s);
  if (rgb) return { r: Number(rgb[1]), g: Number(rgb[2]), b: Number(rgb[3]), a: rgb[4] == null ? 1 : Number(rgb[4]) };
  const hex = /^#([0-9a-f]{3}|[0-9a-f]{6})$/.exec(s)?.[1];
  if (!hex) return null;
  const full = hex.length === 3 ? [...hex].map((c) => c + c).join('') : hex;
  return { r: parseInt(full.slice(0, 2), 16), g: parseInt(full.slice(2, 4), 16), b: parseInt(full.slice(4, 6), 16), a: 1 };
}

const lightness = ({ r, g, b }: Rgba) => (Math.max(r, g, b) + Math.min(r, g, b)) / 510;
const saturation = ({ r, g, b }: Rgba) => {
  const max = Math.max(r, g, b);
  return max === 0 ? 0 : (max - Math.min(r, g, b)) / max;
};

/** Each selector of a list under html.iut-paint (dark, or glass). A rule about html itself has nothing to answer. */
export function scopedToDark(selectors: string): string {
  const parts: string[] = [];
  let depth = 0;
  let from = 0;
  for (let i = 0; i < selectors.length; i++) {
    const c = selectors[i];
    if (c === '(' || c === '[') depth++;
    else if (c === ')' || c === ']') depth--;
    else if (c === ',' && depth === 0) {
      parts.push(selectors.slice(from, i));
      from = i + 1;
    }
  }
  parts.push(selectors.slice(from));
  return parts
    .map((p) => p.trim())
    .filter((p) => p && !/^(html|:root)\b/.test(p))
    .map((p) => `html.iut-paint ${p}`)
    .join(', ');
}

/** Things drawn on their own dark or colored ground, whatever the page's paper is. */
const leaveAlone = /video-js|vjs-|progress-bar|\.badge|\.label\b|::selection|::-/;

type Declarations = Pick<CSSStyleDeclaration, 'backgroundColor' | 'color' | 'borderTopColor' | 'borderRightColor' | 'borderBottomColor' | 'borderLeftColor'>;

/** The dark answer to one rule, or null when it sets nothing meant for white paper. */
export function darkRule(selector: string, style: Declarations): string | null {
  if (leaveAlone.test(selector)) return null;
  const out: string[] = [];

  const bg = parseColor(style.backgroundColor);
  const onLight = bg != null && bg.a >= 0.5 && lightness(bg) >= 0.82;
  if (onLight) {
    const white = bg.r >= 254 && bg.g >= 254 && bg.b >= 254;
    // White was the page and off-white a panel or a muted cell. A hover stays one step apart.
    const token = /:hover|:focus/.test(selector) ? '--high' : white ? '--surface' : '--low';
    out.push(`background-color: var(${token}) !important`);
  }

  // Dark text sitting on a color of its own stays, as on a warning button.
  const color = parseColor(style.color);
  const onColor = bg != null && bg.a >= 0.5 && !onLight;
  if (color != null && !onColor && color.a >= 0.5 && lightness(color) <= 0.45 && saturation(color) <= 0.3) {
    out.push('color: var(--on-surface) !important');
  }

  for (const [side, value] of [['top', style.borderTopColor], ['right', style.borderRightColor], ['bottom', style.borderBottomColor], ['left', style.borderLeftColor]] as const) {
    const border = parseColor(value);
    if (border != null && border.a >= 0.5 && lightness(border) >= 0.7 && saturation(border) <= 0.2) {
      out.push(`border-${side}-color: var(--rule) !important`);
    }
  }

  if (!out.length) return null;
  const scoped = scopedToDark(selector);
  return scoped ? `${scoped} { ${out.join('; ')}; }` : null;
}

/** The dark answers to everything in these rules, inside media queries too; print stays on paper. */
export function darkRulesOf(rules: CSSRuleList | readonly CSSRule[]): string[] {
  const out: string[] = [];
  for (const rule of Array.from(rules as ArrayLike<CSSRule>)) {
    const { selectorText, style } = rule as CSSStyleRule;
    if (selectorText && style) {
      const answer = darkRule(selectorText, style);
      if (answer) out.push(answer);
      continue;
    }
    const inner = rule as CSSGroupingRule & Partial<CSSMediaRule>;
    if (inner.cssRules && !/^print\b/i.test(inner.media?.mediaText ?? '')) out.push(...darkRulesOf(inner.cssRules));
  }
  return out;
}
