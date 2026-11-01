// What the content script decides from eClass's pages, how the course list's
// rows give way, and what each browser's manifest and the release do.

import assert from 'node:assert/strict';
import { createPublicKey } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { describe, test } from 'node:test';
import { fixture } from './setup.ts';
import { manifestFor, versionOfTag } from '../manifest.ts';
import type { Deadline } from '../src/core/models.ts';
import { afterSignIn, courseListSelector, dueHref, isRoute, isSignInPage, publicRoute, routeOfHash, signInForm, signInLooped, viewUrl } from '../src/content/pages.ts';

const page = (name: string) => new DOMParser().parseFromString(fixture(name), 'text/html') as unknown as Document;
const source = (path: string) => readFileSync(new URL(path, import.meta.url), 'utf8');

describe('which page this is', () => {
  test('the sign-in page has its password form, under its address or another', () => {
    assert.equal(isSignInPage('/login/index.php', page('eclass_login.html')), true);
    assert.equal(isSignInPage('/', page('eclass_login.html')), true);
    assert.ok(signInForm(page('eclass_login.html')));
  });

  test('a signed-in student on the sign-in address, with no form, keeps the page eClass gave', () => {
    assert.equal(isSignInPage('/login/index.php', page('eclass_dashboard.html')), false);
    assert.equal(signInForm(page('eclass_dashboard.html')), null);
  });

  test("other pages aren't the sign-in page", () => {
    assert.equal(isSignInPage('/', page('eclass_dashboard.html')), false);
  });

  test("only the dashboard has the course list: the header's course menu on every page doesn't count", () => {
    assert.ok(page('eclass_dashboard.html').querySelector(courseListSelector)?.querySelector('.course_box'));
    for (const other of ['eclass_upcoming.html', 'eclass_attendance_2622.html', 'eclass_progress_2592.html']) {
      assert.ok(page(other).querySelector('.my-course-lists'), `${other} has the header's menu`);
      assert.equal(page(other).querySelector(courseListSelector), null, other);
    }
  });
});

describe('routes', () => {
  test('only #/ is a route', () => {
    assert.equal(routeOfHash('#/mail/inbox/abc%2B1'), 'mail/inbox/abc%2B1');
    assert.equal(routeOfHash('#/grades/2622?x=1'), 'grades/2622');
    assert.equal(routeOfHash('#section-3'), null);
    assert.equal(routeOfHash('#/'), null);
    assert.equal(routeOfHash(''), null);
  });

  test("a mail message's id never reaches eClass's address", () => {
    assert.equal(publicRoute('mail/inbox/AAMkAD%2Babc%3D'), 'mail/inbox');
    assert.equal(publicRoute('mail/drafts'), 'mail/drafts');
    assert.equal(publicRoute('mail'), 'mail');
    assert.equal(publicRoute('grades/2622'), 'grades/2622');
    assert.equal(publicRoute('courses/limits'), 'courses/limits');
  });

  test('a message between eClass and the frame must hold a route', () => {
    assert.equal(isRoute('mail/inbox/AAMkAD%2Babc%3D'), true);
    assert.equal(isRoute('schedule/2026-11-02'), true);
    assert.equal(isRoute('https://example.org/'), false);
    assert.equal(isRoute('javascript:alert(1)//x y'), false);
    assert.equal(isRoute(''), false);
    assert.equal(isRoute({ route: 'grades' }), false);
  });
});

describe('due links', () => {
  const event = (over: Partial<Deadline>) => ({ moduleId: null, moduleType: null, kind: 'assignment', courseId: null, ...over }) as Deadline;

  test("an event with no activity goes to its course, else to Deadlines, and never to '#'", () => {
    assert.equal(dueHref(event({ moduleId: 5, moduleType: 'assign' })), 'https://eclass.inha.ac.kr/mod/assign/view.php?id=5');
    assert.equal(dueHref(event({ courseId: 2622 })), 'https://eclass.inha.ac.kr/course/view.php?id=2622');
    assert.equal(dueHref(event({})), viewUrl('deadlines'));
  });
});

describe('signing in', () => {
  test('goes on to what the address asked for, and only on eClass', () => {
    assert.equal(afterSignIn('?wantsurl=https%3A%2F%2Feclass.inha.ac.kr%2Fmod%2Fassign%2Fview.php%3Fid%3D5', ''), 'https://eclass.inha.ac.kr/mod/assign/view.php?id=5');
    assert.equal(afterSignIn('?wantsurl=https%3A%2F%2Fexample.org%2F', ''), '/');
    assert.equal(afterSignIn('', ''), '/');
  });

  test('keeps the view a link wanted, but not an anchor of the page', () => {
    assert.equal(afterSignIn('', '#/grades/2622'), '/#/grades/2622');
    assert.equal(afterSignIn('?wantsurl=https%3A%2F%2Feclass.inha.ac.kr%2F', '#/deadlines'), 'https://eclass.inha.ac.kr/#/deadlines');
    assert.equal(afterSignIn('', '#section-3'), '/');
  });

  test('back on the page within a minute means the sign-in never reached this tab', () => {
    const now = 1_800_000_000_000;
    assert.equal(signInLooped(String(now - 5_000), now), true);
    assert.equal(signInLooped(String(now - 61_000), now), false);
    assert.equal(signInLooped(null, now), false);
    assert.equal(signInLooped('garbage', now), false);
  });
});

describe("the course list's rows", () => {
  const moodle = source('../src/content/moodle.css');
  const shadow = source('../src/content/eclass.css');

  test('the row is what is measured, and only in the page content', () => {
    assert.match(moodle, /html\.iut #region-main \.my-course-lists > li \{ container-type: inline-size;/);
    assert.doesNotMatch(moodle, /html\.iut \.my-course-lists > li \{[^}]*container-type/);
  });

  test('with less room the next thing due goes, then the facts move under the name', () => {
    const mid = /@container \(max-width: (\d+)px\) \{[^@]*--facts-next: none;/.exec(moodle);
    const stacked = /@container \(max-width: (\d+)px\) \{[^@]*flex-wrap: wrap;[^@]*flex: 1 1 100%;/.exec(moodle);
    assert.ok(mid && stacked);
    assert.ok(Number(stacked[1]) < Number(mid[1]));
    // At the narrowest wide layout the name has at least 300 px beside the 512 px of facts.
    assert.ok(Number(mid[1]) + 1 - 512 >= 300);
    // And beside the four columns left after that, as well.
    assert.ok(Number(stacked[1]) + 1 - (112 + 56 + 56 + 32 + 3 * 16 + 24) >= 300);
  });

  test("the facts' columns come from what moodle.css measured", () => {
    assert.match(shadow, /grid-template-columns: var\(--facts-columns, 112px 56px 56px 32px 168px\)/);
    assert.match(shadow, /\.fact\.next \{ display: var\(--facts-next, flex\);/);
  });

  test("nothing in the name's column can slide under the facts", () => {
    assert.match(moodle, /#region-main \.my-course-lists a\.course_link \{[^}]*display: flex !important;[^}]*overflow: hidden;/);
    assert.match(moodle, /#region-main \.my-course-lists \.course-name \{[^}]*min-width: 0;/);
  });

  test('where the row could not be measured it is stacked, not squeezed', () => {
    assert.match(moodle, /html\.iut-rows-plain #region-main \.my-course-lists > li \{ container-type: normal; \}/);
    assert.match(moodle, /html\.iut-rows-plain [^{]*\[id\^="iut-course-"\] \{ flex: 1 1 100%;/);
  });
});

describe('what the page can reach', () => {
  test("parts sit in closed shadow roots, and the views aren't rendered on eClass's document", () => {
    assert.match(source('../src/content/shared.tsx'), /attachShadow\(\{ mode: 'closed' \}\)/);
    const view = source('../src/content/view.tsx');
    assert.doesNotMatch(view, /ui\/views/);
    assert.match(view, /pages\/app\.html\?frame=inline/);
    for (const part of ['parts.tsx', 'signin.tsx', 'eclass.tsx', 'shared.tsx', 'view.tsx']) {
      assert.doesNotMatch(source(`../src/content/${part}`), /views\/(index|settings|mail)/, part);
    }
  });
});

describe('the manifests', () => {
  const base = JSON.parse(source('../static/manifest.json'));

  test('Chrome keeps one ID from a fixed public key, and no private key is in the repo', () => {
    const key = createPublicKey({ key: Buffer.from(base.key, 'base64'), format: 'der', type: 'spki' });
    assert.equal(key.asymmetricKeyType, 'rsa');
    assert.equal(manifestFor(base, { firefox: false }).key, base.key);
    assert.doesNotMatch(source('../static/manifest.json'), /PRIVATE KEY/);
  });

  test("Firefox and Zen don't get Chrome's key, and have their add-on ID", () => {
    const m = manifestFor(base, { firefox: true }) as { key?: string; browser_specific_settings: { gecko: { id: string } }; options_page?: string };
    assert.equal(m.key, undefined);
    assert.equal(m.options_page, undefined);
    assert.equal(m.browser_specific_settings.gecko.id, 'iut-eclass@kamol1dn.github.io');
    assert.ok(base.key, 'the base manifest is left as it was');
  });

  test('the frame inside eClass is open to eClass alone', () => {
    const open = base.web_accessible_resources as { resources: string[]; matches: string[] }[];
    const entry = open.find((r) => r.resources.includes('pages/app.html'))!;
    assert.deepEqual(entry.matches, ['https://eclass.inha.ac.kr/*']);
  });

  test('a tag stamps both builds, and the repo stays as it is without one', () => {
    assert.equal(versionOfTag('v1.4.0'), '1.4.0');
    assert.equal(versionOfTag('v1.4.0+5'), '1.4.0');
    assert.equal(versionOfTag('v1.4.0-rc1'), '1.4.0');
    assert.equal(versionOfTag('vnext'), null);
    assert.equal(manifestFor(base, { firefox: false, version: '1.4.0' }).version, '1.4.0');
    assert.equal(manifestFor(base, { firefox: true, version: '1.4.0' }).version, '1.4.0');
    assert.equal(manifestFor(base, { firefox: false }).version, base.version);
  });
});

describe('the release workflow', () => {
  const yml = source('../../.github/workflows/extension.yml');

  test('the Chrome zip is on the release before signing can fail', () => {
    assert.ok(yml.indexOf('Attach the Chrome build') < yml.indexOf('Sign for Firefox and Zen'));
    assert.match(yml, /id: sign\n[^\n]*\n\s+continue-on-error: true/);
  });

  test('an xpi that is not signed says so in its name', () => {
    assert.match(yml, /unsigned="iut-eclass-zen-firefox-\$\{suffix\}-unsigned-temporary\.xpi"/);
    assert.match(yml, /signed=iut-eclass-zen-firefox-\$\{suffix\}\.xpi/);
  });

  test('signing has longer than its own wait, and the job longer than that', () => {
    const ms = Number(/--approval-timeout (\d+)/.exec(yml)![1]);
    const step = Number(/timeout-minutes: (\d+)\n\s+env:\n\s+GH_TOKEN/.exec(yml)![1]);
    const job = Number(/timeout-minutes: (\d+)\n\s+env:\n\s+# Mozilla/.exec(yml)![1]);
    assert.ok(ms / 60_000 < step && step < job);
  });

  test('artifact names hold no slash from a ref like 12/merge', () => {
    assert.match(yml, /ref="\$\{GITHUB_REF_NAME\/\/\\\/\/-\}"/);
    assert.doesNotMatch(yml, /name: [^\n]*github\.ref_name/);
  });
});
