// Absences as tally marks (DESIGN.md 8), one of the app's three identity marks.
// The views and the parts added to eClass draw the same one.

import { tallyLabel, tallyStrokes } from './derive.ts';

/** Used strokes in the status color, the ones still allowed faint; no limit: the used ones only. Above 20 marks the words stand alone. */
export function Tally({ used, limit, status, height = 16 }: { used: number; limit: number | null; status: string | null; height?: number }) {
  const t = tallyStrokes(used, limit);
  if (!t) return null;
  return (
    <svg
      class={`tally ${status ? `fg-${status}` : ''}`}
      viewBox={`0 0 ${t.width} 16`}
      style={{ width: `${(t.width * height) / 16}px`, height: `${height}px` }}
      role="img"
      aria-label={tallyLabel(used, limit)}
    >
      {t.strokes.map((s, i) => (
        <line key={i} x1={s.x1} y1={s.y1} x2={s.x2} y2={s.y2} stroke={s.used ? 'currentColor' : 'var(--rule)'} stroke-width="2" stroke-linecap="round" />
      ))}
    </svg>
  );
}
