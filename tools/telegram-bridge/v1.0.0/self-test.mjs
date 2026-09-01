import http from "node:http";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

process.env.BEEFORGE_PLUGIN_SELF_TEST = "1";
process.env.BEEFORGE_PLUGIN_SELF_TEST_PORT = "47657";
const { BeeForgeTelegram } = await import(`./plugin.mjs?selftest=${Date.now()}`);

const key = fs.readFileSync("C:\\AI\\BeeForge AI Console\\secrets\\telegram-bridge.key", "utf8").trim();
const testDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "beeforge-plugin-test-"));
const attachmentPath = path.join(testDirectory, "telegram-input.txt");
fs.writeFileSync(attachmentPath, "attachment self-test", "utf8");
const events = [];
const results = [];
const permissionReplies = [];
const questionReplies = [];
const prompts = [];
let mockCommands = [
  { id: "cmd-permission", type: "permission_reply", api: "v1", sessionId: "s1", requestId: "per_command", reply: "always" },
  { id: "cmd-question", type: "question_reply", api: "v2", sessionId: "s1", requestId: "q1", answer: "Да" },
  { id: "cmd-sessions", type: "list_sessions" },
  { id: "cmd-sync-pending", type: "sync_pending" },
  { id: "cmd-attachment", type: "prompt", sessionId: "s1", prompt: "Проверь вложение", attachments: [{ path: attachmentPath, filename: "telegram-input.txt", mime: "text/plain" }] },
  { id: "cmd-messages", type: "list_messages", sessionId: "s1" },
  { id: "cmd-overview", type: "session_overview", sessionId: "s1" },
  { id: "cmd-fork", type: "fork_session", sessionId: "s1", messageId: "u1" },
  { id: "cmd-revert", type: "revert_session", sessionId: "s1", messageId: "u1" },
  { id: "cmd-worktrees", type: "list_worktrees" },
  { id: "cmd-worktree-create", type: "create_worktree", name: "telegram-test" },
];
const server = http.createServer((request, response) => {
  const chunks = [];
  request.on("data", (chunk) => chunks.push(chunk));
  request.on("end", () => {
    if (request.headers["x-beeforge-key"] !== key) { response.writeHead(401).end(); return; }
    const url = new URL(request.url, "http://127.0.0.1:47657");
    const payload = chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {};
    if (request.method === "POST" && url.pathname === "/event") events.push(payload);
    if (request.method === "POST" && url.pathname === "/result") results.push(payload);
    const body = url.pathname === "/commands" ? { commands: mockCommands.splice(0) } : { ok: true };
    response.writeHead(200, { "content-type": "application/json" }); response.end(JSON.stringify(body));
  });
});

await new Promise((resolve) => server.listen(47657, "127.0.0.1", resolve));
const client = {
  postSessionIdPermissionsPermissionId: async () => { throw new Error('Expected a string starting with "per", got "{permissionID}"'); },
  _client: {
    post: async (args) => {
      if (args.url.startsWith("/session/")) permissionReplies.push(args);
      else questionReplies.push(args);
      return { data: true };
    },
    get: async (args) => {
      if (args.url === "/permission") return { data: [{ id: "pending-p1", sessionID: "s1", permission: "bash", patterns: ["npm test"], always: ["npm test"], metadata: {} }] };
      if (args.url === "/question") return { data: [{ id: "pending-q1", sessionID: "s1", questions: [{ question: "Продолжить?", options: [{ label: "Да" }] }] }] };
      throw new Error(`Unexpected transport URL: ${args.url}`);
    },
  },
  session: {
    messages: async () => ({ data: [
      { info: { id: "u1", role: "user", time: { created: 1 } }, parts: [{ type: "text", text: "Проверь стандартно, включая мобильную версию" }] },
      { info: { id: "a1", role: "assistant", agent: "team-lead", modelID: "Q2", tokens: { input: 1200, output: 300 } }, parts: [{ type: "text", text: "## Completed\n- Build PASS\n## Next Move\n- Проверить браузер\nFiles: src/main.ts\nTELEGRAM_FILE: output/result.zip" }] },
    ] }),
    list: async () => ({ data: [
      { id: "s1", title: "Основная сессия" },
      { id: "child1", title: "Субагент", parentID: "s1" },
    ] }),
    promptAsync: async (args) => { prompts.push(args); return { data: true }; },
    diff: async () => ({ data: [{ file: "src/main.ts" }] }),
    fork: async () => ({ data: { id: "fork-1", title: "Forked" } }),
    revert: async () => ({ data: true }),
  },
  worktree: {
    list: async () => ({ data: [{ name: "wt-1", branch: "telegram-test", directory: `${testDirectory}\\wt-1` }] }),
    create: async () => ({ data: { name: "wt-2", branch: "telegram-test-2", directory: `${testDirectory}\\wt-2` } }),
  },
};

try {
  const hooks = await BeeForgeTelegram({ project: { name: "SelfTest" }, client, directory: testDirectory, worktree: testDirectory });
  await new Promise((resolve) => setTimeout(resolve, 200));
  await hooks.event({ event: { type: "message.updated", properties: { info: { id: "m1", role: "user", sessionID: "s1", agent: "team-lead" } } } });
  await hooks["tool.execute.before"]({ tool: "task", sessionID: "s1" }, { args: { agent: "software-engineer", description: "Реализация" } });
  await hooks.event({ event: { type: "permission.asked", properties: { id: "per_event", sessionID: "s1", permission: "bash", patterns: ["git push --force"], metadata: {} } } });
  await hooks.event({ event: { type: "permission.replied", properties: { permissionID: "per_event", sessionID: "s1", response: "always" } } });
  await hooks.event({ event: { type: "question.asked", properties: { requestID: "q1", sessionID: "s1", questions: [{ question: "Продолжить?", options: [{ label: "Да" }] }] } } });
  await hooks.event({ event: { type: "question.replied", properties: { requestID: "q1", sessionID: "s1" } } });
  await hooks.event({ event: { type: "message.updated", properties: { info: { id: "m2", role: "assistant", sessionID: "s1", agent: "software-engineer", time: { completed: Date.now() } } } } });
  await hooks.event({ event: { type: "session.next.compaction.started", properties: { sessionID: "s1", reason: "auto" } } });
  await hooks.event({ event: { type: "session.next.compaction.ended", properties: { sessionID: "s1", reason: "auto", text: "## Completed\n- Код готов", recent: "## Next Move\n- QA" } } });
  await hooks.event({ event: { type: "session.idle", properties: { sessionID: "s1" } } });
  await hooks.event({ event: { type: "message.part.delta", properties: { sessionID: "s1", text: "PRIVATE_REASONING" } } });
  await new Promise((resolve) => setTimeout(resolve, 250));
  const kinds = events.map((item) => item.kind);
  const required = ["prompted", "delegation", "permission", "permission_closed", "question", "question_closed", "assistant_update", "compaction_started", "compaction_ended", "idle"];
  for (const kind of required) if (!kinds.includes(kind)) throw new Error(`Missing event: ${kind}`);
  if (JSON.stringify(events).includes("PRIVATE_REASONING")) throw new Error("Reasoning leaked into bridge events");
  const prompted = events.find((item) => item.kind === "prompted");
  if (prompted.mode !== "STANDARD" || prompted.agent !== "team-lead") throw new Error("Mode or Team Lead routing mismatch");
  const permissionEvent = events.find((item) => item.kind === "permission");
  if (permissionEvent?.requestId !== "per_event" || !permissionEvent?.detail?.includes("git push --force")) throw new Error("OpenCode string permission event was not normalized");
  await new Promise((resolve) => setTimeout(resolve, 1400));
  if (permissionReplies[0]?.url !== "/session/s1/permissions/per_command" || permissionReplies[0]?.body?.response !== "always") {
    throw new Error("Permission always did not recover from the generated SDK placeholder failure");
  }
  if (questionReplies[0]?.url !== "/question/{requestID}/reply" || questionReplies[0]?.path?.requestID !== "q1" || questionReplies[0]?.body?.answers?.[0]?.[0] !== "Да") throw new Error("Question answer was not passed through the authenticated OpenCode transport");
  const sessionResult = results.find((item) => item.type === "list_sessions");
  if (!sessionResult?.ok || sessionResult.sessions?.length !== 1 || sessionResult.sessions[0].id !== "s1") throw new Error("Subagent sessions were not filtered");
  const syncResult = results.find((item) => item.type === "sync_pending");
  if (!syncResult?.ok || syncResult.permissions?.[0]?.requestId !== "pending-p1" || syncResult.questions?.[0]?.requestId !== "pending-q1") throw new Error("Pending interactions were not synchronized");
  const messageResult = results.find((item) => item.type === "list_messages");
  if (!messageResult?.ok || messageResult.messages?.[0]?.id !== "u1" || messageResult.messages.some((item) => item.preview.includes("PRIVATE_REASONING"))) throw new Error("Safe session history was not returned");
  const overviewResult = results.find((item) => item.type === "session_overview");
  if (!overviewResult?.ok || overviewResult.tokenCount !== 1500 || overviewResult.changedFiles?.[0] !== "src/main.ts") throw new Error("Session overview did not include context and changed files");
  if (!results.find((item) => item.type === "fork_session" && item.ok && item.sessionId === "fork-1")) throw new Error("Session fork command failed");
  if (!results.find((item) => item.type === "revert_session" && item.ok)) throw new Error("Session revert command failed");
  if (!results.find((item) => item.type === "list_worktrees" && item.ok && item.worktrees?.length === 1)) throw new Error("Worktree listing failed");
  if (!results.find((item) => item.type === "create_worktree" && item.ok && item.worktree?.name === "wt-2")) throw new Error("Worktree creation failed");
  const attachmentPrompt = prompts.find((item) => item.body?.parts?.some((part) => part.type === "file"));
  const filePart = attachmentPrompt?.body?.parts?.find((part) => part.type === "file");
  if (!filePart?.url?.startsWith("data:text/plain;base64,") || filePart.filename !== "telegram-input.txt") throw new Error("Telegram attachment was not passed to OpenCode as a file part");
  const assistantEvent = events.find((item) => item.kind === "assistant_update");
  if (assistantEvent?.attachments?.[0] !== "output/result.zip") throw new Error("Outgoing TELEGRAM_FILE marker was not extracted");
  const idleEvent = events.find((item) => item.kind === "idle");
  if (idleEvent?.agent !== "team-lead") throw new Error(`Parent-session final verdict was attributed to ${idleEvent?.agent || "unknown"} instead of team-lead`);
  console.log(`PLUGIN_EVENT_SELF_TEST_OK | ${kinds.join(",")}`);
  await hooks.event({ event: { type: "global.disposed", properties: {} } });
} finally {
  await new Promise((resolve) => server.close(resolve));
  fs.rmSync(testDirectory, { recursive: true, force: true });
}
