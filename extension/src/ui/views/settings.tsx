// Settings, and the same page as the welcome on install: the three logins,
// the class group, notifications and how eClass looks.

import { useEffect, useState } from 'preact/hooks';
import { reloadEclass } from '../../content/framed.ts';
import { describeError, type ErrorInfo } from '../../core/errors.ts';
import { serviceLabel, type Service } from '../../core/models.ts';
import { missingHosts, requestHosts } from '../../core/permissions.ts';
import { call } from '../../core/rpc.ts';
import { writeSettings, type NotifyChannel, type Snapshot } from '../../core/store.ts';
import { pastWhen } from '../../data/format.ts';
import type { Status } from '../../data/status.ts';
import { Dialog, frame, StatusLine } from '../common.tsx';

const accounts: { service: Service; title: string; what: string; user: string }[] = [
  { service: 'eclass', title: 'eClass', what: 'Deadlines, attendance, VOD progress and marks. Also signs you in to eClass with one click.', user: 'Student ID' },
  { service: 'mail', title: 'University mail', what: 'Your @student.inha.uz inbox (mail.inha.uz).', user: 'Student ID' },
  { service: 'ins', title: 'INS', what: 'Grades and GPA (ins.inha.uz).', user: 'Student ID' },
];

const signOutWord: Partial<Record<Service, string>> = {
  eclass: 'This removes the saved login and the eClass session in this browser, your deadlines, attendance and marks kept here, and the reminders planned from them.',
  mail: 'This removes the saved login and the mail kept in this browser.',
  ins: 'This removes the saved login and the grades kept in this browser.',
};

/** What saving a login came to. Only a refused one isn't kept; the others are saved, untested. */
function saveResult(err: ErrorInfo | null, a: (typeof accounts)[number]): { status: Status; text: string } {
  if (!err) return { status: 'ok', text: 'Signed in. Loading your data.' };
  if (err.name === 'LoginRequired') return { status: 'danger', text: `${a.title} rejected this username or password.` };
  const said = describeError(err, a.service);
  if (err.name === 'LoginUntested') return { status: 'warning', text: said };
  return { status: 'warning', text: `Saved, but not tested. ${said}` };
}

function Account({ snap, a, prefill }: { snap: Snapshot; a: (typeof accounts)[number]; prefill: { user: string; pass: string } }) {
  const saved = snap.logins[a.service];
  const [user, setUser] = useState(saved ?? '');
  const [pass, setPass] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ status: Status; text: string } | null>(null);
  const [certificate, setCertificate] = useState(false);
  const [leaving, setLeaving] = useState(false);
  useEffect(() => {
    if (!saved && prefill.user) setUser(prefill.user);
    if (!saved && prefill.pass) setPass(prefill.pass);
  }, [prefill.user, prefill.pass]);

  // A success has said its piece once the row above can show the login's state.
  useEffect(() => {
    if (result?.status !== 'ok') return;
    const t = setTimeout(() => setResult(null), 6000);
    return () => clearTimeout(t);
  }, [result]);

  const state = snap.state[a.service];
  // Only a refusal says anything about the password: after eClass's own Log out the login was never tried.
  const rejected = !!state?.error?.rejected || snap.rejectedLogins.includes(a.service);
  const signedOut = !rejected && state?.error?.name === 'LoginRequired';
  const save = async (e: Event) => {
    e.preventDefault();
    setBusy(true);
    setResult(null);
    try {
      const err = await call('saveLogin', a.service, user.trim(), pass);
      setResult(saveResult(err, a));
      setCertificate(!!err?.certificate);
      // Only a refused one isn't kept: then what was typed is still there to correct.
      if (err?.name !== 'LoginRequired') setPass('');
    } catch (err) {
      setResult({ status: 'danger', text: describeError(err, a.service) });
    } finally {
      setBusy(false);
    }
  };

  return (
    <div class="login-block">
      <h3>{a.title}</h3>
      <p class="t-bm muted" style={{ margin: '2px 0 0' }}>{a.what}</p>
      {saved && (
        <div style={{ margin: '8px 0', display: 'flex', alignItems: 'center', gap: '12px', flexWrap: 'wrap' }}>
          {rejected ? (
            <StatusLine status="danger">Sign-in failed for {saved}. Enter the password again.</StatusLine>
          ) : signedOut ? (
            <StatusLine status="info">Saved for {saved} · signed out of {a.title}</StatusLine>
          ) : (
            <StatusLine status="ok">Saved for {saved}{state?.at ? ` · checked ${pastWhen(state.at)}` : ''}</StatusLine>
          )}
          <button class="btn danger" onClick={() => setLeaving(true)}>Sign out</button>
        </div>
      )}
      <form class="login-grid" onSubmit={save}>
        <div class="field">
          <label for={`${a.service}-user`}>{a.user}</label>
          <input id={`${a.service}-user`} class="input" autoComplete="username" value={user} onInput={(e) => setUser((e.target as HTMLInputElement).value)} required />
        </div>
        <div class="field">
          <label for={`${a.service}-pass`}>Password</label>
          <input id={`${a.service}-pass`} class="input" type="password" autoComplete="current-password" value={pass} placeholder={saved ? 'Saved' : ''} onInput={(e) => setPass((e.target as HTMLInputElement).value)} required />
        </div>
        <button class="btn filled" disabled={busy || !user || !pass}>{busy ? 'Checking…' : saved ? 'Update' : 'Save'}</button>
      </form>
      {result && <StatusLine status={result.status}>{result.text}</StatusLine>}
      {certificate && <button class="btn" type="button" onClick={() => call('insOpenForSync')}>Open INS</button>}
      {leaving && (
        <Dialog title={`Sign out of ${a.title}?`} onClose={() => setLeaving(false)}>
          <p class="t-bm" style={{ margin: 0 }}>{signOutWord[a.service]}</p>
          <div class="actions">
            <button class="btn" onClick={() => setLeaving(false)}>Cancel</button>
            <button
              class="btn danger"
              onClick={() => {
                setLeaving(false);
                setResult(null);
                setPass('');
                void call('clearLogin', a.service);
              }}
            >
              Sign out
            </button>
          </div>
        </Dialog>
      )}
    </div>
  );
}

/** Subjects EduPage lists for the group that the student doesn't take. Offered: what the timetable shows now, plus what is already hidden. */
function HiddenSubjects({ snap }: { snap: Snapshot }) {
  const hidden = snap.settings.excludedSubjects;
  const [picked, setPicked] = useState<string[] | null>(null);
  const subjects = [...new Set([...(snap.cache.lessons?.value ?? []).map((l) => l.subject), ...hidden])].sort();
  const save = async () => {
    await writeSettings({ excludedSubjects: picked! });
    setPicked(null);
    void call('sync', 'edupage', true);
  };
  return (
    <div class="row" style={{ alignItems: 'center', minHeight: '48px' }}>
      <div class="main">
        <span class="t-bl">Hidden subjects</span>
        <span class="t-bm muted">{hidden.length ? hidden.join(', ') : subjects.length ? 'None' : "The timetable hasn't loaded yet."}</span>
      </div>
      <button class="btn" disabled={!subjects.length} onClick={() => setPicked(hidden)}>Choose subjects</button>
      {picked && (
        <Dialog title="Hidden subjects" onClose={() => setPicked(null)}>
          <p class="t-bm muted" style={{ margin: '0 0 8px' }}>Ones EduPage lists for your group that you don't take. Ticked ones leave your timetable.</p>
          {subjects.map((s) => (
            <label class="check" key={s}>
              <input type="checkbox" checked={picked.includes(s)} onChange={(e) => setPicked((e.target as HTMLInputElement).checked ? [...picked, s] : picked.filter((x) => x !== s))} />
              <span class="t-bl">{s}</span>
            </label>
          ))}
          <div class="actions">
            <button class="btn" onClick={() => setPicked(null)}>Cancel</button>
            <button class="btn" onClick={save}>Save</button>
          </div>
        </Dialog>
      )}
    </div>
  );
}

const channels: [NotifyChannel, string, string][] = [
  ['deadlines', 'Deadlines', 'Assignments and quizzes, 24 h and 3 h before'],
  ['vod', 'VOD windows', 'Unwatched VODs, 48 h and 6 h before the window closes'],
  ['attendance', 'Attendance', 'When eClass records a new absence'],
  ['classes', 'Classes', '15 min before each class'],
  ['exams', 'Exams', 'The evening before and 1 h before each exam'],
  ['grades', 'Grades', 'A new or changed mark in eClass'],
  ['mail', 'New mail', 'Unread mail in your inbox'],
  ['notices', 'eClass notifications', "New ones from eClass's bell menu"],
];

/** Shown only where the browser left the sites off (Firefox and Zen can), since then nothing loads and it looks like the connection. */
function SiteAccess() {
  const [missing, setMissing] = useState(false);
  useEffect(() => {
    void missingHosts().then((m) => setMissing(m.length > 0));
  }, []);
  if (!missing) return null;
  const allow = async () => {
    if (!(await requestHosts())) return;
    setMissing(false);
    void call('sync', 'all', true);
  };
  return (
    <section class="section">
      <h2>Site access</h2>
      <p class="t-bm muted" style={{ margin: 0 }}>The browser hasn't let this extension reach eClass, INS, mail and the timetable, so nothing can load.</p>
      <button class="btn" style={{ marginTop: '8px' }} onClick={allow}>Allow access</button>
    </section>
  );
}

/** Absence limits' subtitle: how many of the courses with attendance have one. */
function limitsLine(snap: Snapshot): string {
  const tracked = (snap.cache.attendance?.value ?? []).filter((c) => c.classes.length);
  const set = tracked.filter((c) => snap.settings.absenceLimits[c.course.id] != null).length;
  if (!tracked.length) return 'For courses with attendance in eClass';
  return set === 0 ? 'Not set' : `${set} of ${tracked.length} courses set`;
}

export function Settings({ snap, welcome }: { snap: Snapshot; welcome: boolean }) {
  const { settings } = snap;
  // The timetable sync keeps the list; asked for only when it hasn't run yet.
  const [fetched, setFetched] = useState<string[] | null>(null);
  const [groupError, setGroupError] = useState('');
  const groups = snap.cache.classGroups?.value ?? fetched;
  const [same, setSame] = useState({ user: '', pass: '' });
  const loadGroups = () => {
    setGroupError('');
    call('classGroups').then(setFetched, (e) => setGroupError(describeError(e, 'edupage')));
  };
  useEffect(() => {
    if (!snap.cache.classGroups) loadGroups();
  }, []);
  // One no longer on the timetable stays on show, so the picker doesn't quietly read "Choose".
  const groupOptions = groups ? (settings.classGroup && !groups.includes(settings.classGroup) ? [settings.classGroup, ...groups] : groups) : settings.classGroup ? [settings.classGroup] : [];
  const toggle = (k: NotifyChannel) => (e: Event) => writeSettings({ notify: { ...settings.notify, [k]: (e.target as HTMLInputElement).checked } });

  return (
    <div class={welcome ? 'welcome' : ''} style={welcome ? undefined : { maxWidth: '760px' }}>
      {welcome && (
        <>
          <h1>IUT for eClass</h1>
          <p class="t-bl muted">
            eClass, your timetable, INS grades and university mail in one place. Your logins stay in this browser, encrypted, and each one is sent only to
            the service it belongs to. Nothing goes anywhere else.
          </p>
        </>
      )}

      <SiteAccess />

      <section class="section">
        <h2>Class group</h2>
        <p class="t-bm muted" style={{ margin: 0 }}>Your group on the EduPage timetable, for classes and rooms.</p>
        <div style={{ display: 'flex', gap: '12px', marginTop: '8px', alignItems: 'center' }}>
          <select class="input" style={{ maxWidth: '240px' }} value={settings.classGroup} onChange={async (e) => {
            await writeSettings({ classGroup: (e.target as HTMLSelectElement).value });
            void call('sync', 'edupage', true);
          }} aria-label="Class group">
            <option value="">{groups ? 'Choose your group' : groupError ? 'Groups not loaded' : 'Loading groups…'}</option>
            {groupOptions.map((g) => (
              <option key={g}>{g}</option>
            ))}
          </select>
          {groupError && !groups && <button class="btn" onClick={loadGroups}>Retry</button>}
        </div>
        {groupError && !groups && <StatusLine status="danger">{groupError}</StatusLine>}
        <HiddenSubjects snap={snap} />
      </section>

      <section class="section">
        <h2>Accounts</h2>
        {welcome && (
          <div class="login-grid" style={{ marginBottom: '8px' }}>
            <div class="field">
              <label for="same-user">Student ID for all three</label>
              <input id="same-user" class="input" value={same.user} onInput={(e) => setSame({ ...same, user: (e.target as HTMLInputElement).value })} />
            </div>
            <div class="field">
              <label for="same-pass">Password, if it's the same everywhere</label>
              <input id="same-pass" class="input" type="password" value={same.pass} onInput={(e) => setSame({ ...same, pass: (e.target as HTMLInputElement).value })} />
            </div>
            <span />
          </div>
        )}
        {accounts.map((a) => <Account key={a.service} snap={snap} a={a} prefill={same} />)}
      </section>

      <section class="section">
        <h2>Notifications</h2>
        {channels.map(([k, label, what]) => (
          <label class="check" key={k}>
            <input type="checkbox" checked={settings.notify[k]} onChange={toggle(k)} />
            <span>
              <span class="t-bl">{label}</span>
              <br />
              <span class="t-bm muted">{what}</span>
            </span>
          </label>
        ))}
        <label class="check">
          <input type="checkbox" checked={settings.quietHours} onChange={(e) => writeSettings({ quietHours: (e.target as HTMLInputElement).checked })} />
          <span>
            <span class="t-bl">Quiet hours, 23:00 to 07:30</span>
            <br />
            <span class="t-bm muted">Reminders wait for the morning when there is time, or come at 22:00</span>
          </span>
        </label>
      </section>

      {!welcome && (
        <section class="section">
          <h2>Courses</h2>
          <a class="row" href="#/courses/limits" style={{ minHeight: '48px' }}>
            <div class="main">
              <span class="t-bl">Absence limits</span>
              <span class="t-bm muted">{limitsLine(snap)}</span>
            </div>
          </a>
        </section>
      )}

      <section class="section">
        <h2>eClass</h2>
        <label class="check">
          <input
            type="checkbox"
            checked={settings.takeover}
            onChange={async (e) => {
              await writeSettings({ takeover: (e.target as HTMLInputElement).checked });
              // Inside eClass the page around this has to change too.
              if (frame === 'inline') reloadEclass();
            }}
          />
          <span>
            <span class="t-bl">New look on eClass</span>
            <br />
            <span class="t-bm muted">{frame === 'inline' ? 'Off shows eClass exactly as it is' : 'Off shows eClass exactly as it is. Tabs already open change when reloaded.'}</span>
          </span>
        </label>
        <div class="field" style={{ maxWidth: '240px' }}>
          <label for="theme">Theme</label>
          <select id="theme" class="input" value={settings.theme} onChange={(e) => writeSettings({ theme: (e.target as HTMLSelectElement).value as 'system' })}>
            <option value="system">System</option>
            <option value="light">Light</option>
            <option value="dark">Dark</option>
          </select>
        </div>
      </section>

      {!welcome && (
        <section class="section">
          <h2>Sync</h2>
          <div class="rows">
            {(['edupage', 'eclass', 'ins', 'mail'] as Service[]).map((s) => {
              const st = snap.state[s];
              return (
                <div key={s} class="row" style={{ minHeight: '48px', alignItems: 'center' }}>
                  <span class="t-bl" style={{ width: '120px' }}>{serviceLabel[s]}</span>
                  <span class="main" title={st?.error?.message}>
                    {st?.busy ? (
                      <span class="t-bm muted">Updating…</span>
                    ) : st?.error ? (
                      <StatusLine status="danger">{st.error.name === 'SetupNeeded' ? st.error.message : describeError(st.error, s)}</StatusLine>
                    ) : st?.at ? (
                      <StatusLine status="ok">Updated {pastWhen(st.at)}</StatusLine>
                    ) : (
                      <span class="t-bm muted">Not yet</span>
                    )}
                  </span>
                  {st?.error?.certificate ? (
                    <button class="btn" onClick={() => call('insOpenForSync')}>Open INS</button>
                  ) : (
                    <button class="btn" disabled={st?.busy} onClick={() => call('sync', s, true)}>Update</button>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      )}

      {!welcome && (
        <section class="section">
          <h2>About</h2>
          <p class="t-bm tnum" style={{ margin: 0 }}>Version {chrome.runtime.getManifest().version}</p>
          <p class="t-bm muted" style={{ margin: '4px 0 0' }}>The fonts, Fraunces and Public Sans, come with the extension under the SIL Open Font License.</p>
        </section>
      )}

      {welcome && (
        <section class="section">
          <a class="btn filled" href="https://eclass.inha.ac.kr/">Open eClass</a>
        </section>
      )}
    </div>
  );
}
