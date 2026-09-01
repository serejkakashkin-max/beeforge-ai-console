import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";

const CONFIG_PATH = "C:\\AI\\BeeForge AI Console\\config\\telegram.json";
const KEY_PATH = "C:\\AI\\BeeForge AI Console\\secrets\\telegram-bridge.key";
const PLUGIN_LOG_PATH = "C:\\AI\\BeeForge AI Console\\runtime\\telegram\\opencode-plugin.log";

function pluginAudit(kind, fields = {}) {
  try {
    fs.mkdirSync(path.dirname(PLUGIN_LOG_PATH), { recursive: true });
    const safe = {};
    for (const [key, value] of Object.entries(fields)) safe[key] = clean(value, 500);
    try {
      if (fs.statSync(PLUGIN_LOG_PATH).size >= 5 * 1024 * 1024) {
        const previous = `${PLUGIN_LOG_PATH}.1`;
        try { fs.unlinkSync(previous); } catch {}
        fs.renameSync(PLUGIN_LOG_PATH, previous);
      }
    } catch {}
    fs.appendFileSync(PLUGIN_LOG_PATH, `${JSON.stringify({ at: new Date().toISOString(), kind, ...safe })}\n`, "utf8");
  } catch {}
}

function loadBridgeSettings() {
  try {
    const config = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
    const key = fs.readFileSync(KEY_PATH, "utf8").trim();
    if (!config.enabled || !key) return null;
    const testPort = process.env.BEEFORGE_PLUGIN_SELF_TEST === "1" ? Number(process.env.BEEFORGE_PLUGIN_SELF_TEST_PORT || 0) : 0;
    return { config, key, baseUrl: `http://127.0.0.1:${testPort || Number(config.bridgePort || 47655)}` };
  } catch { return null; }
}

function clean(value, max = 1600) {
  let text = String(value ?? "")
    .replace(/\b\d{5,}:[A-Za-z0-9_-]{20,}\b/g, "[REDACTED_TOKEN]")
    .replace(/\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi, "Bearer [REDACTED]")
    .replace(/\b(AKIA|ASIA)[A-Z0-9]{16}\b/g, "[REDACTED_AWS_KEY]")
    .replace(/((?:api[_-]?key|token|password|secret|authorization)\s*[:=]\s*)[^\s,;]+/gi, "$1[REDACTED]")
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[REDACTED_PRIVATE_KEY]")
    .replace(/(?:^|[\\/])\.env(?:\.[^\s\\/]*)?/gi, "[REDACTED_ENV]")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "")
    .trim();
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

function unwrap(result) { return result && typeof result === "object" && "data" in result ? result.data : result; }

function canonicalProject(value) {
  try { return path.win32.resolve(String(value || "")).replace(/[\\/]+$/, "").toLowerCase(); }
  catch { return ""; }
}

function isDiscoverableProject(value) {
  const candidate = canonicalProject(value);
  const resolved = path.win32.resolve(String(value || ""));
  const driveRoot = canonicalProject(path.win32.parse(resolved).root);
  const profileRoot = canonicalProject(process.env.USERPROFILE || "");
  return Boolean(candidate && candidate !== driveRoot && (!profileRoot || candidate !== profileRoot));
}

function modeFromText(value) {
  const text = String(value || "").toLowerCase();
  if (/release|релизн|максимально тщательно|публикац|полный аудит перед релизом/.test(text)) return "RELEASE";
  if (/standard|стандарт|проверь нормально|мобильн|полная обычная/.test(text)) return "STANDARD";
  if (/plan.only|plan_only|только план|сначала.*план|пока не (?:начинай|приступай)/.test(text)) return "PLAN_ONLY";
  return "FAST";
}

export const BeeForgeTelegram = async ({ project, client, directory, worktree, serverUrl }) => {
  const instanceDirectory = path.win32.resolve(directory || worktree || process.cwd());
  const instanceId = crypto.createHash("sha256").update(canonicalProject(instanceDirectory)).digest("hex").slice(0, 20);
  let settings = loadBridgeSettings();
  let stopped = false;
  let registered = false;
  let activeAgent = "team-lead";
  const sessionModes = new Map();
  const promptedMessages = new Set();
  const processedAssistantMessages = new Set();
  const sessionMetaCache = new Map();
  const recentCompactions = new Map();
  let lastPollError = "";
  let lastRegistrationIssue = "";

  pluginAudit("plugin_loaded", { instanceId, directory: instanceDirectory, pid: process.pid, project: project?.name || "" });

  function withTimeout(promise, milliseconds, operation) {
    let timer;
    return Promise.race([
      Promise.resolve(promise),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(`${operation} timed out after ${milliseconds}ms`)), milliseconds); }),
    ]).finally(() => clearTimeout(timer));
  }

  function assertSdkResult(result, operation) {
    if (result?.error) throw new Error(`${operation}: ${result.error?.data?.message || result.error?.message || JSON.stringify(result.error)}`);
    return result;
  }

  async function request(route, method = "POST", body) {
    settings ||= loadBridgeSettings();
    if (!settings) throw new Error("BeeForge Telegram is disabled");
    const response = await fetch(`${settings.baseUrl}${route}`, {
      method,
      headers: { "content-type": "application/json", "x-beeforge-key": settings.key },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(6000),
    });
    if (!response.ok) throw new Error(`BeeForge Telegram HTTP ${response.status}`);
    return response.json();
  }

  async function register() {
    settings = loadBridgeSettings();
    if (!settings) return false;
    const explicitlyAllowed = (settings.config.allowedProjects || []).some((item) => canonicalProject(item) === canonicalProject(instanceDirectory));
    const allowed = explicitlyAllowed || (settings.config.allowPreviouslyOpenedProjects === true && isDiscoverableProject(instanceDirectory));
    if (!allowed) {
      registered = false;
      if (lastRegistrationIssue !== "project_not_allowed") pluginAudit("registration_skipped", { instanceId, directory: instanceDirectory, reason: "project_not_allowed" });
      lastRegistrationIssue = "project_not_allowed";
      return false;
    }
    try {
      await request("/register", "POST", { instanceId, directory: instanceDirectory, projectName: clean(project?.name || path.win32.basename(instanceDirectory), 100), pid: process.pid });
      registered = true; lastRegistrationIssue = ""; pluginAudit("registered", { instanceId, directory: instanceDirectory, pid: process.pid }); return true;
    } catch (error) {
      registered = false;
      const message = clean(error?.message || error, 500);
      if (lastRegistrationIssue !== message) pluginAudit("registration_error", { instanceId, error: message });
      lastRegistrationIssue = message;
      return false;
    }
  }

  async function emit(payload) {
    if (!registered && !(await register())) return;
    try { await request("/event", "POST", { instanceId, ...payload }); } catch { registered = false; }
  }

  async function sessionMeta(sessionId) {
    if (!sessionId) return {};
    if (sessionMetaCache.has(sessionId)) return sessionMetaCache.get(sessionId);
    try {
      const list = unwrap(await client.session.list({ query: { directory: instanceDirectory } })) || [];
      for (const item of list) sessionMetaCache.set(item.id, { parentID: item.parentID || "", title: clean(item.title || "", 160) });
    } catch {}
    return sessionMetaCache.get(sessionId) || {};
  }

  async function emitForSession(payload) {
    const meta = await sessionMeta(payload.sessionId);
    return emit({ ...payload, parentID: meta.parentID || "", title: payload.title || meta.title || "" });
  }

  function telegramAttachmentPaths(text) {
    return [...String(text || "").matchAll(/^\s*(?:BEEFORGE_)?TELEGRAM_FILE\s*:\s*(?:`([^`]+)`|"([^"]+)"|(.+?))\s*$/gim)]
      .map((match) => clean(match[1] || match[2] || match[3], 1000)).filter(Boolean).slice(0, 10);
  }

  async function latestAssistantPayload(sessionId) {
    try {
      const result = unwrap(await client.session.messages({ path: { id: sessionId }, query: { directory: instanceDirectory } }));
      const messages = Array.isArray(result) ? result : [];
      for (let index = messages.length - 1; index >= 0; index--) {
        const message = messages[index];
        if (message?.info?.role !== "assistant") continue;
        const text = (message.parts || []).filter((part) => part?.type === "text" && !part.synthetic).map((part) => part.text).join("\n");
        if (text) return {
          text: clean(text, 100000),
          agent: clean(message?.info?.agent || message?.info?.mode || "", 80),
          attachments: telegramAttachmentPaths(text),
        };
      }
    } catch {}
    return { text: "", agent: "", attachments: [] };
  }

  async function latestAssistantText(sessionId) { return (await latestAssistantPayload(sessionId)).text; }

  async function latestUserMode(sessionId) {
    try {
      const result = unwrap(await client.session.messages({ path: { id: sessionId }, query: { directory: instanceDirectory } }));
      const messages = Array.isArray(result) ? result : [];
      for (let index = messages.length - 1; index >= 0; index--) {
        const message = messages[index];
        if (message?.info?.role !== "user") continue;
        const text = (message.parts || []).filter((part) => part?.type === "text" && !part.synthetic).map((part) => part.text).join("\n");
        if (text) return modeFromText(text);
      }
    } catch {}
    return "FAST";
  }

  async function permissionReply(command) {
    if (!command.sessionId || !command.requestId) throw new Error("OpenCode permission request is missing sessionID or permissionID");
    // OpenCode 1.x exposes this generated top-level method to plugins. Newer
    // SDK builds expose one of the namespace variants retained below.
    if (client.postSessionIdPermissionsPermissionId) {
      try {
        return assertSdkResult(await client.postSessionIdPermissionsPermissionId({
          path: { id: command.sessionId, permissionID: command.requestId },
          query: { directory: instanceDirectory },
          body: { response: command.reply },
        }), "postSessionIdPermissionsPermissionId");
      } catch (error) {
        if (!client?._client?.post) throw error;
        // Affected generated clients leave {permissionID} unsubstituted. The
        // authenticated transport is safe to reuse with encoded path segments.
        const session = encodeURIComponent(String(command.sessionId));
        const permission = encodeURIComponent(String(command.requestId));
        return assertSdkResult(await client._client.post({
          url: `/session/${session}/permissions/${permission}`,
          query: { directory: instanceDirectory },
          body: { response: command.reply },
          headers: { "Content-Type": "application/json" },
        }), "permission reply transport");
      }
    }
    if (client.session?.permission?.reply) {
      return assertSdkResult(await client.session.permission.reply({ sessionID: command.sessionId, requestID: command.requestId, reply: command.reply }), "session.permission.reply");
    }
    if (client.permission?.reply) {
      return assertSdkResult(await client.permission.reply({ requestID: command.requestId, directory: instanceDirectory, reply: command.reply }), "permission.reply");
    }
    if (client.permission?.respond) {
      return assertSdkResult(await client.permission.respond({ sessionID: command.sessionId, permissionID: command.requestId, directory: instanceDirectory, response: command.reply }), "permission.respond");
    }
    if (client.permission2?.reply) {
      return assertSdkResult(await client.permission2.reply({ sessionID: command.sessionId, requestID: command.requestId, reply: command.reply }), "permission2.reply");
    }
    throw new Error("OpenCode permission reply API unavailable");
  }

  async function questionReply(command) {
    const answers = [[String(command.answer || "")]];
    if (client.session?.question?.reply) {
      return assertSdkResult(await client.session.question.reply({ sessionID: command.sessionId, requestID: command.requestId, answers }), "session.question.reply");
    }
    if (client.question?.reply) {
      return assertSdkResult(await client.question.reply({ requestID: command.requestId, directory: instanceDirectory, answers }), "question.reply");
    }
    if (client.question2?.reply) {
      return assertSdkResult(await client.question2.reply({ sessionID: command.sessionId, requestID: command.requestId, answers }), "question2.reply");
    }
    // Some OpenCode desktop builds expose the authenticated generated
    // transport, but omit the Question namespace from the top-level client.
    if (client?._client?.post) {
      return assertSdkResult(await client._client.post({
        url: "/question/{requestID}/reply",
        path: { requestID: command.requestId },
        query: { directory: instanceDirectory },
        body: { answers },
      }), "question reply transport");
    }
    throw new Error("OpenCode question reply API unavailable");
  }

  function attachmentParts(attachments = []) {
    const root = fs.realpathSync.native(instanceDirectory);
    const parts = [];
    for (const attachment of attachments.slice(0, 10)) {
      const candidate = path.win32.resolve(String(attachment.path || ""));
      if (!fs.existsSync(candidate)) throw new Error(`Telegram attachment not found: ${candidate}`);
      const resolved = fs.realpathSync.native(candidate);
      const relative = path.win32.relative(root, resolved);
      if (!relative || relative === ".." || relative.startsWith(`..${path.win32.sep}`) || path.win32.isAbsolute(relative)) throw new Error("Telegram attachment is outside the OpenCode project");
      const stat = fs.statSync(resolved);
      if (!stat.isFile() || stat.size > 20 * 1024 * 1024) throw new Error("Telegram attachment is not a regular file or exceeds 20 MB");
      const mime = clean(attachment.mime || "application/octet-stream", 120);
      parts.push({ type: "file", mime, filename: clean(attachment.filename || path.win32.basename(resolved), 180), url: `data:${mime};base64,${fs.readFileSync(resolved).toString("base64")}` });
    }
    return parts;
  }

  async function prompt(sessionId, text, attachments = []) {
    const parts = [{ type: "text", text: String(text) }, ...attachmentParts(attachments)];
    return client.session.promptAsync({ path: { id: sessionId }, query: { directory: instanceDirectory }, body: { agent: "team-lead", parts } });
  }

  async function selectSessionInUi(sessionId) {
    if (!client.tui?.selectSession) return false;
    try {
      await withTimeout(client.tui.selectSession({ query: { directory: instanceDirectory }, body: { sessionID: sessionId } }), 8000, "tui.selectSession");
      pluginAudit("session_selected_in_ui", { instanceId, sessionId });
      return true;
    } catch (error) {
      pluginAudit("session_ui_select_failed", { instanceId, sessionId, error: error?.message || error });
      return false;
    }
  }

  async function rawGet(url, query = {}) {
    if (!client?._client?.get) throw new Error(`OpenCode transport GET unavailable: ${url}`);
    return unwrap(await client._client.get({ url, query: { directory: instanceDirectory, ...query } }));
  }

  async function rawPost(url, body = {}, query = {}) {
    if (!client?._client?.post) throw new Error(`OpenCode transport POST unavailable: ${url}`);
    return unwrap(await client._client.post({ url, query: { directory: instanceDirectory, ...query }, body, headers: { "Content-Type": "application/json" } }));
  }

  async function sessionMessages(sessionId, limit = 20) {
    const result = unwrap(await client.session.messages({ path: { id: sessionId }, query: { directory: instanceDirectory, limit } }));
    return Array.isArray(result) ? result : [];
  }

  async function execute(command) {
    switch (command.type) {
      case "list_sessions": {
        const list = unwrap(await withTimeout(client.session.list({ query: { directory: instanceDirectory } }), 15000, "session.list")) || [];
        return { sessions: list.filter((item) => !item.parentID).map((item) => ({ id: item.id, title: clean(item.title || item.id, 100) })) };
      }
      case "list_messages": {
        const list = await sessionMessages(command.sessionId, 30);
        return { messages: list.slice(-20).map((message) => ({
          id: clean(message?.info?.id || "", 160), role: clean(message?.info?.role || "", 20),
          agent: clean(message?.info?.agent || message?.info?.mode || "", 80),
          createdAt: message?.info?.time?.created || message?.info?.time?.completed || 0,
          preview: clean((message.parts || []).filter((part) => part?.type === "text" && !part.synthetic).map((part) => part.text).join("\n"), 500),
        })).filter((item) => item.id && item.preview) };
      }
      case "session_overview": {
        const list = await sessionMessages(command.sessionId, 6);
        const last = [...list].reverse().find((message) => message?.info?.role === "assistant") || list.at(-1) || {};
        const tokens = last?.info?.tokens || {};
        const tokenCount = Number(tokens.input || 0) + Number(tokens.output || 0) + Number(tokens.reasoning || 0) + Number(tokens.cache?.read || 0);
        let diffs = [];
        try {
          if (client.session?.diff) diffs = unwrap(await client.session.diff({ path: { id: command.sessionId }, query: { directory: instanceDirectory } })) || [];
          else diffs = await rawGet(`/session/${encodeURIComponent(command.sessionId)}/diff`);
        } catch {}
        return { tokenCount, model: clean(last?.info?.modelID || last?.info?.model?.modelID || "", 120), changedFiles: (Array.isArray(diffs) ? diffs : []).map((item) => clean(item.file || item.path || "", 240)).filter(Boolean).slice(0, 30) };
      }
      case "fork_session": {
        let created;
        if (client.session?.fork) created = unwrap(await client.session.fork({ path: { id: command.sessionId }, query: { directory: instanceDirectory }, body: command.messageId ? { messageID: command.messageId } : {} }));
        else created = await rawPost(`/session/${encodeURIComponent(command.sessionId)}/fork`, command.messageId ? { messageID: command.messageId } : {});
        if (!created?.id) throw new Error("OpenCode did not return a forked session ID");
        sessionModes.set(created.id, command.mode || "FAST");
        await selectSessionInUi(created.id);
        return { sessionId: created.id, title: clean(created.title || "Fork", 120) };
      }
      case "revert_session": {
        if (!command.messageId) throw new Error("Message ID is required for revert");
        if (client.session?.revert) await client.session.revert({ path: { id: command.sessionId }, query: { directory: instanceDirectory }, body: { messageID: command.messageId } });
        else await rawPost(`/session/${encodeURIComponent(command.sessionId)}/revert`, { messageID: command.messageId });
        return {};
      }
      case "list_worktrees": {
        let rows;
        if (client.worktree?.list) rows = unwrap(await client.worktree.list({ directory: instanceDirectory }));
        else rows = await rawGet("/experimental/worktree");
        return { worktrees: (Array.isArray(rows) ? rows : []).map((item) => typeof item === "string" ? { name: path.win32.basename(item), directory: item } : { name: clean(item.name || path.win32.basename(item.directory || ""), 100), branch: clean(item.branch || "", 160), directory: clean(item.directory || "", 1000) }).filter((item) => item.directory) };
      }
      case "create_worktree": {
        let created;
        if (client.worktree?.create) created = unwrap(await client.worktree.create({ directory: instanceDirectory, worktreeCreateInput: { name: clean(command.name || "", 80) } }));
        else created = await rawPost("/experimental/worktree", { name: clean(command.name || "", 80) });
        return { worktree: created };
      }
      case "remove_worktree": {
        if (client.worktree?.remove) await client.worktree.remove({ directory: instanceDirectory, worktreeRemoveInput: { directory: command.directory } });
        else if (client?._client?.delete) await client._client.delete({ url: "/experimental/worktree", query: { directory: instanceDirectory }, body: { directory: command.directory } });
        else throw new Error("OpenCode worktree remove API unavailable");
        return {};
      }
      case "sync_pending": {
        const list = unwrap(await withTimeout(client.session.list({ query: { directory: instanceDirectory } }), 15000, "session.list")) || [];
        const permissions = [];
        const questions = [];
        const sessionIds = new Set(list.map((session) => session?.id).filter(Boolean));
        if (!client.session?.permission?.list && client?._client?.get) {
          try {
            const rows = unwrap(await withTimeout(client._client.get({ url: "/permission", query: { directory: instanceDirectory } }), 8000, "permission list transport")) || [];
            for (const item of rows) {
              if (!item?.id || (item.sessionID && !sessionIds.has(item.sessionID))) continue;
              permissions.push({ sessionId: item.sessionID, requestId: item.id, action: clean(item.permission || item.action || item.title || "permission", 120), resources: (item.patterns || item.resources || []).map((value) => clean(value, 500)).slice(0, 20), save: (item.always || item.save || []).map((value) => clean(value, 500)).slice(0, 20), metadata: item.metadata || {} });
            }
          } catch (error) { pluginAudit("sync_pending_permission_error", { instanceId, error: error?.message || error }); }
        }
        if (!client.session?.question?.list && client?._client?.get) {
          try {
            const rows = unwrap(await withTimeout(client._client.get({ url: "/question", query: { directory: instanceDirectory } }), 8000, "question list transport")) || [];
            for (const item of rows) {
              if (!item?.id || (item.sessionID && !sessionIds.has(item.sessionID))) continue;
              questions.push({ sessionId: item.sessionID, requestId: item.id, questions: (item.questions || []).slice(0, 8).map((question) => ({ question: clean(question.question || question.header || "Агент ожидает ответ", 2400), options: (question.options || []).map((option) => clean(typeof option === "string" ? option : option.label || option.description, 120)).filter(Boolean).slice(0, 8) })) });
            }
          } catch (error) { pluginAudit("sync_pending_question_error", { instanceId, error: error?.message || error }); }
        }
        for (const session of list.slice(0, 60)) {
          if (!session?.id) continue;
          if (client.session?.permission?.list) {
            try {
              const rows = unwrap(await withTimeout(client.session.permission.list({ sessionID: session.id }), 8000, "session.permission.list")) || [];
              for (const item of rows) permissions.push({ sessionId: item.sessionID || session.id, requestId: item.id, action: clean(item.action || "permission", 120), resources: (item.resources || []).map((value) => clean(value, 500)).slice(0, 20), save: (item.save || []).map((value) => clean(value, 500)).slice(0, 20), metadata: item.metadata || {} });
            } catch {}
          }
          if (client.session?.question?.list) {
            try {
              const rows = unwrap(await withTimeout(client.session.question.list({ sessionID: session.id }), 8000, "session.question.list")) || [];
              for (const item of rows) questions.push({ sessionId: item.sessionID || session.id, requestId: item.id, questions: (item.questions || []).slice(0, 8).map((question) => ({ question: clean(question.question || question.header || "Агент ожидает ответ", 2400), options: (question.options || []).map((option) => clean(typeof option === "string" ? option : option.label || option.description, 120)).filter(Boolean).slice(0, 8) })) });
            } catch {}
          }
        }
        pluginAudit("sync_pending_completed", { instanceId, permissions: permissions.length, questions: questions.length });
        return { permissions, questions };
      }
      case "new_session": {
        const created = unwrap(await client.session.create({ query: { directory: instanceDirectory }, body: { title: `Telegram · ${clean(command.prompt, 80)}` } }));
        if (!created?.id) throw new Error("OpenCode did not return a session ID");
        sessionModes.set(created.id, command.mode || modeFromText(command.prompt));
        await selectSessionInUi(created.id);
        await prompt(created.id, command.prompt, command.attachments);
        return { sessionId: created.id };
      }
      case "select_session": await selectSessionInUi(command.sessionId); return {};
      case "prompt": sessionModes.set(command.sessionId, modeFromText(command.prompt)); await prompt(command.sessionId, command.prompt, command.attachments); return {};
      case "abort": await client.session.abort({ path: { id: command.sessionId }, query: { directory: instanceDirectory } }); return {};
      case "permission_reply": await permissionReply(command); return {};
      case "question_reply": await questionReply(command); return {};
      default: throw new Error(`Unsupported bridge command: ${command.type}`);
    }
  }

  async function poll() {
    while (!stopped) {
      try {
        if (!registered && !(await register())) { await new Promise((r) => setTimeout(r, 3000)); continue; }
        const response = await request(`/commands?instanceId=${encodeURIComponent(instanceId)}`, "GET");
        for (const command of response.commands || []) {
          pluginAudit("command_received", { instanceId, commandId: command.id, type: command.type });
          try {
            const result = await execute(command);
            await request("/result", "POST", { commandId: command.id, type: command.type, ok: true, instanceId, projectName: clean(project?.name || path.win32.basename(instanceDirectory), 100), ...result });
            pluginAudit("command_completed", { instanceId, commandId: command.id, type: command.type });
          } catch (error) {
            await request("/result", "POST", { commandId: command.id, type: command.type, ok: false, instanceId, error: clean(error?.message || error, 1600) });
            pluginAudit("command_failed", { instanceId, commandId: command.id, type: command.type, error: error?.message || error });
          }
        }
        lastPollError = "";
      } catch (error) {
        registered = false;
        const message = clean(error?.message || error, 500);
        if (message !== lastPollError) { lastPollError = message; pluginAudit("poll_error", { instanceId, error: message }); }
      }
      await new Promise((resolve) => setTimeout(resolve, 1200));
    }
  }

  register().then(() => poll()).catch((error) => pluginAudit("poll_fatal", { instanceId, error: error?.stack || error?.message || error }));

  return {
    "tool.execute.before": async (input, output) => {
      if (String(input?.tool || "").toLowerCase() !== "task") return;
      const args = output?.args || {};
      activeAgent = clean(args.agent || args.subagent_type || args.name || "specialist", 80);
      await emitForSession({ kind: "delegation", sessionId: input?.sessionID || input?.sessionId, agent: activeAgent, detail: clean(args.description || args.prompt || "Назначена подзадача", 800) });
    },
    event: async ({ event }) => {
      const type = String(event?.type || "");
      const p = event?.properties || {};
      const sessionId = p.sessionID || p.sessionId || p.session?.id || p.id;
      if (!type || type.includes("reasoning") || type.includes("text.delta") || type === "message.part.delta") return;
      if (type === "message.updated") {
        const info = p.info || p.message || p;
        const messageId = info.id || p.messageID;
        const promptSessionId = info.sessionID || sessionId;
        if (info.role === "user") {
          if (messageId && promptedMessages.has(messageId)) return;
          if (messageId) promptedMessages.add(messageId);
          const mode = await latestUserMode(promptSessionId);
          sessionModes.set(promptSessionId, mode);
          return emitForSession({ kind: "prompted", sessionId: promptSessionId, agent: clean(info.agent || "team-lead", 80), mode, status: "running" });
        }
        if (info.role === "assistant" && info.time?.completed) {
          if (messageId && processedAssistantMessages.has(messageId)) return;
          if (messageId) processedAssistantMessages.add(messageId);
          const latest = await latestAssistantPayload(promptSessionId);
          if (latest.text) return emitForSession({ kind: "assistant_update", sessionId: promptSessionId, messageId, agent: clean(latest.agent || info.agent || info.mode || activeAgent, 80), status: "working", finalText: latest.text, attachments: latest.attachments });
        }
        return;
      }
      if (type === "session.next.compaction.started") {
        return emitForSession({ kind: "compaction_started", sessionId, agent: activeAgent, reason: clean(p.reason || "auto", 20), status: "compacting" });
      }
      if (type === "session.next.compaction.ended") {
        recentCompactions.set(sessionId, Date.now());
        const finalText = clean([p.text, p.recent].filter(Boolean).join("\n\n"), 5000) || await latestAssistantText(sessionId);
        return emitForSession({ kind: "compaction_ended", sessionId, agent: activeAgent, reason: clean(p.reason || "auto", 20), status: "working", finalText });
      }
      if (type === "session.compacted") {
        if (Date.now() - (recentCompactions.get(sessionId) || 0) < 15000) return;
        recentCompactions.set(sessionId, Date.now());
        return emitForSession({ kind: "compaction_ended", sessionId, agent: activeAgent, reason: "auto", status: "working", finalText: await latestAssistantText(sessionId) });
      }
      if (type === "session.next.agent.switched") {
        activeAgent = clean(p.agent || p.agentID || p.to || "specialist", 80);
        return emitForSession({ kind: "delegation", sessionId, agent: activeAgent, detail: clean(p.title || p.task || "Передача следующему специалисту", 800) });
      }
      if ((type === "session.next.tool.called" || type === "tool.execute.before") && String(p.tool || p.name || "").toLowerCase() === "task") {
        const input = p.input || p.args || {};
        activeAgent = clean(input.agent || input.subagent_type || input.name || "specialist", 80);
        return emitForSession({ kind: "delegation", sessionId, agent: activeAgent, detail: clean(input.description || input.prompt || "Назначена подзадача", 800) });
      }
      if (type === "permission.updated" || type === "permission.asked" || type === "permission.v2.asked") {
        const nestedRequest = p.request && typeof p.request === "object"
          ? p.request
          : (p.permission && typeof p.permission === "object" ? p.permission : null);
        const request = nestedRequest || p;
        const permissionName = request.title || request.action || (typeof request.permission === "string" ? request.permission : "") || request.type || (typeof p.permission === "string" ? p.permission : "") || "permission";
        return emitForSession({
          kind: "permission",
          api: type.includes("v2") ? "v2" : "v1",
          sessionId: p.sessionID || request.sessionID,
          requestId: p.permissionID || p.requestID || p.id || request.permissionID || request.requestID || request.id,
          agent: clean(request.agent || activeAgent, 80),
          permission: clean(permissionName, 120),
          detail: clean(JSON.stringify({
            action: permissionName,
            resources: request.resources || request.patterns || request.pattern,
            always: request.always || request.save,
            metadata: request.metadata,
          }), 1700),
        });
      }
      if (type === "permission.replied" || type === "permission.v2.replied") {
        const nestedRequest = p.request && typeof p.request === "object"
          ? p.request
          : (p.permission && typeof p.permission === "object" ? p.permission : null);
        const request = nestedRequest || p;
        return emitForSession({ kind: "permission_closed", sessionId: p.sessionID || request.sessionID, requestId: p.permissionID || p.requestID || p.id || request.permissionID || request.requestID || request.id });
      }
      if (type === "question.asked" || type === "question.v2.asked") {
        const request = p.request || p;
        const questions = request.questions || [];
        const first = questions[0] || request.question || {};
        const options = (first.options || []).map((item) => typeof item === "string" ? item : item.label || item.description).filter(Boolean);
        return emitForSession({ kind: "question", api: type.includes("v2") ? "v2" : "v1", sessionId: p.sessionID || request.sessionID, requestId: p.requestID || request.id || request.requestID, agent: clean(request.agent || activeAgent, 80), question: clean(first.question || first.header || request.text || "Агент ожидает ответ", 2400), options, createdAt: Date.now() });
      }
      if (type === "question.replied" || type === "question.v2.replied" || type === "question.rejected" || type === "question.v2.rejected") {
        const request = p.request || p;
        return emitForSession({ kind: "question_closed", sessionId: p.sessionID || request.sessionID, requestId: p.requestID || request.id || request.requestID });
      }
      if (type === "session.next.prompted") {
        const mode = clean(p.mode || sessionModes.get(sessionId) || await latestUserMode(sessionId), 20);
        sessionModes.set(sessionId, mode);
        return emitForSession({ kind: "prompted", sessionId, agent: clean(p.agent || activeAgent, 80), mode, status: "running" });
      }
      if (type === "session.error" || type === "session.next.step.failed" || type === "workspace.failed") return emitForSession({ kind: "error", sessionId, agent: activeAgent, status: "error", detail: clean(p.error?.message || p.message || JSON.stringify(p.error || {}), 2500) });
      if (type === "session.idle") {
        const latest = await latestAssistantPayload(sessionId);
        const meta = await sessionMeta(sessionId);
        const finalAgent = latest.agent || (meta.parentID ? activeAgent : "team-lead");
        return emitForSession({ kind: "idle", sessionId, agent: clean(finalAgent, 80), status: "idle", finalText: latest.text, attachments: latest.attachments });
      }
      if (type === "session.status") return emitForSession({ kind: "status", sessionId, agent: activeAgent, status: clean(p.status?.type || p.status || "working", 40) });
      if (type === "global.disposed" && process.env.BEEFORGE_PLUGIN_SELF_TEST === "1") stopped = true;
      // OpenCode may emit global.disposed while replacing an internal client or
      // workspace context. The plugin process itself owns this polling loop, so
      // process termination is the reliable lifecycle boundary. Stopping here
      // prevented automatic reconnection after a bridge restart.
    },
  };
};
