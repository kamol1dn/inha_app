// eClass's sign-in page, redone: "Continue as <ID>" signs the browser in with
// the saved login (the worker posts it; this page never sees the password),
// and the form below it can remember a new one, once eClass has accepted it.

import { render } from 'preact';
import { useState } from 'preact/hooks';
import { call } from '../core/rpc.ts';
import { readSnapshot, writeSettings } from '../core/store.ts';
import { afterSignIn, SIGN_IN_TRY, signInForm, signInLooped } from './pages.ts';
import { shadowHost, StatusLine } from './shared.tsx';

/** Whether this tab came back here just after signing in, with the record of it cleared. */
function cameBack(): boolean {
  try {
    const looped = signInLooped(sessionStorage.getItem(SIGN_IN_TRY), Date.now());
    sessionStorage.removeItem(SIGN_IN_TRY);
    return looped;
  } catch {
    return false; // blocked site data: as if it were the first try
  }
}

export function SignIn({ saved, form }: { saved: string | null; form: HTMLFormElement | null }) {
  // The worker's sign-in is in the browser's main cookies. A container tab or a private window has its own, and only its own form reaches those.
  const [ownSession] = useState(cameBack);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(
    ownSession
      ? 'The browser signed in, but this tab didn’t stay signed in. A container tab or a private window keeps its own session, so sign in here.'
      : // eClass's own message after a failed sign-in, in our words where we can.
        document.querySelector('#loginerrormessage, .loginerrors .error, .alert-danger')?.textContent?.trim() || null,
  );
  const [other, setOther] = useState(!saved || ownSession);
  const [user, setUser] = useState((form?.querySelector('input[name="username"]') as HTMLInputElement | null)?.value || saved || '');
  const [pass, setPass] = useState('');
  const [remember, setRemember] = useState(true);
  const goOn = () => {
    try {
      sessionStorage.setItem(SIGN_IN_TRY, String(Date.now()));
    } catch {
      // As in cameBack.
    }
    location.replace(afterSignIn(location.search, location.hash));
  };

  const continueAs = async () => {
    setBusy(true);
    setError(null);
    try {
      if (await call('eclassAutoLogin')) goOn();
      else setOther(true);
    } catch (e) {
      setError((e as Error).name === 'LoginRequired' ? 'eClass didn’t accept the saved password. Sign in below to update it.' : 'Couldn’t reach eClass. Check the connection.');
      setOther(true);
    } finally {
      setBusy(false);
    }
  };

  const submit = async (e: Event) => {
    e.preventDefault();
    if (!form) return;
    setBusy(true);
    setError(null);
    if (remember) {
      // Tried first: a mistyped password never replaces the one that works. It is
      // the same one attempt on eClass's lockout count as the form's would be.
      const trouble = await call('saveLogin', 'eclass', user.trim(), pass).catch((err: Error) => ({ name: err.name, message: err.message }));
      if (trouble?.name === 'LoginRequired') {
        setError('eClass rejected this username or password.');
        setBusy(false);
        return;
      }
      if (!trouble && !ownSession) return goOn(); // the worker's sign-in already holds for this tab
    }
    // eClass's own form does the sign-in, so its checks and redirects stay as they are.
    (form.querySelector('input[name="username"]') as HTMLInputElement).value = user.trim();
    (form.querySelector('input[name="password"]') as HTMLInputElement).value = pass;
    HTMLFormElement.prototype.submit.call(form);
  };

  const initial = (saved ?? user ?? '?').slice(0, 1).toUpperCase();
  return (
    <div class="signin">
      <div class="side">
        <div>
          <h1>IUT</h1>
          <p>eClass, your timetable, grades and university mail, in one place.</p>
        </div>
        <div class="foot">Inha University in Tashkent · Your logins stay in this browser, encrypted.</div>
      </div>
      <div class="form">
        <h2>Sign in to eClass</h2>
        <p class="sub">{saved ? 'Welcome back.' : 'With your student ID and eClass password.'}</p>
        {error && <StatusLine status="danger">{error}</StatusLine>}
        {saved && !ownSession && (
          <button class="continue" disabled={busy} onClick={continueAs} autoFocus>
            <span class="avatar">{initial}</span>
            <span class="who">
              <b>Continue as {saved}</b>
              <span>Saved in IUT for eClass</span>
            </span>
            <span class="arrow">{busy ? 'Signing in…' : 'Continue'}</span>
          </button>
        )}
        {saved && !other && (
          <button class="btn" style={{ marginTop: '12px', alignSelf: 'flex-start', marginLeft: '-12px' }} onClick={() => setOther(true)}>
            Use another account
          </button>
        )}
        {other && (
          <>
            {saved && !ownSession && <div class="or">or</div>}
            <form onSubmit={submit}>
              <div class="field">
                <label for="iut-user">Student ID</label>
                <input id="iut-user" class="input" autoComplete="username" value={user} onInput={(e) => setUser((e.target as HTMLInputElement).value)} required autoFocus={!saved} />
              </div>
              <div class="field">
                <label for="iut-pass">Password</label>
                <input id="iut-pass" class="input" type="password" autoComplete="current-password" value={pass} onInput={(e) => setPass((e.target as HTMLInputElement).value)} required />
              </div>
              <label class="check">
                <input type="checkbox" checked={remember} onChange={(e) => setRemember((e.target as HTMLInputElement).checked)} />
                Remember in IUT for eClass, for one-click sign-in
              </label>
              <button class="btn filled" disabled={busy || !form}>{busy ? 'Signing in…' : 'Sign in'}</button>
            </form>
            {!form && <StatusLine status="warning">eClass’s sign-in form didn’t load. Reload the page.</StatusLine>}
          </>
        )}
        <div class="links">
          <a class="btn" style={{ marginLeft: '-12px' }} href="/login/forgot_password.php">Forgot password</a>
          <a class="btn" href="#" onClick={async (e) => (e.preventDefault(), await writeSettings({ takeover: false }), location.reload())}>Classic sign-in</a>
        </div>
      </div>
    </div>
  );
}

export async function signInPage() {
  const saved = (await readSnapshot()).logins.eclass ?? null;
  const shadow = shadowHost('iut-signin', (el) => document.body.append(el));
  render(<SignIn saved={saved} form={signInForm(document)} />, shadow);
}
