import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { darkRule, darkRulesOf, parseColor, scopedToDark } from '../src/content/darkrules.ts';

const decl = (over: Partial<Record<'backgroundColor' | 'color' | 'borderTopColor' | 'borderRightColor' | 'borderBottomColor' | 'borderLeftColor', string>>) => ({
  backgroundColor: '', color: '', borderTopColor: '', borderRightColor: '', borderBottomColor: '', borderLeftColor: '', ...over,
});

describe('darkRule', () => {
  test("eClass's attendance cells: the held ones on the page, the rest a step apart", () => {
    assert.equal(
      darkRule('.format-ubsweeks .user_attendance .attendance_section.active', decl({ backgroundColor: 'rgb(255, 255, 255)' })),
      'html.iut-paint .format-ubsweeks .user_attendance .attendance_section.active { background-color: var(--surface) !important; }',
    );
    assert.equal(
      darkRule('.format-ubsweeks .user_attendance .attendance li', decl({ backgroundColor: '#f5f5f6', borderRightColor: '#ebebeb' })),
      'html.iut-paint .format-ubsweeks .user_attendance .attendance li { background-color: var(--low) !important; border-right-color: var(--rule) !important; }',
    );
  });

  test('a hover over white paper stays apart from the row', () => {
    assert.match(darkRule('.format-ubsweeks li.activity:hover', decl({ backgroundColor: '#f0f2f2' }))!, /background-color: var\(--high\)/);
  });

  test('a tint for white paper goes too, like the current week', () => {
    assert.match(darkRule('.course_box_current h2.main', decl({ backgroundColor: '#f5efd7' }))!, /var\(--low\)/);
  });

  test('near-black text takes the ink, colored text does not', () => {
    assert.match(darkRule('.a', decl({ color: '#333' }))!, /color: var\(--on-surface\)/);
    assert.equal(darkRule('.a', decl({ color: '#337ab7' })), null);
    assert.equal(darkRule('.a', decl({ color: 'white' })), null);
  });

  test('a rule with its own color keeps it, and its text', () => {
    assert.equal(darkRule('.btn-warning', decl({ backgroundColor: '#f0ad4e', color: '#333' })), null);
    assert.equal(darkRule('.name_text0 p', decl({ backgroundColor: '#dc5648', borderTopColor: '#dc5648' })), null);
  });

  test('what is drawn on its own ground is left alone', () => {
    assert.equal(darkRule('.video-js .vjs-play-progress', decl({ backgroundColor: '#fff' })), null);
    assert.equal(darkRule('.progress-bar', decl({ backgroundColor: '#fff' })), null);
    assert.equal(darkRule('.a', decl({ backgroundColor: 'rgba(255, 255, 255, 0.1)' })), null);
    assert.equal(darkRule('.a', decl({})), null);
  });
});

describe('scopedToDark', () => {
  test('every selector of a list, keeping the commas inside brackets', () => {
    assert.equal(scopedToDark('.a, .b:is(.c, .d),.e[x="1,2"]'), 'html.iut-paint .a, html.iut-paint .b:is(.c, .d), html.iut-paint .e[x="1,2"]');
  });
  test('a rule on html itself has nothing to answer; body does', () => {
    assert.equal(scopedToDark('html.foo, :root'), '');
    assert.equal(scopedToDark('body.foo .x'), 'html.iut-paint body.foo .x');
    assert.equal(darkRule('html', decl({ backgroundColor: '#fff' })), null);
  });
});

describe('parseColor', () => {
  test('reads what a declaration may hold', () => {
    assert.deepEqual(parseColor('#fff'), { r: 255, g: 255, b: 255, a: 1 });
    assert.deepEqual(parseColor('rgba(1, 2, 3, 0.5)'), { r: 1, g: 2, b: 3, a: 0.5 });
    assert.deepEqual(parseColor('rgb(1 2 3 / 0.5)'), { r: 1, g: 2, b: 3, a: 0.5 });
    assert.equal(parseColor('transparent'), null);
    assert.equal(parseColor(''), null);
  });
});

describe('darkRulesOf', () => {
  const rule = (selectorText: string, over: Parameters<typeof decl>[0]) => ({ selectorText, style: decl(over) }) as unknown as CSSRule;
  test('reads inside media queries, and leaves print on paper', () => {
    const media = (mediaText: string, ...cssRules: CSSRule[]) => ({ cssRules, media: { mediaText } }) as unknown as CSSRule;
    assert.deepEqual(
      darkRulesOf([
        rule('.a', { backgroundColor: '#fff' }),
        media('(max-width: 600px)', rule('.b', { backgroundColor: '#fff' })),
        media('print', rule('.c', { backgroundColor: '#fff' })),
        rule('.d', { backgroundColor: '#123' }),
      ]),
      ['html.iut-paint .a { background-color: var(--surface) !important; }', 'html.iut-paint .b { background-color: var(--surface) !important; }'],
    );
  });
});
