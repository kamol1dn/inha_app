// The service worker: the only place that reads passwords and talks to the
// services. Pages and content scripts ask it through src/core/rpc.ts and read
// what it caches from chrome.storage.
import './dom-shim.ts';

import { errorInfo, LoginRequired, type ErrorInfo } from '../core/errors.ts';
import type { Service } from '../core/models.ts';
import { serve } from '../core/rpc.ts';
import { clearCache, clearStaleBusy, ensureCacheSchema, writeCache, writeState } from '../core/store.ts';
import { clearLogin, markLoginRejected, readLogin, readSealedLogin, restoreLogin, saveLogin } from '../core/vault.ts';
import { forgetNotified, onNotificationClick, postDueReminders, REMINDER_ALARM } from './notify.ts';
import {
  eclass,
  eclassStop,
  edupage,
  forgetEclassOwner,
  ins,
  keptAlive,
  mail,
  mailPageSize,
  refresh,
  refreshDue,
  retryLogin,
  serviceCache,
  setEclassStop,
  startOver,
  usableLogin,
} from './sync.ts';

declare const __DEV__: boolean;

const TICK = 'tick';
const INS_SYNC_TABS = 'ins.syncTabs'; // tabs opened to read the grades, which close themselves after
const INS_ADOPTED_TABS = 'ins.adoptedTabs'; // INS tabs the student chose to read the grades in

// Whatever a stored busy flag says, nothing is running in a worker that just woke.
void clearStaleBusy();

async function tick(force = false): Promise<void> {
  await refreshDue(force);
  await postDueReminders();
}

chrome.runtime.onInstalled.addListener(async ({ reason }) => {
  await ensureCacheSchema();
  await chrome.alarms.create(TICK, { periodInMinutes: 5, delayInMinutes: 0.1 });
  if (reason === 'install') await chrome.tabs.create({ url: chrome.runtime.getURL('pages/app.html#/welcome') });
});

chrome.runtime.onStartup.addListener(async () => {
  await chrome.alarms.create(TICK, { periodInMinutes: 5, delayInMinutes: 0.1 });
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === TICK) void tick();
  if (alarm.name === REMINDER_ALARM) void postDueReminders();
});

chrome.notifications.onClicked.addListener((id) => {
  onNotificationClick(id).catch((e) => console.warn("IUT: couldn't open a notification", e));
});

// Development builds only: an eClass page can ask for a reload after a rebuild.
if (__DEV__) {
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg?.devReload) chrome.runtime.reload();
  });
}

/** Mail changed on the server: refresh the inbox and counts in the background, with one more run if one had already started. */
const mailChanged = () => void refresh('mail', true);

const fromHost = (sender: chrome.runtime.MessageSender, host: string) => {
  try {
    return new URL(sender.url ?? '').host === host;
  } catch {
    return false;
  }
};

const insTabs = async (key: string) => ((await chrome.storage.session.get(key))[key] as number[] | undefined) ?? [];

/** Whether this tab may read the grades: INS, in a tab the extension opened or the student picked. A page or a link with #iut-sync isn't enough. */
async function insTabAllowed(sender: chrome.runtime.MessageSender): Promise<boolean> {
  const tab = sender.tab?.id;
  if (!fromHost(sender, 'ins.inha.uz') || tab == null) return false;
  return (await insTabs(INS_SYNC_TABS)).includes(tab) || (await insTabs(INS_ADOPTED_TABS)).includes(tab);
}

serve(
  {
    async sync(_, source, force) {
      if (source === 'all') {
        await tick(force);
      } else {
        if (force) await retryLogin(source);
        await refresh(source, force);
      }
      await postDueReminders();
    },

    async saveLogin(_, service, username, password) {
      const previous = await readSealedLogin(service);
      const stop = service === 'eclass' ? await eclassStopCleared() : null;
      await startOver(service);
      await saveLogin(service, { username, password });
      let outcome: ErrorInfo | null = null;
      try {
        if (service === 'eclass') await eclass.verifyLogin();
        if (service === 'mail') {
          mail.forgetRejected(); // the same password typed again is a fresh try
          await mail.unreadCount();
        }
        if (service === 'ins' && !(await ins.verifyLogin())) outcome = { name: 'LoginUntested', message: 'INS is still signed in' };
      } catch (e) {
        // A refused login is not kept, and the one before it stays. An unreachable service keeps it, to try later.
        if (e instanceof LoginRequired) {
          await restoreLogin(service, previous);
          if (stop) await setEclassStop(stop);
          return errorInfo(e);
        }
        outcome = errorInfo(e);
      }
      // Another account now: nothing of the last one's stays.
      if (previous && previous.username !== username.trim()) await forgetAccount(service);
      if (service === 'eclass') await forgetEclassOwner();
      void refresh(service).then(() => postDueReminders());
      return outcome;
    },

    async clearLogin(_, service: Service) {
      await startOver(service);
      await clearLogin(service);
      if (service === 'eclass') {
        // Ended in the browser too, or the next refresh reads it all back through the session.
        await setEclassStop('logout');
        await forgetEclassOwner();
        await eclass.logout().then(() => setEclassStop('out')).catch(() => {});
      }
      await forgetAccount(service);
      await writeState(service, { error: null, at: 0, marksError: null, busy: false });
      await postDueReminders(); // what was in the tray for that account goes with it
    },

    classGroups: () => edupage.classGroups(),

    mailFolder: (_, folder, offset) => mail.folder(folder, mailPageSize, offset),
    mailSearch: (_, folder, query, offset) => mail.search(folder, query, mailPageSize, offset),
    mailMessage: (_, id) => mail.message(id),
    async mailMarkRead(_, id, read) {
      await mail.markRead(id, read);
      mailChanged();
    },
    async mailSend(_, m) {
      await keptAlive(() => mail.send(m));
      mailChanged();
    },
    async mailSaveDraft(_, m) {
      await keptAlive(() => mail.saveDraft(m));
    },
    async mailMove(_, id, to) {
      const moved = await mail.move(id, to);
      mailChanged();
      return moved;
    },
    mailLookup: (_, q) => mail.lookup(q),
    mailAttachment: (_, id) => keptAlive(() => mail.attachment(id)),

    async eclassAutoLogin() {
      if (!(await readLogin('eclass'))) return false;
      // The student asked for this one, whatever stopped it before.
      await retryLogin('eclass');
      await setEclassStop(null);
      await eclass.ensureLoggedIn();
      void refresh('eclass');
      return true;
    },

    async eclassLoggedOut(sender) {
      if (!fromHost(sender, 'eclass.inha.ac.kr')) throw new Error('Not from eClass');
      await startOver('eclass');
      await setEclassStop('out');
    },

    insSyncAllowed: (sender) => insTabAllowed(sender),

    async insAdoptTab(sender) {
      const tab = sender.tab?.id;
      if (!fromHost(sender, 'ins.inha.uz') || tab == null) throw new Error('Not from INS');
      await chrome.storage.session.set({ [INS_ADOPTED_TABS]: [...new Set([...(await insTabs(INS_ADOPTED_TABS)), tab])] });
    },

    async insLogin(sender) {
      // Only ever to a tab the extension opened or the student picked, never to a page that just asks.
      if (!(await insTabAllowed(sender))) throw new Error('Not from INS');
      return usableLogin('ins');
    },

    async insReport(sender, report, error) {
      if (!(await insTabAllowed(sender))) throw new Error('Not from INS');
      if (report) await writeCache('grades', report);
      if (error?.rejected) {
        const tried = await readLogin('ins');
        if (tried) await markLoginRejected('ins', tried);
      }
      await writeState('ins', { busy: false, error, at: Date.now() });
      if (!report) return;
      // A tab opened only to read the grades closes itself once it has.
      const tab = sender.tab!.id!;
      const opened = await insTabs(INS_SYNC_TABS);
      await chrome.storage.session.set({
        [INS_SYNC_TABS]: opened.filter((t) => t !== tab),
        [INS_ADOPTED_TABS]: (await insTabs(INS_ADOPTED_TABS)).filter((t) => t !== tab),
      });
      if (opened.includes(tab)) await chrome.tabs.remove(tab).catch(() => {});
    },

    async insOpenForSync() {
      const tab = await chrome.tabs.create({ url: 'https://ins.inha.uz/ITIS/Start.aspx#iut-sync' });
      if (tab.id != null) await chrome.storage.session.set({ [INS_SYNC_TABS]: [...(await insTabs(INS_SYNC_TABS)), tab.id] });
    },
  },
  errorInfo,
);

/** Clears what stops eClass logins, to test a new one, and says what it was in case the new one is refused. */
async function eclassStopCleared() {
  const stop = await eclassStop();
  await setEclassStop(null);
  return stop;
}

/** Nothing of that account stays: its data, and what it was already told. */
async function forgetAccount(service: Service): Promise<void> {
  await clearCache(serviceCache[service]);
  await forgetNotified(service);
}
