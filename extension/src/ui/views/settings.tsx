// Settings, and the same page as the welcome on install: the three logins,
// the class group, notifications and how eClass looks.

import { useEffect, useState } from 'preact/hooks';
import { describeError } from '../../core/errors.ts';
import { serviceLabel, type Service } from '../../core/models.ts';
import { call } from '../../core/rpc.ts';
import { writeSettings, type NotifyChannel, type Snapshot } from '../../core/store.ts';
import { pastWhen } from '../../data/format.ts';
import { StatusLine } from '../common.tsx';

const accounts: { service: Service; title: string; what: string; user: string }[] = [
  { service: 'eclass', title: 'eClass', what: 'Deadlines, attendance, VOD progress and marks. Also signs you in to eClass with one click.', user: 'Student ID' },
  { service: 'mail', title: 'University mail', what: 'Your @student.inha.uz inbox (mail.inha.uz).', user: 'Student ID' },
  { service: 'ins', title: 'INS', what: 'Grades and GPA (ins.inha.uz).', user: 'Student ID' },
];

function Account({ snap, a, prefill }: { snap: Snapshot; a: (typeof accounts)[number]; prefill: { user: string; pass: string } }) {
  const saved = snap.logins[a.service];
  const [user, setUser] = useState(saved ?? '');
  const [pass, setPass] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<string | null>(null);
  useEffect(() => {
    if (!saved && prefill.user) setUser(prefill.user);
    if (!saved && prefill.pass) setPass(prefill.pass);
  }, [prefill.user, prefill.pass]);

  const state = snap.state[a.service];
  const save = async (e: Event) => {
    e.preventDefault();
    setBusy(true);
    setResult(null);
    try {
      const err = await call('saveLogin', a.service, user.trim(), pass);
      setResult(err ? describeError(err, a.service) : 'ok');
      if (!err) setPass('');
    } catch (err) {
      setResult(describeError(err, a.service));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div class="login-block">
      <h3>{a.title}</h3>
      <p class="t-bm muted" style={{ margin: '2px 0 0' }}>{a.what}</p>
      {saved && !result && (
        <div style={{ margin: '8px 0', display: 'flex', alignItems: 'center', gap: '12px', flexWrap: 'wrap' }}>
          {state?.error?.name === 'LoginRequired' ? (
            <StatusLine status="danger">Sign-in failed for {saved}. Enter the password again.</StatusLine>
          ) : (
            <StatusLine status="ok">Saved for {saved}{state?.at ? ` · checked ${pastWhen(state.at)}` : ''}</StatusLine>
          )}
          <button class="btn quiet" onClick={() => call('clearLogin', a.service)}>Sign out</button>
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
      {result === 'ok' && <StatusLine status="ok">Signed in. Loading your data.</StatusLine>}
      {result && result !== 'ok' && <StatusLine status="danger">{result}</StatusLine>}
    </div>
  );
}

const channels: [NotifyChannel, string, string][] = [
  ['deadlines', 'Deadlines', 'Assignments and quizzes, 24 h and 3 h before'],
  ['vod', 'VOD windows', 'Unwatched VODs, 48 h and 6 h before the window closes'],
  ['attendance', 'Attendance', 'When eClass records a new absence'],
  ['classes', 'Classes', '15 min before each class'],
  ['grades', 'Grades', 'A new or changed mark in eClass'],
  ['mail', 'New mail', 'Unread mail in your inbox'],
];

export function Settings({ snap, welcome }: { snap: Snapshot; welcome: boolean }) {
  const { settings } = snap;
  // The timetable sync keeps the list; asked for only when it hasn't run yet.
  const [fetched, setFetched] = useState<string[] | null>(null);
  const [groupError, setGroupError] = useState('');
  const groups = snap.cache.classGroups?.value ?? fetched;
  const [same, setSame] = useState({ user: '', pass: '' });
  useEffect(() => {
    if (!snap.cache.classGroups) call('classGroups').then(setFetched, (e) => setGroupError(describeError(e, 'edupage')));
  }, []);
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

      <section class="section">
        <h2>Class group</h2>
        <p class="t-bm muted" style={{ margin: 0 }}>Your group on the EduPage timetable, for classes and rooms.</p>
        <div style={{ display: 'flex', gap: '12px', marginTop: '8px', alignItems: 'center' }}>
          <select class="input" style={{ maxWidth: '240px' }} value={settings.classGroup} onChange={async (e) => {
            await writeSettings({ classGroup: (e.target as HTMLSelectElement).value });
            void call('sync', 'edupage', true);
          }} aria-label="Class group">
            <option value="">{groups ? 'Choose your group' : 'Loading groups…'}</option>
            {(groups ?? (settings.classGroup ? [settings.classGroup] : [])).map((g) => (
              <option key={g}>{g}</option>
            ))}
          </select>
          {groupError && !groups && <StatusLine status="danger">{groupError}</StatusLine>}
        </div>
        <div class="field" style={{ maxWidth: '520px' }}>
          <label for="dropped">Subjects you dropped (EduPage still lists them), separated by commas</label>
          <input id="dropped" class="input" value={settings.excludedSubjects.join(', ')} onChange={async (e) => {
            await writeSettings({ excludedSubjects: (e.target as HTMLInputElement).value.split(',').map((s) => s.trim()).filter(Boolean) });
            void call('sync', 'edupage', true);
          }} />
        </div>
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

      <section class="section">
        <h2>eClass</h2>
        <label class="check">
          <input type="checkbox" checked={settings.takeover} onChange={(e) => writeSettings({ takeover: (e.target as HTMLInputElement).checked })} />
          <span>
            <span class="t-bl">New look on eClass</span>
            <br />
            <span class="t-bm muted">Off shows eClass exactly as it is</span>
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
                  <button class="btn" disabled={st?.busy} onClick={() => call('sync', s, true)}>Update</button>
                </div>
              );
            })}
          </div>
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
