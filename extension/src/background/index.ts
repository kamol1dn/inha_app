// The service worker: the only place that reads passwords and talks to the
// services. Pages and content scripts ask it through src/core/rpc.ts and read
// what it caches from chrome.storage.
import './dom-shim.ts';

import { errorInfo, LoginRequired } from '../core/errors.ts';
import type { Service } from '../core/models.ts';
import { serve } from '../core/rpc.ts';
import { clearCache, writeCache, writeState } from '../core/store.ts';
import { clearLogin, readLogin, saveLogin } from '../core/vault.ts';
import { forgetSeenGrades, onNotificationClick, postDueReminders, REMINDER_ALARM } from './notify.ts';
import { eclass, edupage, ins, mail, mailPageSize, refresh, refreshDue, serviceCache } from './sync.ts';

declare const __DEV__: boolean;

const TICK = 'tick';
const INS_SYNC_TABS = 'ins.syncTabs';

async function tick(force = false): Promise<void> {
  await refreshDue(force);
  await postDueReminders();
}

chrome.runtime.onInstalled.addListener(async ({ reason }) => {
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

chrome.notifications.onClicked.addListener((id) => void onNotificationClick(id));

// Development builds only: an eClass page can ask for a reload after a rebuild.
if (__DEV__) {
  chrome.runtime.onMessage.addListener((msg) => {
    if (msg?.devReload) chrome.runtime.reload();
  });
}

/** Mail changed on the server: refresh the inbox and counts in the background. */
const mailChanged = () => void refresh('mail');

const fromHost = (sender: chrome.runtime.MessageSender, host: string) => {
  try {
    return new URL(sender.url ?? '').host === host;
  } catch {
    return false;
  }
};

serve(
  {
    async sync(_, source, force) {
      if (source === 'all') await tick(force);
      else await refresh(source);
      await postDueReminders();
    },

    async saveLogin(_, service, username, password) {
      await saveLogin(service, { username, password });
      try {
        if (service === 'eclass') await eclass.ensureLoggedIn();
        if (service === 'ins') await ins.ensureLoggedIn();
        if (service === 'mail') await mail.unreadCount();
      } catch (e) {
        // A rejected login is not kept; an unreachable service keeps it, to try later.
        if (e instanceof LoginRequired) await clearLogin(service);
        return errorInfo(e);
      }
      void refresh(service).then(() => postDueReminders());
      return null;
    },

    async clearLogin(_, service: Service) {
      await clearLogin(service);
      await clearCache(serviceCache[service]);
      await writeState(service, { error: null, at: 0, marksError: null });
      if (service === 'eclass') await forgetSeenGrades();
    },

    classGroups: () => edupage.classGroups(),

    mailFolder: (_, folder, offset) => mail.folder(folder, mailPageSize, offset),
    mailMessage: (_, id) => mail.message(id),
    async mailMarkRead(_, id, read) {
      await mail.markRead(id, read);
      mailChanged();
    },
    async mailSend(_, m) {
      await mail.send(m);
      mailChanged();
    },
    async mailSaveDraft(_, m) {
      await mail.saveDraft(m);
    },
    async mailMove(_, id, to) {
      const moved = await mail.move(id, to);
      mailChanged();
      return moved;
    },
    mailLookup: (_, q) => mail.lookup(q),
    mailAttachment: (_, id) => mail.attachment(id),

    async eclassAutoLogin() {
      if (!(await readLogin('eclass'))) return false;
      await eclass.ensureLoggedIn();
      void refresh('eclass');
      return true;
    },

    async eclassRemember(sender, username, password) {
      if (!fromHost(sender, 'eclass.inha.ac.kr')) throw new Error('Not from eClass');
      await saveLogin('eclass', { username, password });
    },

    async insLogin(sender) {
      // Only ever to INS's own page, which the student is signing in to anyway.
      if (!fromHost(sender, 'ins.inha.uz')) throw new Error('Not from INS');
      return readLogin('ins');
    },

    async insReport(sender, report, error) {
      if (!fromHost(sender, 'ins.inha.uz')) throw new Error('Not from INS');
      if (report) await writeCache('grades', report);
      await writeState('ins', { busy: false, error, at: Date.now() });
      // A tab opened only to read the grades closes itself once it has.
      const tabs = ((await chrome.storage.session.get(INS_SYNC_TABS))[INS_SYNC_TABS] as number[] | undefined) ?? [];
      const tab = sender.tab?.id;
      if (report && tab != null && tabs.includes(tab)) {
        await chrome.storage.session.set({ [INS_SYNC_TABS]: tabs.filter((t) => t !== tab) });
        await chrome.tabs.remove(tab).catch(() => {});
      }
    },

    async insOpenForSync() {
      const tab = await chrome.tabs.create({ url: 'https://ins.inha.uz/ITIS/Start.aspx#iut-sync' });
      const tabs = ((await chrome.storage.session.get(INS_SYNC_TABS))[INS_SYNC_TABS] as number[] | undefined) ?? [];
      if (tab.id != null) await chrome.storage.session.set({ [INS_SYNC_TABS]: [...tabs, tab.id] });
    },
  },
  errorInfo,
);
