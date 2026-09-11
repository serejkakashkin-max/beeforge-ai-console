import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const source = fs.readFileSync(new URL('./bridge.mjs', import.meta.url), 'utf8');
const block = source.slice(source.indexOf('async function deleteTelegramMessagesResilient('), source.indexOf('async function telegramUpload('));
const calls = [];
const deleted = new Set();
const notices = [];
const context = vm.createContext({
  config: { allowedChatId: 1, pinnedStatus: true }, pinnedMessageId: 550,
  pendingQuestions: new Map([['pending', {}]]), callbacks: new Map([['menu', {}]]), openRequests: new Map([['permission', {}]]),
  saveBridgeState() {}, audit() {}, updatePinnedStatus: async () => {}, schedulePinnedStatus() {},
  send: async (text) => notices.push(text),
  telegram: async (method, body) => {
    calls.push(method);
    if (method === 'deleteMessages') {
      // One undeletable service message does not make older messages undeletable.
      if (body.message_ids.includes(690)) throw new Error('Telegram deleteMessages: Bad Request: message cannot be deleted');
      for (const id of body.message_ids) deleted.add(id);
    }
    return true;
  },
});
await vm.runInContext(`${block}\nclearRecentTelegramChat(701)`, context);
assert(deleted.has(500), 'Clear stopped after one undeletable message, leaving recent messages');
assert(!deleted.has(550), 'Pinned status must survive');
assert(!calls.includes('pinChatMessage'), 'Clear must not create a new pinned service entry');
assert(!calls.includes('unpinAllChatMessages'), 'Clear must preserve unrelated user pins');
assert(notices.some(text => /част|не удалось/i.test(text)), 'Partial clear must not claim complete success');
assert.equal(context.callbacks.size, 1, 'Preserved menu buttons must remain usable');
assert.equal(context.openRequests.size, 1, 'Clear must not discard pending permissions');
assert.equal(context.pendingQuestions.size, 1, 'Clear must not discard pending questions');
assert(!deleted.has(201), 'Clear must remain bounded to 500 IDs');
notices.length = 0;
context.telegram = async () => { throw new Error('Network unavailable'); };
await vm.runInContext('clearRecentTelegramChat(701)', context);
assert(notices.some(text => /част|не удалось/i.test(text)), 'Network failure must not claim success');
notices.length = 0;
context.telegram = async () => true;
await vm.runInContext('clearRecentTelegramChat(701)', context);
assert(notices.some(text => /Чат очищен/.test(text)), 'Successful cleanup needs a bounded success message');
console.log('CLEAR_CHAT_TEST_OK');
