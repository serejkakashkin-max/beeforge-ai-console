import http from "node:http";
import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { spawn, spawnSync } from "node:child_process";

const args = Object.fromEntries(process.argv.slice(2).reduce((a, v, i, all) => {
  if (v.startsWith("--")) a.push([v.slice(2), all[i + 1]]);
  return a;
}, []));
for (const name of ["config", "token-file", "key-file", "status", "pid", "log"]) {
  if (!args[name]) throw new Error(`Missing --${name}`);
}

// PowerShell's UTF-8 output can include a BOM. JSON.parse rejects that
// otherwise-valid leading U+FEFF, so normalize it at the common read seam.
const readJson = (file) => JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));
const config = readJson(args.config);
const bridgeKey = fs.readFileSync(args["key-file"], "utf8").trim();
let telegramToken = "";
if (args["token-stdin"] === "true") {
  telegramToken = fs.readFileSync(0, "utf8").trim();
} else {
  const secretReader = path.join(path.dirname(decodeURIComponent(new URL(import.meta.url).pathname).replace(/^\/(.:)/, "$1")), "read-secret.ps1");
  const powerShellExe = path.join(process.env.WINDIR || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const secret = spawnSync(powerShellExe, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", secretReader, "-Path", args["token-file"]], { encoding: "utf8", windowsHide: true });
  const secretOutput = String(secret.stdout || "").trim();
  if (secret.error || secret.status !== 0 || !secretOutput) throw new Error(`Cannot decrypt Telegram token: ${String(secret.error?.message || secret.stderr || `exit ${secret.status}`).trim()}`);
  telegramToken = secretOutput;
  secret.stdout = "";
}
if (!telegramToken) throw new Error("Telegram token input is empty");

const instances = new Map();
const sessions = new Map();
const commands = new Map();
const callbacks = new Map();
const pendingQuestions = new Map();
const openRequests = new Map();
const recentNotifications = new Map();
const deliveredProgress = new Map();
const deliveredFinals = new Map();
const deliveredFiles = new Map();
const pendingMainProgress = new Map();
const pendingCommands = new Map();
const pendingMediaGroups = new Map();
const queuedPrompts = [];
const scheduledTasks = [];
let selectedInstance = null;
let selectedSession = null;
let selectedDirectory = null;
let pendingNewSessionInstance = null;
let pendingProjectCreation = null;
let telegramOffset = 0;
let muted = Boolean(config.muted);
let stopping = false;
let modelStartProcess = null;
let modelWaitInProgress = false;
let modelWaitEpoch = 0;
let pinnedMessageId = null;
let pinnedUpdateTimer = null;
let pinnedUpdateInFlight = false;
let voiceServiceProcess = null;
const bridgeStatePath = path.join(path.dirname(args.status), "bridge-state.json");
const modelStatusPath = path.join(path.dirname(args.status), "model-start.status.json");
const fullAccessStatePath = path.resolve(path.dirname(args.status), "..", "access", "full-access.json");
const remoteAccessStatePath = path.join(path.dirname(args.config), "remote-access.json");
const remoteLeaseMessage = "🔒 Модель сейчас передана ноутбуку. Выключите удалённый доступ в BeeForge на основном ПК, чтобы снова отправлять локальные задачи.";

function localModelLeased() {
  try {
    const state = readJson(remoteAccessStatePath);
    return state?.Enabled === true && state?.Managed === true;
  } catch { return false; }
}

try {
  const saved = readJson(bridgeStatePath);
  selectedInstance = cleanText(saved.selectedInstance || "", 100) || null;
  selectedSession = cleanText(saved.selectedSession || "", 160) || null;
  selectedDirectory = cleanText(saved.selectedDirectory || "", 1000) || null;
  if (saved.pendingProjectCreation?.kind && Number(saved.pendingProjectCreation.createdAt || 0) > Date.now() - 30 * 60 * 1000) {
    pendingProjectCreation = saved.pendingProjectCreation;
  }
  telegramOffset = Math.max(0, Number(saved.telegramOffset || 0));
  if (typeof saved.muted === "boolean") muted = saved.muted;
  pinnedMessageId = Number(saved.pinnedMessageId || 0) || null;
  for (const item of Array.isArray(saved.queuedPrompts) ? saved.queuedPrompts : []) {
    if (item?.instanceId && item?.sessionId && item?.prompt && Number(item.createdAt || 0) > Date.now() - 24 * 60 * 60 * 1000) queuedPrompts.push(item);
  }
  for (const item of Array.isArray(saved.scheduledTasks) ? saved.scheduledTasks : []) {
    if (item?.id && item?.directory && item?.prompt && item?.schedule) scheduledTasks.push(item);
  }
  const now = Date.now();
  for (const row of Array.isArray(saved.callbacks) ? saved.callbacks : []) {
    if (!row?.token || !row?.item || Number(row.item.expiresAt || 0) <= now) continue;
    callbacks.set(String(row.token), { ...row.item, used: false });
  }
  for (const row of Array.isArray(saved.pendingQuestions) ? saved.pendingQuestions : []) {
    if (row?.key && row?.item) pendingQuestions.set(String(row.key), row.item);
  }
  for (const row of Array.isArray(saved.openRequests) ? saved.openRequests : []) {
    if (row?.key && row?.token && callbacks.has(String(row.token))) openRequests.set(String(row.key), String(row.token));
  }
} catch {}

function saveBridgeState() {
  const now = Date.now();
  const savedCallbacks = [...callbacks.entries()]
    .filter(([, item]) => Number(item.expiresAt || 0) > now)
    .map(([token, item]) => ({ token, item: { ...item, used: false } }));
  writeAtomic(bridgeStatePath, {
    selectedInstance, selectedSession, selectedDirectory, telegramOffset, muted, pendingProjectCreation, pinnedMessageId,
    queuedPrompts: queuedPrompts.slice(-100), scheduledTasks: scheduledTasks.slice(-100),
    callbacks: savedCallbacks,
    pendingQuestions: [...pendingQuestions.entries()].map(([key, item]) => ({ key, item })),
    openRequests: [...openRequests.entries()].map(([key, token]) => ({ key, token })),
    updatedAt: new Date().toISOString(),
  });
}

function pruneInstances(maxAgeMs = 90000) {
  const cutoff = Date.now() - maxAgeMs;
  for (const [id, instance] of instances) {
    if (instance.lastSeen >= cutoff) continue;
    instances.delete(id);
    audit("instance_expired", { instanceId: id, directory: instance.directory });
    commands.delete(id);
  }
}

function pruneTransientState() {
  const now = Date.now();
  for (const [token, item] of callbacks) if (item.expiresAt < now) callbacks.delete(token);
  for (const [key, token] of openRequests) {
    const item = callbacks.get(token);
    if (!item || item.used || Number(item.expiresAt || 0) <= now) openRequests.delete(key);
  }
  for (const [key, item] of pendingQuestions) if (now - Number(item.createdAt || now) > 30 * 60 * 1000) pendingQuestions.delete(key);
  if (pendingProjectCreation && now - Number(pendingProjectCreation.createdAt || now) > 30 * 60 * 1000) pendingProjectCreation = null;
  for (let index = queuedPrompts.length - 1; index >= 0; index -= 1) {
    if (now - Number(queuedPrompts[index].createdAt || now) > 24 * 60 * 60 * 1000) queuedPrompts.splice(index, 1);
  }
  saveBridgeState();
}

function writeAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(value, null, 2), "utf8");
  let lastError;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    try {
      fs.renameSync(temp, file);
      return;
    } catch (error) {
      lastError = error;
      if (attempt < 3) Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 25 * (attempt + 1));
    }
  }
  try { fs.unlinkSync(temp); } catch {}
  throw lastError;
}

function setStatus(state, message) {
  writeAtomic(args.status, { state, message, pid: process.pid, updatedAt: new Date().toISOString(), instances: instances.size });
}

function writePid() {
  fs.mkdirSync(path.dirname(args.pid), { recursive: true });
  fs.writeFileSync(args.pid, String(process.pid), "ascii");
}

function clearOwnPid() {
  try {
    if (fs.readFileSync(args.pid, "ascii").trim() === String(process.pid)) fs.unlinkSync(args.pid);
  } catch {}
}

function cleanText(value, max = 1200) {
  let text = String(value ?? "")
    .replace(/\b\d{5,}:[A-Za-z0-9_-]{20,}\b/g, "[REDACTED_TOKEN]")
    .replace(/\bBearer\s+[A-Za-z0-9._~+\/-]+=*/gi, "Bearer [REDACTED]")
    .replace(/\b(AKIA|ASIA)[A-Z0-9]{16}\b/g, "[REDACTED_AWS_KEY]")
    .replace(/((?:api[_-]?key|token|password|secret|authorization)\s*[:=]\s*)[^\s,;]+/gi, "$1[REDACTED]")
    .replace(/-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g, "[REDACTED_PRIVATE_KEY]")
    .replace(/(?:^|[\\/])\.env(?:\.[^\s\\/]*)?/gi, "[REDACTED_ENV]")
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, "")
    .trim();
  if (text.length > max) text = `${text.slice(0, max)}…`;
  return text;
}

function audit(kind, fields = {}) {
  const safe = {};
  for (const [key, value] of Object.entries(fields)) safe[key] = cleanText(value, 500);
  fs.mkdirSync(path.dirname(args.log), { recursive: true });
  try {
    if (fs.statSync(args.log).size >= 5 * 1024 * 1024) {
      const previous = `${args.log}.1`;
      try { fs.unlinkSync(previous); } catch {}
      fs.renameSync(args.log, previous);
    }
  } catch {}
  fs.appendFileSync(args.log, `${JSON.stringify({ at: new Date().toISOString(), kind, ...safe })}\n`, "utf8");
}

function canonical(value) {
  return path.win32.resolve(String(value || "")).replace(/[\\/]+$/, "").toLowerCase();
}

function mimeFromFilename(filename, fallback = "application/octet-stream") {
  const extension = path.win32.extname(String(filename || "")).toLowerCase();
  return ({
    ".txt": "text/plain", ".md": "text/markdown", ".html": "text/html", ".htm": "text/html", ".css": "text/css",
    ".js": "text/javascript", ".mjs": "text/javascript", ".cjs": "text/javascript", ".ts": "text/typescript", ".tsx": "text/tsx",
    ".json": "application/json", ".csv": "text/csv", ".xml": "application/xml", ".yaml": "application/yaml", ".yml": "application/yaml",
    ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".webp": "image/webp", ".gif": "image/gif", ".bmp": "image/bmp", ".svg": "image/svg+xml",
    ".pdf": "application/pdf", ".zip": "application/zip", ".7z": "application/x-7z-compressed", ".rar": "application/vnd.rar",
    ".mp3": "audio/mpeg", ".m4a": "audio/mp4", ".ogg": "audio/ogg", ".wav": "audio/wav", ".mp4": "video/mp4", ".webm": "video/webm",
  })[extension] || fallback;
}

function safeFilename(value, fallback = "attachment.bin") {
  let filename = path.win32.basename(String(value || "")).replace(/[<>:"/\\|?*\u0000-\u001F]/g, "_").replace(/[. ]+$/g, "").trim();
  if (!filename || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i.test(filename)) filename = fallback;
  if (filename.length > 140) {
    const extension = path.win32.extname(filename).slice(0, 20);
    filename = `${path.win32.basename(filename, extension).slice(0, 140 - extension.length)}${extension}`;
  }
  return filename;
}

function telegramAttachmentFromMessage(message) {
  if (message.document?.file_id) return { fileId: message.document.file_id, filename: safeFilename(message.document.file_name, `document-${message.message_id}.bin`), mime: message.document.mime_type || mimeFromFilename(message.document.file_name), size: Number(message.document.file_size || 0), kind: "document" };
  if (Array.isArray(message.photo) && message.photo.length) {
    const photo = [...message.photo].sort((a, b) => Number(a.file_size || 0) - Number(b.file_size || 0)).at(-1);
    return { fileId: photo.file_id, filename: `photo-${message.message_id}.jpg`, mime: "image/jpeg", size: Number(photo.file_size || 0), kind: "photo" };
  }
  for (const [kind, fallbackExtension] of [["animation", ".mp4"], ["video", ".mp4"], ["audio", ".mp3"], ["voice", ".ogg"], ["video_note", ".mp4"], ["sticker", ".webp"]]) {
    const item = message[kind];
    if (!item?.file_id) continue;
    const fallback = `${kind.replace("_", "-")}-${message.message_id}${fallbackExtension}`;
    return { fileId: item.file_id, filename: safeFilename(item.file_name, fallback), mime: item.mime_type || mimeFromFilename(item.file_name || fallback), size: Number(item.file_size || 0), kind };
  }
  return null;
}

function resolveProjectFile(directory, requestedPath) {
  const root = fs.realpathSync.native(path.win32.resolve(directory));
  const raw = String(requestedPath || "").trim().replace(/^`|`$/g, "").replace(/^"|"$/g, "");
  if (!raw) throw new Error("Не указан путь к файлу.");
  const candidate = path.win32.isAbsolute(raw) ? path.win32.resolve(raw) : path.win32.resolve(root, raw);
  if (!fs.existsSync(candidate)) throw new Error(`Файл не найден: ${raw}`);
  const resolved = fs.realpathSync.native(candidate);
  const relative = path.win32.relative(root, resolved);
  if (!relative || relative.startsWith(`..${path.win32.sep}`) || relative === ".." || path.win32.isAbsolute(relative)) throw new Error("Отправка разрешена только из выбранного проекта.");
  const stat = fs.statSync(resolved);
  if (!stat.isFile()) throw new Error("Можно отправлять только обычные файлы.");
  if (stat.size > 50 * 1024 * 1024) throw new Error("Telegram принимает исходящие файлы размером не более 50 МБ.");
  if (/(^|[\\/])(?:\.env(?:\.|$)|\.git(?:[\\/]|$)|secrets?(?:[\\/]|$)|id_(?:rsa|ed25519)(?:\.|$)|credentials?\.json$)|\.(?:pem|pfx|p12|key)$/i.test(relative)) throw new Error("Этот файл похож на секрет или служебный файл и не может быть отправлен автоматически.");
  return { path: resolved, relative, stat, mime: mimeFromFilename(resolved) };
}

function isAllowedProject(directory) {
  const candidate = canonical(directory);
  if ((config.allowedProjects || []).some((item) => canonical(item) === candidate)) return true;
  if (config.allowPreviouslyOpenedProjects !== true) return false;
  const resolved = path.win32.resolve(directory || "");
  const driveRoot = canonical(path.win32.parse(resolved).root);
  const profileRoot = canonical(process.env.USERPROFILE || "");
  return Boolean(candidate && candidate !== driveRoot && (!profileRoot || candidate !== profileRoot));
}

function persistAllowedProject(directory) {
  const resolved = path.win32.resolve(directory);
  const existing = Array.isArray(config.allowedProjects) ? config.allowedProjects : [];
  if (!existing.some((item) => canonical(item) === canonical(resolved))) {
    config.allowedProjects = [...existing, resolved];
    writeAtomic(args.config, config);
  }
  return resolved;
}

function validateProjectName(value) {
  const name = String(value || "").trim();
  if (!name) throw new Error("Укажите имя проекта: /create ИмяПроекта");
  if (name === "." || name === ".." || /[\\/:*?"<>|]/.test(name) || /[. ]$/.test(name)) throw new Error("Имя проекта содержит недопустимые символы.");
  if (/^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?$/i.test(name)) throw new Error("Это имя зарезервировано Windows.");
  return name;
}

function validateExplicitProjectPath(value) {
  const raw = String(value || "").trim().replace(/^"|"$/g, "");
  if (!/^[A-Za-z]:[\\/]/.test(raw)) throw new Error("Для /createat укажите полный путь, например C:\\Projects\\NewApp");
  const resolved = path.win32.resolve(raw);
  const root = path.win32.parse(resolved).root;
  if (canonical(resolved) === canonical(root)) throw new Error("Нельзя использовать корень диска как папку проекта.");
  if (/^c:\\(?:windows|program files(?: \(x86\))?|programdata)(?:\\|$)/i.test(resolved)) throw new Error("Системная папка не может быть папкой проекта.");
  validateProjectName(path.win32.basename(resolved));
  return resolved;
}

function ensureOpenCodeProjectRegistered(directory, makeCurrent = true) {
  const resolved = path.win32.resolve(directory);
  const dataFile = process.env.BEEFORGE_OPENCODE_GLOBAL_DATA
    || path.join(process.env.APPDATA || "", "ai.opencode.desktop", "opencode.global.dat");
  if (!dataFile || !fs.existsSync(dataFile)) return { updated: false, available: false };
  try {
    const outer = readJson(dataFile);
    const serverWasString = typeof outer.server === "string";
    const server = serverWasString ? JSON.parse(outer.server || "{}") : (outer.server || {});
    server.projects ||= {};
    const localProjects = Array.isArray(server.projects.local) ? server.projects.local : [];
    const existing = localProjects.find((item) => canonical(item?.worktree) === canonical(resolved));
    server.projects.local = [
      { ...(existing || {}), worktree: resolved, expanded: existing?.expanded !== false },
      ...localProjects.filter((item) => canonical(item?.worktree) !== canonical(resolved)),
    ];
    if (makeCurrent) server.lastProject = { ...(server.lastProject || {}), local: resolved };
    outer.server = serverWasString ? JSON.stringify(server) : server;
    const backup = `${dataFile}.beeforge-backup`;
    if (!fs.existsSync(backup)) fs.copyFileSync(dataFile, backup);
    writeAtomic(dataFile, outer);
    audit("opencode_project_registered", { directory: resolved, dataFile, existed: Boolean(existing) });
    return { updated: true, available: true };
  } catch (error) {
    audit("opencode_project_registration_failed", { directory: resolved, dataFile, error: error.message });
    return { updated: false, available: true, error: cleanText(error.message, 500) };
  }
}

function launchOpenCode(directory) {
  const resolved = path.win32.resolve(directory);
  const deepLink = new URL("opencode://open-project");
  deepLink.searchParams.set("directory", resolved);
  const registration = ensureOpenCodeProjectRegistered(resolved);
  if (process.env.BEEFORGE_BRIDGE_SELF_TEST === "1") {
    audit("opencode_launch", { directory: resolved, deepLink: deepLink.toString(), registered: registration.updated, selfTest: true });
    return true;
  }
  const executable = path.join(process.env.LOCALAPPDATA || "", "Programs", "@opencode-aidesktop", "OpenCode.exe");
  if (!fs.existsSync(executable)) return false;
  const child = spawn(executable, [], { detached: true, stdio: "ignore", windowsHide: false });
  child.unref();
  const deliver = (delayMs) => {
    const timer = setTimeout(() => {
      try {
        const deepLinkProcess = spawn(executable, [deepLink.toString()], { detached: true, stdio: "ignore", windowsHide: false });
        deepLinkProcess.unref();
        audit("opencode_deep_link_delivered", { directory: resolved, deepLink: deepLink.toString(), delayMs });
      } catch (error) { audit("opencode_deep_link_failed", { directory: resolved, delayMs, error: error.message }); }
    }, delayMs);
    timer.unref();
  };
  deliver(1200);
  deliver(7000);
  audit("opencode_launch", { directory: resolved, deepLink: deepLink.toString(), registered: registration.updated });
  return true;
}

function readModelStatus() {
  const powerShellExe = path.join(process.env.WINDIR || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const manager = "C:\\AI\\BeeForge AI Console\\scripts\\server-manager.ps1";
  const result = spawnSync(powerShellExe, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", manager, "-Action", "Status"], { encoding: "utf8", windowsHide: true, timeout: 15000 });
  if (result.error || result.status !== 0) throw new Error(cleanText(result.error?.message || result.stderr || "Не удалось получить состояние модели", 900));
  return JSON.parse(String(result.stdout || "{}"));
}

function readFullAccessStatus() {
  try {
    const state = readJson(fullAccessStatePath);
    return { enabled: Boolean(state.enabled) && !Boolean(state.pending), pending: Boolean(state.pending), enabledAt: cleanText(state.enabledAt || "", 80) };
  } catch { return { enabled: false, pending: false, enabledAt: "" }; }
}

function runFullAccessAction(enabled, userId) {
  if (process.env.BEEFORGE_BRIDGE_SELF_TEST === "1") {
    return { Enabled: Boolean(enabled), Configured: Boolean(enabled), Inconsistent: false, Source: `Telegram user ${userId}` };
  }
  const powerShellExe = path.join(process.env.WINDIR || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const helper = "C:\\AI\\BeeForge AI Console\\scripts\\Set-BeeFullAccess.ps1";
  const action = enabled ? "Enable" : "Disable";
  const result = spawnSync(powerShellExe, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "-Action", action, "-Source", `Telegram user ${userId}`], { encoding: "utf8", windowsHide: true, timeout: 30000 });
  const output = String(result.stdout || "").trim();
  if (result.error || result.status !== 0) throw new Error(cleanText(result.error?.message || result.stderr || output || `Команда завершилась с кодом ${result.status}`, 1800));
  const lines = output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (!lines.length) throw new Error("Скрипт режима доступа не вернул состояние.");
  try { return JSON.parse(lines.at(-1).replace(/^\uFEFF/, "")); }
  catch { throw new Error(`Некорректный ответ режима доступа: ${cleanText(output, 1200)}`); }
}

async function executeFullAccessAction(enabled, userId) {
  try {
    const result = runFullAccessAction(enabled, userId);
    audit("full_access", { enabled, userId, succeeded: true });
    schedulePinnedStatus(50);
    await send(enabled
      ? "🟠 Полный доступ ВКЛЮЧЁН. Исполняющие агенты OpenCode могут работать с файлами, shell, интернетом, MCP и skills без системных запросов. Team Lead остаётся координатором и может только делегировать настроенным агентам. Для уже открытой сессии может потребоваться новая сессия."
      : "🟢 Полный доступ выключен. Обычные правила и запросы разрешений восстановлены.", mainMenuKeyboard());
    return result;
  } catch (error) {
    audit("full_access", { enabled, userId, succeeded: false, error: error.message });
    await send(`❌ Не удалось ${enabled ? "включить" : "выключить"} полный доступ\n${cleanText(error.message, 1800)}`, mainMenuKeyboard());
    return null;
  }
}

async function requestFullAccessEnable() {
  const token = newCallback({ kind: "full_access_first" }, 2 * 60 * 1000);
  await send("⚠️ Полный доступ отключает системные запросы разрешения для файлов, shell, интернета и MCP. Агент сможет выполнять команды на компьютере с правами текущего пользователя.\n\nНажмите «Продолжить», затем подтвердите действие ещё раз.", { inline_keyboard: [[
    { text: "Продолжить", callback_data: `bf:${token}:confirm` },
    { text: "Отмена", callback_data: `bf:${token}:cancel` },
  ]] });
}

async function showFullAccess() {
  const status = readFullAccessStatus();
  if (status.enabled) {
    const token = newCallback({ kind: "full_access_disable" }, 2 * 60 * 1000);
    return send(`🟠 Полный доступ: ВКЛЮЧЁН${status.enabledAt ? `\nС: ${status.enabledAt}` : ""}\n\nМожно безопасно вернуть обычные запросы разрешений.`, { inline_keyboard: [[{ text: "🛡 Вернуть обычный режим", callback_data: `bf:${token}:disable` }]] });
  }
  const token = newCallback({ kind: "full_access_menu" }, 2 * 60 * 1000);
  return send("🟢 Полный доступ: выключен. Действуют обычные запросы разрешений.", { inline_keyboard: [[{ text: "🟠 Включить полный доступ", callback_data: `bf:${token}:enable` }]] });
}

function launchBeeForgeConsole() {
  if (process.env.BEEFORGE_BRIDGE_SELF_TEST === "1") return { Started: true, Running: true, Pid: 1, Message: "self-test" };
  const powerShellExe = path.join(process.env.WINDIR || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const launcher = "C:\\AI\\BeeForge AI Console\\scripts\\Start-BeeForgeConsole.ps1";
  const result = spawnSync(powerShellExe, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", launcher], { encoding: "utf8", windowsHide: true, timeout: 15000 });
  if (result.error || result.status !== 0) throw new Error(cleanText(result.error?.message || result.stderr || "Не удалось запустить BeeForge AI Console", 1200));
  return JSON.parse(String(result.stdout || "{}"));
}

async function startConsole() {
  try {
    const result = launchBeeForgeConsole();
    audit("console_launch", { started: result.Started, pid: result.Pid || "" });
    await send(`${result.Started ? "✅" : "ℹ️"} ${result.Message || "BeeForge AI Console работает"}\nPID: ${result.Pid || "—"}`);
  } catch (error) { await send(`❌ Не удалось запустить BeeForge AI Console\n${cleanText(error.message, 1600)}`); }
}

const lifecycleActions = {
  model: { helper: "Model", title: "выгрузить локальную модель", button: "⏹ Выгрузить модель" },
  console: { helper: "Console", title: "закрыть BeeForge AI Console", button: "✖ Закрыть BeeForge" },
  opencode: { helper: "OpenCode", title: "закрыть OpenCode", button: "✖ Закрыть OpenCode" },
  all: { helper: "All", title: "выгрузить модель и закрыть OpenCode/BeeForge Console", button: "⏻ Завершить всё" },
};

function runLifecycleAction(target) {
  const action = lifecycleActions[target];
  if (!action) throw new Error("Неизвестное действие завершения.");
  if (process.env.BEEFORGE_BRIDGE_SELF_TEST === "1") {
    return { Succeeded: true, Action: action.helper, Results: [{ Target: target, Succeeded: true, Message: `self-test ${target}`, Matched: 1, Forced: 0 }] };
  }
  const powerShellExe = path.join(process.env.WINDIR || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  const helper = "C:\\AI\\BeeForge AI Console\\scripts\\Stop-BeeForgeApps.ps1";
  const result = spawnSync(powerShellExe, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "-Action", action.helper], { encoding: "utf8", windowsHide: true, timeout: 45000 });
  const output = String(result.stdout || "").trim();
  if (result.error) throw new Error(cleanText(result.error.message, 1800));
  const lines = output.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (lines.length) {
    try { return JSON.parse(lines.at(-1)); }
    catch {}
  }
  if (result.status !== 0 || !output) throw new Error(cleanText(result.stderr || output || `Команда завершилась с кодом ${result.status}`, 1800));
  throw new Error(`Некорректный ответ управляющего скрипта: ${cleanText(output, 1200)}`);
}

async function requestLifecycleAction(target) {
  const action = lifecycleActions[target];
  if (!action) return send("❌ Неизвестное действие завершения.");
  const token = newCallback({ kind: "lifecycle", target }, 2 * 60 * 1000);
  const note = target === "model"
    ? "OpenCode и BeeForge Console останутся открыты."
    : target === "console"
      ? "Telegram-мост и модель продолжат работать."
      : target === "opencode"
        ? "Telegram-мост, BeeForge Console и модель продолжат работать."
        : "Telegram-мост останется работать, поэтому всё можно будет снова запустить из бота.";
  await send(`⚠️ Подтвердите действие\n\n${action.title}.\n${note}\n\nПодтверждение действует 2 минуты.`, {
    inline_keyboard: [[
      { text: `✅ Да, ${action.title}`, callback_data: `bf:${token}:confirm` },
      { text: "Отмена", callback_data: `bf:${token}:cancel` },
    ]],
  });
}

async function executeLifecycleAction(target, userId) {
  const action = lifecycleActions[target];
  try {
    if ((target === "model" || target === "all") && modelStartProcess) {
      try {
        modelStartProcess.removeAllListeners("error");
        modelStartProcess.removeAllListeners("close");
        modelStartProcess.kill();
      } catch {}
      modelStartProcess = null;
    }
    if (target === "model" || target === "all") { modelWaitEpoch += 1; modelWaitInProgress = false; }
    const result = runLifecycleAction(target);
    const rows = Array.isArray(result.Results) ? result.Results : [];
    const details = rows.length
      ? rows.map((row) => `${row.Succeeded ? "✅" : "❌"} ${cleanText(row.Message || row.Target, 700)}${Number(row.Forced || 0) > 0 ? ` (принудительно завершено: ${row.Forced})` : ""}`).join("\n")
      : cleanText(result.Error || "Нет подробностей.", 1200);
    audit("lifecycle_action", { target, userId, succeeded: Boolean(result.Succeeded), results: rows.map((row) => ({ target: row.Target, succeeded: row.Succeeded, matched: row.Matched, forced: row.Forced })) });
    await send(`${result.Succeeded ? "✅" : "❌"} ${action.title}\n\n${details}\n\nTelegram-мост продолжает работать.`, mainMenuKeyboard());
  } catch (error) {
    audit("lifecycle_action_failed", { target, userId, error: error.message });
    await send(`❌ Не удалось выполнить действие\n${cleanText(error.message, 1800)}\n\nTelegram-мост продолжает работать.`, mainMenuKeyboard());
  }
}

function formatModelStatus(status) {
  return `Модель: ${status.Profile || "не выбрана"}\nСостояние: ${status.Ready ? "READY" : status.Running ? "LOADING" : "STOPPED"}\nPID: ${status.Pid || "—"}\nКонтекст: ${status.Context || "—"}\nVRAM: ${status.VramUsedMiB ?? "—"}/${status.VramTotalMiB ?? "—"} MiB`;
}

async function showModelStatus() {
  try { await send(`🤖 BeeLlama\n${formatModelStatus(readModelStatus())}`); }
  catch (error) { await send(`❌ Не удалось прочитать состояние модели\n${cleanText(error.message, 1200)}`); }
}

async function waitForModelReady(directory, source = "existing") {
  if (modelWaitInProgress) return send("⏳ Модель уже загружается. Я сообщу, когда она станет READY.");
  modelWaitInProgress = true;
  const epoch = ++modelWaitEpoch;
  try {
    for (let attempt = 0; attempt < 120; attempt += 1) {
      await new Promise((resolve) => setTimeout(resolve, 2000));
      if (epoch !== modelWaitEpoch) return;
      const state = readModelStatus();
      if (state.Ready) {
        const opened = directory ? launchOpenCode(directory) : false;
        audit("model_ready", { profile: state.Profile || "", pid: state.Pid || "", directory, opened, source });
        await send(`✅ Последняя активная модель READY\n${formatModelStatus(state)}${directory ? `\n\n${opened ? "OpenCode открыт с выбранным проектом." : "Модель готова, но OpenCode.exe не найден."}` : ""}`);
        return;
      }
      if (!state.Running) throw new Error("Сервер модели остановился до READY.");
    }
    throw new Error("Модель не стала READY за 240 секунд.");
  } catch (error) {
    audit("model_wait_failed", { error: error.message, directory, source });
    await send(`❌ Ошибка ожидания модели\n${cleanText(error.message, 1600)}`);
  } finally { if (epoch === modelWaitEpoch) modelWaitInProgress = false; }
}

async function startLastModel(openCodeDirectory = "", requestedProfileId = "") {
  const leased = localModelLeased();
  const directory = leased ? "" : (openCodeDirectory ? path.win32.resolve(openCodeDirectory) : "");
  if (process.env.BEEFORGE_BRIDGE_SELF_TEST === "1") return send(`✅ Тестовый запуск последней модели${directory ? " и OpenCode" : ""}.`);
  if (modelStartProcess) return send("⏳ Модель уже запускается. Я сообщу, когда она станет READY.");
  try {
    const consoleState = launchBeeForgeConsole();
    audit("console_launch", { started: consoleState.Started, pid: consoleState.Pid || "", source: "model_launch" });
    const current = readModelStatus();
    const selectedProfile = requestedProfileId ? readProfiles().profiles.find((item) => item.id === requestedProfileId) : null;
    const sameReadyProfile = current.Ready && (!selectedProfile || current.Profile === selectedProfile.name);
    if (sameReadyProfile) {
      const opened = directory ? launchOpenCode(directory) : false;
      return send(`✅ Модель уже готова\n${formatModelStatus(current)}${directory ? `\n\n${opened ? "OpenCode открыт с выбранным проектом." : "Не удалось найти OpenCode.exe."}` : ""}`);
    }
    if (current.Running && !requestedProfileId) {
      await send(`⏳ Модель уже загружается\n${current.Profile || "Профиль BeeForge"}\nЖду READY${directory ? " и затем открою OpenCode." : "."}`);
      void waitForModelReady(directory);
      return;
    }
    const powerShellExe = path.join(process.env.WINDIR || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
    const worker = "C:\\AI\\BeeForge AI Console\\scripts\\Start-BeeLastModel.ps1";
    const workerArgs = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", worker, "-StatusPath", modelStatusPath];
    if (requestedProfileId) workerArgs.push("-ProfileId", requestedProfileId);
    const child = spawn(powerShellExe, workerArgs, { windowsHide: true, stdio: "ignore" });
    modelStartProcess = child;
    audit("model_start_requested", { directory, pid: child.pid || "" });
    await send(`⏳ Запускаю модель BeeForge\n${selectedProfile?.name || current.Profile || "Последний успешный профиль"}\nПараметры будут взяты из сохранённого профиля.${directory ? " После READY автоматически открою OpenCode с выбранным проектом." : ""}`);
    child.once("error", async (error) => {
      modelStartProcess = null;
      audit("model_start_error", { error: error.message });
      await send(`❌ Не удалось запустить модель\n${cleanText(error.message, 1600)}`);
    });
    child.once("close", async (code) => {
      modelStartProcess = null;
      let state = null;
      try { state = readJson(modelStatusPath); } catch {}
      if (code === 0 && state?.ready) {
        const opened = directory ? launchOpenCode(directory) : false;
        audit("model_ready", { profile: state.profile || "", pid: state.pid || "", directory, opened });
        await send(`✅ Последняя активная модель READY\nПрофиль: ${state.profile || "BeeForge"}\nPID: ${state.pid || "—"}${directory ? `\n${opened ? "OpenCode открыт с выбранным проектом." : "Модель готова, но OpenCode.exe не найден."}` : ""}`);
      } else {
        audit("model_start_failed", { code, error: state?.message || "" });
        await send(`❌ Модель не запустилась\n${cleanText(state?.message || `Процесс завершился с кодом ${code}`, 2200)}`);
      }
    });
  } catch (error) { await send(`❌ Не удалось начать запуск модели\n${cleanText(error.message, 1600)}`); }
}

function projectActionKeyboard(directory) {
  const launch = newCallback({ kind: "project_action", directory });
  const open = newCallback({ kind: "project_action", directory });
  return { inline_keyboard: [[
    { text: "🚀 BeeForge → OpenCode", callback_data: `bf:${launch}:launch` },
    { text: "📂 Только OpenCode", callback_data: `bf:${open}:open` },
  ]] };
}

async function createProject(directory) {
  const resolved = path.win32.resolve(directory);
  const parent = path.win32.dirname(resolved);
  if (!fs.existsSync(parent) || !fs.statSync(parent).isDirectory()) throw new Error(`Родительская папка не существует: ${parent}`);
  let created = false;
  if (fs.existsSync(resolved)) {
    if (!fs.statSync(resolved).isDirectory()) throw new Error("По указанному пути уже существует файл.");
  } else {
    fs.mkdirSync(resolved);
    created = true;
  }
  persistAllowedProject(resolved);
  ensureOpenCodeProjectRegistered(resolved);
  selectedDirectory = resolved;
  selectedInstance = null;
  selectedSession = null;
  pendingNewSessionInstance = null;
  pendingProjectCreation = null;
  saveBridgeState();
  audit("project_created", { directory: resolved, created });
  await send(`${created ? "✅ Папка проекта создана" : "✅ Существующая папка добавлена как проект"}\n${resolved}\n\nВыберите способ запуска:`, projectActionKeyboard(resolved));
}

function listProjectEntries(directory, requested = "") {
  const root = fs.realpathSync.native(path.win32.resolve(directory));
  const candidate = path.win32.resolve(root, String(requested || ""));
  if (!fs.existsSync(candidate)) throw new Error("Каталог не найден.");
  const resolved = fs.realpathSync.native(candidate);
  const relative = path.win32.relative(root, resolved);
  if (relative === ".." || relative.startsWith(`..${path.win32.sep}`) || path.win32.isAbsolute(relative)) throw new Error("Просмотр разрешён только внутри выбранного проекта.");
  if (!fs.statSync(resolved).isDirectory()) throw new Error("Указанный путь не является каталогом.");
  const entries = fs.readdirSync(resolved, { withFileTypes: true })
    .filter((item) => !/(^\.git$|^\.env(?:\.|$)|^secrets?$)/i.test(item.name))
    .map((item) => {
      const full = path.win32.join(resolved, item.name);
      let stat = null; try { stat = fs.statSync(full); } catch {}
      return { name: item.name, directory: item.isDirectory(), size: stat?.size || 0, relative: path.win32.relative(root, full) };
    })
    .sort((a, b) => Number(b.directory) - Number(a.directory) || a.name.localeCompare(b.name, "ru"));
  return { root, directory: resolved, relative, entries: entries.slice(0, 40), truncated: entries.length > 40 };
}

async function showFiles(requested = "") {
  const instance = currentInstance();
  if (!instance) return send("Нет подключённого разрешённого проекта OpenCode.");
  try {
    const listing = listProjectEntries(instance.directory, requested);
    const rows = [];
    if (listing.relative) {
      const parent = path.win32.dirname(listing.relative);
      const token = newCallback({ kind: "file_browser", instanceId: instance.id, relative: parent === "." ? "" : parent });
      rows.push([{ text: "⬆️ На уровень выше", callback_data: `bf:${token}:open` }]);
    }
    for (const entry of listing.entries) {
      const token = newCallback({ kind: "file_browser", instanceId: instance.id, relative: entry.relative });
      rows.push([{ text: `${entry.directory ? "📁" : "📄"} ${cleanText(entry.name, 44)}`, callback_data: `bf:${token}:${entry.directory ? "open" : "send"}` }]);
    }
    await send(`📂 ${instance.projectName}\\${listing.relative || ""}${listing.truncated ? "\nПоказаны первые 40 элементов." : ""}`, { inline_keyboard: rows });
  } catch (error) { await send(`❌ Не удалось открыть каталог\n${cleanText(error.message, 1200)}`); }
}

function readProfiles() {
  const profilePath = process.env.BEEFORGE_PROFILES_PATH || "C:\\AI\\BeeForge AI Console\\config\\profiles.json";
  const store = readJson(profilePath);
  return { ...store, profiles: Array.isArray(store.profiles) ? store.profiles.filter((item) => item?.id && item?.name) : [] };
}

async function showProfiles() {
  try {
    const store = readProfiles();
    const rows = store.profiles.slice(0, 20).map((profile) => {
      const token = newCallback({ kind: "profile", profileId: cleanText(profile.id, 100), profileName: cleanText(profile.name, 120) });
      const active = profile.id === store.lastGoodProfileId || profile.id === store.activeProfileId;
      return [{ text: `${active ? "✅ " : ""}${cleanText(profile.name, 44)}`, callback_data: `bf:${token}:select` }];
    });
    await send(rows.length ? "🤖 Выберите сохранённый профиль BeeForge. Смена уже работающей модели потребует отдельного подтверждения." : "В BeeForge нет сохранённых профилей.", rows.length ? { inline_keyboard: rows } : undefined);
  } catch (error) { await send(`❌ Не удалось прочитать профили BeeForge\n${cleanText(error.message, 1200)}`); }
}

const weekdayMap = new Map([
  ["sun", 0], ["sunday", 0], ["вс", 0], ["воскресенье", 0],
  ["mon", 1], ["monday", 1], ["пн", 1], ["понедельник", 1],
  ["tue", 2], ["tuesday", 2], ["вт", 2], ["вторник", 2],
  ["wed", 3], ["wednesday", 3], ["ср", 3], ["среда", 3],
  ["thu", 4], ["thursday", 4], ["чт", 4], ["четверг", 4],
  ["fri", 5], ["friday", 5], ["пт", 5], ["пятница", 5],
  ["sat", 6], ["saturday", 6], ["сб", 6], ["суббота", 6],
]);

function nextScheduledAt(schedule, from = new Date()) {
  const [hours, minutes] = String(schedule.time || "00:00").split(":").map(Number);
  if (schedule.kind === "once") return new Date(`${schedule.date}T${schedule.time}:00`);
  const next = new Date(from); next.setSeconds(0, 0); next.setHours(hours, minutes, 0, 0);
  if (schedule.kind === "daily") { if (next <= from) next.setDate(next.getDate() + 1); return next; }
  const difference = (Number(schedule.weekday) - next.getDay() + 7) % 7;
  next.setDate(next.getDate() + difference);
  if (next <= from) next.setDate(next.getDate() + 7);
  return next;
}

function parseTaskSpec(value) {
  const text = String(value || "").trim();
  let match = /^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2})\s+([\s\S]+)$/.exec(text);
  if (match) return { schedule: { kind: "once", date: match[1], time: match[2] }, prompt: match[3].trim() };
  match = /^(?:every|каждый|каждую)\s+([^\s]+)\s+(\d{2}:\d{2})\s+([\s\S]+)$/i.exec(text);
  if (match && weekdayMap.has(match[1].toLowerCase())) return { schedule: { kind: "weekly", weekday: weekdayMap.get(match[1].toLowerCase()), time: match[2] }, prompt: match[3].trim() };
  match = /^(\d{2}:\d{2})\s+([\s\S]+)$/.exec(text);
  if (match) return { schedule: { kind: "daily", time: match[1] }, prompt: match[2].trim() };
  throw new Error("Формат: /task 09:30 задача; /task 2026-09-01 09:30 задача; /task every monday 09:30 задача");
}

function scheduleLabel(task) {
  const schedule = task.schedule;
  if (schedule.kind === "once") return `${schedule.date} ${schedule.time}`;
  if (schedule.kind === "daily") return `ежедневно ${schedule.time}`;
  return `еженедельно, день ${schedule.weekday}, ${schedule.time}`;
}

async function showScheduledTasks() {
  if (!scheduledTasks.length) return send("Запланированных задач Team Lead нет.");
  const rows = scheduledTasks.slice(0, 20).map((task) => `${task.enabled === false ? "⏸" : "⏰"} ${task.id.slice(0, 8)} · ${path.win32.basename(task.directory)} · ${scheduleLabel(task)}\n${cleanText(task.prompt, 120)}`);
  await send(`Запланированные задачи:\n\n${rows.join("\n\n")}\n\nУдаление: /taskdel первые-8-символов-ID`);
}

async function runScheduledTasks() {
  const now = new Date();
  for (const task of scheduledTasks) {
    if (task.enabled === false) continue;
    const due = new Date(task.nextRunAt || nextScheduledAt(task.schedule, new Date(now.getTime() - 60000)).toISOString());
    if (!Number.isFinite(due.getTime()) || due > now) continue;
    if (localModelLeased()) {
      task.nextRunAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();
      audit("scheduled_task_postponed_remote_lease", { taskId: task.id, directory: task.directory });
      continue;
    }
    const instance = [...instances.values()].find((item) => canonical(item.directory) === canonical(task.directory));
    if (!instance) {
      launchOpenCode(task.directory);
      task.nextRunAt = new Date(Date.now() + 2 * 60 * 1000).toISOString();
      audit("scheduled_task_waiting_for_opencode", { taskId: task.id, directory: task.directory });
      continue;
    }
    const busy = [...sessions.values()].some((item) => item.instanceId === instance.id && !item.parentID && sessionIsBusy(item.id));
    if (busy) {
      task.nextRunAt = new Date(Date.now() + 5 * 60 * 1000).toISOString();
      audit("scheduled_task_postponed_busy", { taskId: task.id, directory: task.directory });
      continue;
    }
    queue(instance.id, { type: "new_session", prompt: task.prompt, agent: "team-lead", mode: modeFromText(task.prompt), scheduledTaskId: task.id });
    task.lastRunAt = now.toISOString();
    if (task.schedule.kind === "once") task.enabled = false;
    else task.nextRunAt = nextScheduledAt(task.schedule, new Date(now.getTime() + 60000)).toISOString();
    audit("scheduled_task_started", { taskId: task.id, directory: task.directory });
    await send(`⏰ Запускаю запланированную задачу Team Lead\nПроект: ${path.win32.basename(task.directory)}\n${cleanText(task.prompt, 1200)}`);
  }
  saveBridgeState();
}

const wait = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function telegram(method, body = {}) {
  let lastError;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    try {
      const response = await fetch(`https://api.telegram.org/bot${telegramToken}/${method}`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(method === "getUpdates" ? 35000 : 20000),
      });
      const result = await response.json();
      if (response.status === 429 || Number(result?.error_code) === 429) {
        const retrySeconds = Math.max(1, Math.min(30, Number(result?.parameters?.retry_after || 2)));
        audit("telegram_rate_limited", { method, attempt, retrySeconds });
        await wait(retrySeconds * 1000 + crypto.randomInt(100, 500));
        continue;
      }
      if (!response.ok || !result.ok) throw new Error(`Telegram ${method}: ${cleanText(result.description || response.statusText)}`);
      return result.result;
    } catch (error) {
      lastError = error;
      if (attempt >= 3 || /Bad Request|Forbidden|Unauthorized/i.test(String(error.message))) throw error;
      await wait(500 * (2 ** attempt) + crypto.randomInt(50, 250));
    }
  }
  throw lastError || new Error(`Telegram ${method} failed`);
}

async function send(text, replyMarkup) {
  const body = { chat_id: config.allowedChatId, text: cleanText(text, 3900), disable_web_page_preview: true };
  if (replyMarkup) body.reply_markup = replyMarkup;
  return telegram("sendMessage", body);
}

async function clearRecentTelegramChat(anchorMessageId) {
  // Telegram has no bot API method that clears a chat wholesale. In a private
  // chat, however, it permits deleting incoming and outgoing messages younger
  // than 48 hours, in deleteMessages batches of at most 100 IDs.
  const latest = Math.max(1, Number(anchorMessageId || 0));
  // Scan a broad ID range, not just the latest 500 IDs. The previous fixed
  // window repeated the same range on every click and could never reach older
  // but still deletable messages. Telegram safely skips missing/expired IDs.
  const ids = Array.from({ length: Math.min(5000, latest) }, (_unused, index) => latest - index);
  let attempted = 0;
  for (let index = 0; index < ids.length; index += 100) {
    const messageIds = ids.slice(index, index + 100);
    try {
      await telegram("deleteMessages", { chat_id: config.allowedChatId, message_ids: messageIds });
      attempted += messageIds.length;
    } catch (error) {
      audit("chat_clear_batch_failed", { start: messageIds.at(0), end: messageIds.at(-1), error: error.message });
    }
  }
  pinnedMessageId = null;
  pendingQuestions.clear();
  callbacks.clear();
  openRequests.clear();
  saveBridgeState();
  audit("chat_cleared", { attempted, anchorMessageId: latest });
  await send("🧹 Чат очищен. Нажмите /start, чтобы снова открыть меню.");
}

async function telegramUpload(method, field, filePath, mime, caption = "") {
  const data = fs.readFileSync(filePath);
  let lastError;
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const form = new FormData();
    form.set("chat_id", String(config.allowedChatId));
    form.set(field, new Blob([data], { type: mime || "application/octet-stream" }), path.win32.basename(filePath));
    if (caption) form.set("caption", cleanText(caption, 1000));
    try {
      const response = await fetch(`https://api.telegram.org/bot${telegramToken}/${method}`, { method: "POST", body: form, signal: AbortSignal.timeout(120000) });
      const result = await response.json();
      if (response.status === 429 || Number(result?.error_code) === 429) {
        const retrySeconds = Math.max(1, Math.min(30, Number(result?.parameters?.retry_after || 2)));
        audit("telegram_upload_rate_limited", { method, attempt, retrySeconds });
        await wait(retrySeconds * 1000 + crypto.randomInt(100, 500));
        continue;
      }
      if (!response.ok || !result.ok) throw new Error(`Telegram ${method}: ${cleanText(result.description || response.statusText)}`);
      return result.result;
    } catch (error) {
      lastError = error;
      if (attempt >= 3 || /Bad Request|Forbidden|Unauthorized/i.test(String(error.message))) throw error;
      await wait(750 * (2 ** attempt) + crypto.randomInt(50, 250));
    }
  }
  throw lastError || new Error(`Telegram ${method} upload failed`);
}

async function sendProjectFile(directory, requestedPath, caption = "") {
  const file = resolveProjectFile(directory, requestedPath);
  // Always use Telegram documents, including PNG/JPEG/WebP. The photo endpoint
  // may resize or recompress an image; document uploads preserve original bytes.
  await telegramUpload("sendDocument", "document", file.path, file.mime, caption || `Файл из прокта: ${file.relative}`);
  audit("telegram_file_sent", { directory, relative: file.relative, size: file.stat.size, mime: file.mime, method: "sendDocument" });
  return file;
}

async function downloadTelegramAttachment(message, instance, descriptor) {
  const maximum = 20 * 1024 * 1024;
  if (descriptor.size > maximum) throw new Error("Telegram Bot API позволяет скачать входящий файл размером не более 20 МБ.");
  const remote = await telegram("getFile", { file_id: descriptor.fileId });
  if (!remote?.file_path) throw new Error("Telegram не вернул путь к файлу.");
  const response = await fetch(`https://api.telegram.org/file/bot${telegramToken}/${remote.file_path}`, { signal: AbortSignal.timeout(120000) });
  if (!response.ok) throw new Error(`Не удалось скачать файл из Telegram: HTTP ${response.status}`);
  const declared = Number(response.headers.get("content-length") || 0);
  if (declared > maximum) throw new Error("Входящий файл превышает лимит 20 МБ.");
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length > maximum) throw new Error("Входящий файл превышает лимит 20 МБ.");
  const date = new Date().toISOString().slice(0, 10);
  const folder = path.win32.join(instance.directory, ".beeforge", "telegram", "inbox", date);
  fs.mkdirSync(folder, { recursive: true });
  const remoteExtension = path.posix.extname(remote.file_path || "");
  let filename = descriptor.filename;
  if (!path.win32.extname(filename) && remoteExtension) filename = `${filename}${remoteExtension}`;
  filename = safeFilename(filename);
  const target = path.win32.join(folder, `${message.message_id}-${crypto.randomBytes(4).toString("hex")}-${filename}`);
  fs.writeFileSync(target, bytes, { flag: "wx" });
  const relative = path.win32.relative(instance.directory, target);
  const attachment = { path: target, relative, filename, mime: descriptor.mime || mimeFromFilename(filename), size: bytes.length };
  audit("telegram_file_received", { directory: instance.directory, relative, size: bytes.length, mime: attachment.mime, kind: descriptor.kind });
  return attachment;
}

function attachmentPrompt(caption, attachments) {
  const paths = attachments.map((item) => `- ${item.relative} (${item.mime}, ${item.size} байт)`).join("\n");
  const request = cleanText(caption, 3000) || "Изучи присланное вложение и выполни задачу по его содержимому.";
  return `${request}\n\nВложения из Telegram сохранены внутри текущего проекта:\n${paths}\nИспользуй файловые части сообщения; если формат нельзя прочитать напрямую, работай с указанными локальными путями.`;
}

function voiceServiceSettings() {
  return { port: Number(config.voicePort || 47656), model: cleanText(config.voiceModel || "small", 80) };
}

async function voiceHealth() {
  if (config.voiceEnabled === false) return null;
  const { port } = voiceServiceSettings();
  try {
    const response = await fetch(`http://127.0.0.1:${port}/health`, { headers: { "x-beeforge-key": bridgeKey }, signal: AbortSignal.timeout(2500) });
    if (!response.ok) return null;
    return response.json();
  } catch { return null; }
}

async function ensureVoiceService() {
  const existing = await voiceHealth();
  if (existing) return existing;
  if (config.voiceEnabled === false) throw new Error("Голосовой ввод выключен в настройках BeeForge.");
  if (!voiceServiceProcess) {
    const root = "C:\\AI\\BeeForge AI Console";
    const script = path.win32.join(root, "scripts", "Run-BeeVoiceService.ps1");
    const powerShellExe = path.join(process.env.WINDIR || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
    const settings = voiceServiceSettings();
    voiceServiceProcess = spawn(powerShellExe, ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Root", root, "-Port", String(settings.port), "-Model", settings.model], { windowsHide: true, stdio: "ignore" });
    voiceServiceProcess.once("close", () => { voiceServiceProcess = null; });
    voiceServiceProcess.once("error", () => { voiceServiceProcess = null; });
    audit("voice_service_started", { port: settings.port, model: settings.model, pid: voiceServiceProcess.pid || "" });
  }
  for (let attempt = 0; attempt < 30; attempt += 1) {
    await wait(500);
    const health = await voiceHealth();
    if (health) return health;
  }
  throw new Error("Локальный Voice Service не запустился за 15 секунд. Проверьте runtime\\telegram\\voice\\voice-service.log.");
}

async function transcribeVoice(file) {
  await ensureVoiceService();
  const { port, model } = voiceServiceSettings();
  const form = new FormData();
  form.set("file", new Blob([fs.readFileSync(file.path)], { type: file.mime || "audio/ogg" }), file.filename);
  form.set("language", cleanText(config.voiceLanguage || "auto", 20));
  const response = await fetch(`http://127.0.0.1:${port}/v1/audio/transcriptions`, {
    method: "POST", headers: { "x-beeforge-key": bridgeKey }, body: form, signal: AbortSignal.timeout(10 * 60 * 1000),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(cleanText(result.detail || `Voice Service HTTP ${response.status}`, 1000));
  audit("voice_transcribed", { model, language: result.language || "", duration: result.duration || "", characters: String(result.text || "").length });
  return cleanText(result.text || "", 12000);
}

async function handleInboundAttachments(messages) {
  const instance = currentInstance();
  if (!instance) return send("Нет подключённого выбранного проекта OpenCode. Сначала выберите проект через /projects.");
  if (pendingProjectCreation) return send("Сначала завершите создание проекта или отправьте /cancel, затем пришлите файл снова.");
  try {
    const items = messages.map((message) => ({ message, descriptor: telegramAttachmentFromMessage(message) })).filter((item) => item.descriptor);
    if (!items.length) return;
    await send(`⬇️ Получаю вложения: ${items.length}…`);
    const attachments = [];
    for (const item of items.slice(0, 10)) attachments.push(await downloadTelegramAttachment(item.message, instance, item.descriptor));
    const caption = cleanText(items.map((item) => item.message.caption || "").find(Boolean) || "", 3000);
    const words = String(caption || "").trim().split(/\s+/);
    const command = words[0] || "";
    const explicitNew = command === "/new";
    const voiceItems = items.map((item, index) => ({ descriptor: item.descriptor, attachment: attachments[index] })).filter((item) => item.descriptor.kind === "voice" || item.descriptor.kind === "audio");
    const transcripts = [];
    for (const voice of voiceItems) {
      try {
        const transcript = await transcribeVoice(voice.attachment);
        if (transcript) transcripts.push(transcript);
      } catch (error) {
        audit("voice_transcription_failed", { file: voice.attachment.relative, error: error.message });
        await send(`⚠️ Голосовой файл сохранён, но распознавание не удалось\n${cleanText(error.message, 1200)}`);
      }
    }
    const baseCaption = explicitNew ? words.slice(1).join(" ") : caption;
    const voiceText = transcripts.length ? `${baseCaption ? `${baseCaption}\n\n` : ""}Распознанное голосовое сообщение:\n${transcripts.join("\n")}` : baseCaption;
    const promptText = attachmentPrompt(voiceText, attachments);
    if (explicitNew || pendingNewSessionInstance) {
      const target = pendingNewSessionInstance ? instances.get(pendingNewSessionInstance) : instance;
      pendingNewSessionInstance = null;
      if (!target) return send("Проект отключился. Выберите его снова через /projects.");
      queue(target.id, { type: "new_session", prompt: promptText, attachments, agent: "team-lead", mode: modeFromText(promptText) });
      return send(`✅ Вложения сохранены: ${attachments.length}\nСоздаю основную сессию Team Lead и передаю их одним сообщением.`);
    }
    if (!selectedSession) return send(`✅ Вложения сохранены: ${attachments.length}\nСначала создайте основную сессию через /new, затем отправьте их ещё раз.`);
    const result = enqueuePrompt(instance.id, { type: "prompt", sessionId: selectedSession, prompt: promptText, attachments, agent: "team-lead" });
    return send(result.queued ? `🕓 Вложения добавлены в очередь Team Lead · позиция ${result.position}` : `✅ Вложения переданы Team Lead\n${attachments.map((item) => item.relative).join("\n")}`);
  } catch (error) {
    audit("telegram_file_receive_failed", { directory: instance.directory, count: messages.length, error: error.message });
    return send(`❌ Не удалось обработать вложение\n${cleanText(error.message, 1500)}`);
  }
}

async function handleInboundAttachment(message) { return handleInboundAttachments([message]); }

function enqueueMediaGroup(message) {
  const key = String(message.media_group_id || "");
  if (!key) return false;
  const existing = pendingMediaGroups.get(key) || { messages: [], timer: null };
  existing.messages.push(message);
  if (existing.timer) clearTimeout(existing.timer);
  existing.timer = setTimeout(() => {
    pendingMediaGroups.delete(key);
    void handleInboundAttachments(existing.messages.sort((a, b) => Number(a.message_id) - Number(b.message_id)));
  }, 900);
  existing.timer.unref();
  pendingMediaGroups.set(key, existing);
  return true;
}

function eventAttachmentPaths(event) {
  const explicit = Array.isArray(event.attachments) ? event.attachments : [];
  const marked = [...String(event.finalText || "").matchAll(/^\s*(?:BEEFORGE_)?TELEGRAM_FILE\s*:\s*(?:`([^`]+)`|"([^"]+)"|(.+?))\s*$/gim)]
    .map((match) => match[1] || match[2] || match[3]).filter(Boolean);
  return [...new Set([...explicit, ...marked].map((item) => String(item).trim()).filter(Boolean))].slice(0, 10);
}

async function sendEventAttachments(event, instance) {
  if (event.parentID) return;
  for (const requested of eventAttachmentPaths(event)) {
    let key = "";
    try {
      const file = resolveProjectFile(instance.directory, requested);
      key = `${event.sessionId}:${canonical(file.path)}:${file.stat.size}:${file.stat.mtimeMs}`;
      if (deliveredFiles.has(key)) continue;
      // Reserve before the asynchronous upload. OpenCode commonly emits
      // assistant_update and idle for the same final answer almost together.
      // On failure the catch block removes the reservation so a retry remains possible.
      deliveredFiles.set(key, Date.now());
      await sendProjectFile(instance.directory, file.path, `Результат Team Lead · ${instance.projectName}\n${file.relative}`);
      deliveredFiles.set(key, Date.now());
    } catch (error) {
      if (key) deliveredFiles.delete(key);
      audit("telegram_file_send_failed", { directory: instance.directory, requested, error: error.message });
      await send(`❌ Не удалось отправить файл Team Lead\n${cleanText(requested, 500)}\n${cleanText(error.message, 1200)}`);
    }
  }
  const cutoff = Date.now() - 24 * 60 * 60 * 1000;
  for (const [key, at] of deliveredFiles) if (at < cutoff) deliveredFiles.delete(key);
}

async function answerCallback(id, text) {
  try { await telegram("answerCallbackQuery", { callback_query_id: id, text: cleanText(text, 180), show_alert: false }); } catch (error) { audit("callback_error", { error: error.message }); }
}

function queue(instanceId, command) {
  if (localModelLeased() && ["new_session", "prompt"].includes(command?.type)) throw new Error(remoteLeaseMessage);
  if (!instances.has(instanceId)) throw new Error("Экземпляр OpenCode недоступен");
  const item = { id: crypto.randomUUID(), createdAt: Date.now(), ...command };
  const list = commands.get(instanceId) || [];
  list.push(item);
  commands.set(instanceId, list);
  pendingCommands.set(item.id, { ...item, instanceId, deliveredAt: 0, notified: false });
  audit("command_queued", { instanceId, type: item.type, sessionId: item.sessionId || "" });
  return item;
}

function sessionIsBusy(sessionId) {
  const value = String(sessions.get(sessionId)?.status || sessions.get(sessionId)?.stage || "idle").toLowerCase();
  return /^(busy|running|working|compacting)$/.test(value);
}

function enqueuePrompt(instanceId, command) {
  if (!command?.sessionId || !sessionIsBusy(command.sessionId)) return { queued: false, command: queue(instanceId, command) };
  const item = { id: crypto.randomUUID(), instanceId, createdAt: Date.now(), ...command };
  queuedPrompts.push(item);
  saveBridgeState();
  audit("prompt_waiting", { instanceId, sessionId: command.sessionId, queueLength: queuedPrompts.filter((row) => row.sessionId === command.sessionId).length });
  schedulePinnedStatus();
  return { queued: true, position: queuedPrompts.filter((row) => row.sessionId === command.sessionId).length };
}

async function dispatchNextPrompt(sessionId) {
  const index = queuedPrompts.findIndex((item) => item.sessionId === sessionId);
  if (index < 0) return false;
  const [item] = queuedPrompts.splice(index, 1);
  if (!instances.has(item.instanceId)) {
    queuedPrompts.unshift(item);
    saveBridgeState();
    return false;
  }
  const { id: _id, instanceId, createdAt: _createdAt, ...command } = item;
  queue(instanceId, command);
  saveBridgeState();
  await send(`▶️ Передаю Team Lead следующее сообщение из очереди. Осталось: ${queuedPrompts.filter((row) => row.sessionId === sessionId).length}`);
  schedulePinnedStatus();
  return true;
}

function hasBlockingInteraction() {
  const now = Date.now();
  return [...openRequests.values()].some((token) => {
    const item = callbacks.get(token);
    return item && !item.used && Number(item.expiresAt || 0) > now;
  });
}

async function expireCommands() {
  const now = Date.now();
  for (const [commandId, item] of pendingCommands) {
    const timeout = item.deliveredAt ? 30000 : 15000;
    const since = item.deliveredAt || item.createdAt;
    if (now - since < timeout) continue;
    pendingCommands.delete(commandId);
    const list = commands.get(item.instanceId) || [];
    commands.set(item.instanceId, list.filter((command) => command.id !== commandId));
    audit("command_timeout", { commandId, instanceId: item.instanceId, type: item.type, delivered: Boolean(item.deliveredAt) });
    const reopened = reopenInteractiveCommand(item);
    await send(`⚠️ OpenCode не ответил на команду «${item.type}» за ${Math.floor(timeout / 1000)} секунд.\n\nПлагин будет переподключаться автоматически. Проверьте /status и повторите действие.${reopened ? " Кнопка запроса снова активна." : ""}`);
  }
}

function newCallback(data, ttlMs = 10 * 60 * 1000) {
  const token = crypto.randomBytes(16).toString("hex");
  callbacks.set(token, { ...data, expiresAt: Date.now() + ttlMs, used: false });
  saveBridgeState();
  return token;
}

function reopenInteractiveCommand(item) {
  if (!item?.callbackToken) return false;
  const callback = callbacks.get(item.callbackToken);
  if (!callback) return false;
  callback.used = false;
  callback.expiresAt = Date.now() + 5 * 60 * 1000;
  if (item.requestKey) openRequests.set(item.requestKey, item.callbackToken);
  saveBridgeState();
  return true;
}

function closeInteractiveCommand(item) {
  if (!item?.callbackToken) return;
  callbacks.delete(item.callbackToken);
  if (item.requestKey) openRequests.delete(item.requestKey);
  saveBridgeState();
}

function currentInstance() {
  if (selectedInstance && instances.has(selectedInstance)) return instances.get(selectedInstance);
  if (selectedDirectory) {
    const matching = [...instances.values()].find((item) => canonical(item.directory) === canonical(selectedDirectory));
    if (matching) {
      selectedInstance = matching.id;
      selectedDirectory = matching.directory;
      saveBridgeState();
      return matching;
    }
    return null;
  }
  const first = [...instances.values()][0];
  if (first) {
    selectedInstance = first.id;
    selectedDirectory = first.directory;
    saveBridgeState();
  }
  return first || null;
}

function sessionLabel(item) {
  const project = path.win32.basename(item.directory || "project");
  return `${project} · ${item.agent || "Team Lead"} · ${statusLabel(item.status)}`;
}

function statusLabel(status) {
  const value = String(status || "idle").toLowerCase();
  if (value === "busy" || value === "running" || value === "working") return "выполняет задачу";
  if (value === "compacting") return "сжимает контекст";
  if (value === "idle") return "ожидает";
  if (value === "error") return "ошибка";
  return cleanText(value, 40);
}

function compactProgress(value) {
  const text = cleanText(value, 12000);
  if (!text) return "";
  const buckets = { done: [], active: [], next: [], files: [] };
  let section = "";
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  for (const raw of lines) {
    const heading = raw.replace(/^#{1,6}\s*/, "").replace(/^[*_]{1,3}\s*/, "").replace(/\s*[*_]{1,3}$/, "").replace(/[:：]\s*$/, "").trim();
    if (/^(completed|done|сделано|выполнено|готово|завершено)$/i.test(heading)) { section = "done"; continue; }
    if (/^(objective|work state|active|in progress|сейчас активно|активно|текущее состояние)$/i.test(heading)) { section = "active"; continue; }
    if (/^(next move|next steps?|remaining|todo|осталось|следующие шаги|дальше)$/i.test(heading)) { section = "next"; continue; }
    if (/^(relevant files?|files?|релевантные файлы|файлы)$/i.test(heading)) { section = "files"; continue; }
    if (/^(important details?|details?|риски|примечания)$/i.test(heading)) { section = ""; continue; }
    if (section && buckets[section].join("\n").length < (section === "files" ? 500 : 1100)) buckets[section].push(raw);
  }
  if (!buckets.done.length) buckets.done = lines.filter((line) => /\b(done|pass(?:es|ed)?|created|rewritten|fixed|green|готово|сделано|выполнено|исправлено|завершено)\b/i.test(line)).slice(0, 7);
  if (!buckets.next.length) buckets.next = lines.filter((line) => /\b(next|resolve|remaining|todo|write|verify|осталось|следующ|проверить|доделать)\b/i.test(line)).slice(0, 6);
  if (!buckets.active.length) buckets.active = lines.filter((line) => !/^#{1,6}\s/.test(line)).slice(0, 3);
  const fileMatches = [...text.matchAll(/(?:[A-Za-z]:\\[^\s`"']+|(?:src|tests|scripts|docs|data|config|ui|tools)\/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+)/g)].map((match) => match[0].replace(/[),.;:]+$/, ""));
  buckets.files.push(...fileMatches);
  buckets.files = [...new Set(buckets.files)].slice(0, 12);
  const render = (title, items, max) => items.length ? `${title}:\n${cleanText(items.join("\n"), max)}` : "";
  return [render("Сделано", buckets.done, 1150), render("Сейчас активно", buckets.active, 650), render("Следующие шаги", buckets.next, 1000), render("Релевантные файлы", buckets.files, 600)].filter(Boolean).join("\n\n");
}

async function sendProgress(event, title) {
  const summary = compactProgress(event.finalText);
  if (!summary) return;
  const hash = crypto.createHash("sha256").update(summary).digest("hex");
  if (deliveredProgress.get(event.sessionId) === hash) return;
  deliveredProgress.set(event.sessionId, hash);
  const source = event.parentID ? "Субагент" : "Агент";
  await send(`${title}\nПроект: ${event.projectName}\n${source}: ${event.agent || "Team Lead"}\n\n${summary}`);
}

function scheduleMainProgress(event, delayMs = 900) {
  const previous = pendingMainProgress.get(event.sessionId);
  if (previous?.timer) clearTimeout(previous.timer);
  const timer = setTimeout(() => {
    pendingMainProgress.delete(event.sessionId);
    void sendProgress(event, "📝 Обновление работы").catch((error) => audit("main_progress_send_failed", { sessionId: event.sessionId, error: error.message }));
  }, delayMs);
  timer.unref();
  pendingMainProgress.set(event.sessionId, { timer, event });
}

function cancelMainProgress(sessionId) {
  const pending = pendingMainProgress.get(sessionId);
  if (!pending) return;
  clearTimeout(pending.timer);
  pendingMainProgress.delete(sessionId);
}

async function flushMainProgress(sessionId) {
  const pending = pendingMainProgress.get(sessionId);
  if (!pending) return;
  clearTimeout(pending.timer);
  pendingMainProgress.delete(sessionId);
  await sendProgress(pending.event, "📝 Обновление работы");
}

function splitTelegramText(value, maxLength = 3800) {
  const text = String(value || "");
  if (!text) return [];
  const chunks = [];
  let remaining = text;
  while (remaining.length > maxLength) {
    const window = remaining.slice(0, maxLength + 1);
    let splitAt = window.lastIndexOf("\n\n");
    if (splitAt < Math.floor(maxLength * 0.55)) splitAt = window.lastIndexOf("\n");
    if (splitAt < Math.floor(maxLength * 0.55)) splitAt = window.lastIndexOf(" ");
    if (splitAt < Math.floor(maxLength * 0.55)) splitAt = maxLength;
    chunks.push(remaining.slice(0, splitAt));
    remaining = remaining.slice(splitAt);
    if (remaining.startsWith("\n\n")) remaining = remaining.slice(2);
    else if (remaining.startsWith("\n") || remaining.startsWith(" ")) remaining = remaining.slice(1);
  }
  if (remaining) chunks.push(remaining);
  return chunks;
}

async function sendTeamLeadVerdict(event) {
  const full = cleanText(event.finalText, 100000);
  if (!full) return;
  const hash = crypto.createHash("sha256").update(full).digest("hex");
  if (deliveredFinals.get(event.sessionId) === hash) return;
  deliveredFinals.set(event.sessionId, hash);
  const header = `✅ Финальный отчёт Team Lead\nПроект: ${event.projectName}`;
  const parts = splitTelegramText(full, 3700);
  for (let index = 0; index < parts.length; index += 1) {
    const partHeader = index === 0 ? header : `📄 Продолжение финального отчёта Team Lead · ${index + 1}/${parts.length}`;
    await send(`${partHeader}\n\n${parts[index]}`);
  }
}

function mainMenuKeyboard() {
  const projects = newCallback({ kind: "menu" });
  const sessionsToken = newCallback({ kind: "menu" });
  const newSession = newCallback({ kind: "menu" });
  const status = newCallback({ kind: "menu" });
  const notifications = newCallback({ kind: "menu" });
  const model = newCallback({ kind: "menu" });
  const launch = newCallback({ kind: "menu" });
  const closeAll = newCallback({ kind: "menu" });
  const files = newCallback({ kind: "menu" });
  const history = newCallback({ kind: "menu" });
  const profiles = newCallback({ kind: "menu" });
  const worktrees = newCallback({ kind: "menu" });
  const clearChat = newCallback({ kind: "menu" });
  const fullAccess = newCallback({ kind: "menu" });
  const fullAccessEnabled = readFullAccessStatus().enabled;
  return { inline_keyboard: [
    [{ text: "📂 Проекты", callback_data: `bf:${projects}:projects` }, { text: "🧵 Сессии", callback_data: `bf:${sessionsToken}:sessions` }],
    [{ text: "➕ Новая сессия", callback_data: `bf:${newSession}:new` }, { text: "📊 Статус", callback_data: `bf:${status}:status` }],
    [{ text: muted ? "🔔 Включить уведомления" : "🔕 Приглушить уведомления", callback_data: `bf:${notifications}:${muted ? "unmute" : "mute"}` }],
    [{ text: "📁 Файлы", callback_data: `bf:${files}:files` }, { text: "🕘 История", callback_data: `bf:${history}:messages` }],
    [{ text: "🧩 Worktree", callback_data: `bf:${worktrees}:worktrees` }, { text: "🎛 Профили", callback_data: `bf:${profiles}:profiles` }],
    [{ text: "🤖 Состояние модели", callback_data: `bf:${model}:model` }],
    [{ text: fullAccessEnabled ? "🟠 Полный доступ: ВКЛ" : "🛡 Полный доступ: ВЫКЛ", callback_data: `bf:${fullAccess}:fullaccess` }],
    [{ text: "🚀 Запустить всё", callback_data: `bf:${launch}:launch` }],
    [{ text: lifecycleActions.all.button, callback_data: `bf:${closeAll}:closeall` }],
    [{ text: "🧹 Очистить чат", callback_data: `bf:${clearChat}:clear` }],
  ] };
}

function modeFromText(text) {
  const value = String(text || "").toLowerCase();
  if (/release|релизн|максимально тщательно|публикац/.test(value)) return "RELEASE";
  if (/standard|стандарт|мобильн|полная обычная/.test(value)) return "STANDARD";
  if (/plan.only|plan_only|только план|сначала.*план/.test(value)) return "PLAN_ONLY";
  return "FAST";
}

function isCriticalPermission(event) {
  // Removing a process-local environment variable is credential hygiene, not a
  // destructive filesystem operation. Strip only that narrow PowerShell form;
  // any subsequent command after a semicolon remains visible to the matcher.
  const text = JSON.stringify(event).toLowerCase()
    .replace(/remove-item\s+(?:(?:-path|-literalpath)\s+)?env:[^;\r\n"']+/gi, "");
  return /(force\s*push|push\s+--force|reset\s+--hard|clean\s+-[a-z]*f|remove-item|rm\s+-rf|(?:rd|rmdir)\s+\/s|del\s+\/|format\s|diskpart|stop-process|stop-service|restart-computer|taskkill|shutdown|(?:sc|net)\s+stop|external_directory|outside.*project|delete|удален)/i.test(text);
}

function firstNotification(key, ttlMs = 15000) {
  const now = Date.now();
  const previous = recentNotifications.get(key) || 0;
  recentNotifications.set(key, now);
  for (const [item, at] of recentNotifications) if (now - at > 10 * 60 * 1000) recentNotifications.delete(item);
  return now - previous > ttlMs;
}

async function notifyPermission(event) {
  if (!event?.sessionId || !event?.requestId) {
    audit("permission_event_invalid", { instanceId: event?.instanceId || "", sessionId: event?.sessionId || "", hasRequestId: Boolean(event?.requestId) });
    return;
  }
  const key = `permission:${event.instanceId}:${event.requestId}`;
  const current = openRequests.get(key);
  if (current && callbacks.get(current) && !callbacks.get(current).used) return;
  const detail = cleanText(event.detail || event.permission || "Операция требует разрешения", 1700);
  const token = newCallback({ kind: "permission", instanceId: event.instanceId, sessionId: event.sessionId, requestId: event.requestId, api: event.api, critical: isCriticalPermission(event), detail });
  openRequests.set(key, token);
  await send(`🔐 Запрос разрешения\n\nПроект: ${event.projectName}\nАгент: ${event.agent || "не указан"}\n${detail}\n\n«Разрешить всегда» сохранит правило OpenCode для совпадающих действий.`, {
    inline_keyboard: [
      [{ text: "✅ Один раз", callback_data: `bf:${token}:allow` }, { text: "♾ Разрешить всегда", callback_data: `bf:${token}:always` }],
      [{ text: "⛔ Отклонить", callback_data: `bf:${token}:reject` }, { text: "ℹ️ Подробнее", callback_data: `bf:${token}:details` }],
    ],
  });
}

async function notifyQuestion(event) {
  const key = `${event.instanceId}:${event.requestId}`;
  const requestKey = `question:${key}`;
  const current = openRequests.get(requestKey);
  if (current && callbacks.get(current) && !callbacks.get(current).used) return;
  pendingQuestions.set(key, event);
  const rows = [];
  const options = Array.isArray(event.options) ? event.options.slice(0, 8) : [];
  for (const option of options) {
    const token = newCallback({ kind: "question", instanceId: event.instanceId, sessionId: event.sessionId, requestId: event.requestId, api: event.api, answer: String(option) });
    rows.push([{ text: cleanText(option, 48), callback_data: `bf:${token}:answer` }]);
  }
  const textToken = newCallback({ kind: "question_text", key }); openRequests.set(requestKey, textToken);
  rows.push([{ text: "✍️ Ответить текстом", callback_data: `bf:${textToken}:text` }]);
  const sent = await send(`❓ Вопрос от агента\n\nПроект: ${event.projectName}\nАгент: ${event.agent || "Team Lead"}\n${cleanText(event.question, 2400)}`, { inline_keyboard: rows });
  pendingQuestions.set(key, { ...event, telegramMessageId: sent.message_id });
  saveBridgeState();
}

function closeRequest(event) {
  const key = `${event.kind === "permission_closed" ? "permission" : "question"}:${event.instanceId}:${event.requestId}`;
  for (const item of callbacks.values()) {
    if (item.instanceId === event.instanceId && item.requestId === event.requestId) item.used = true;
  }
  openRequests.delete(key);
  if (event.kind === "question_closed") pendingQuestions.delete(`${event.instanceId}:${event.requestId}`);
  saveBridgeState();
}

async function handleEvent(event) {
  const instance = instances.get(event.instanceId);
  if (!instance) return;
  event.projectName = instance.projectName;
  if (event.kind === "idle" && !event.parentID) event.agent = "team-lead";
  let lateAssistantUpdate = false;
  if (event.sessionId) {
    const old = sessions.get(event.sessionId) || {};
    const oldState = String(old.status || old.stage || "").toLowerCase();
    // OpenCode can emit the terminal session.idle event before the final
    // message.updated notification reaches the plugin. That notification is
    // informative, not a new model turn, so it must never re-mark an already
    // idle Team Lead session as working and strand the next Telegram prompt.
    const keepIdle = event.kind === "assistant_update" && oldState === "idle";
    lateAssistantUpdate = keepIdle;
    const nextStatus = event.kind === "idle" ? "idle" : (keepIdle ? (old.status || "idle") : (event.status || old.status));
    if (keepIdle) audit("assistant_update_after_idle", { instanceId: event.instanceId, sessionId: event.sessionId });
    sessions.set(event.sessionId, { ...old, id: event.sessionId, instanceId: event.instanceId, directory: instance.directory, projectName: instance.projectName, updatedAt: Date.now(), startedAt: old.startedAt || (event.kind === "prompted" ? Date.now() : undefined), agent: event.agent || old.agent, stage: event.kind === "delegation" ? event.agent : (old.stage || event.status), status: nextStatus, mode: event.mode || old.mode || "FAST", title: event.title || old.title, parentID: event.parentID || old.parentID || "" });
    if (event.kind === "prompted" && !event.parentID) {
      selectedInstance = instance.id;
      selectedDirectory = instance.directory;
      selectedSession = event.sessionId;
      saveBridgeState();
    } else if (!selectedSession && !event.parentID) {
      selectedInstance = instance.id;
      selectedDirectory = instance.directory;
      selectedSession = event.sessionId;
      saveBridgeState();
    }
  }
  switch (event.kind) {
    case "permission": await notifyPermission(event); break;
    case "question": await notifyQuestion(event); break;
    case "permission_closed":
    case "question_closed": closeRequest(event); break;
    case "prompted":
      if (!muted) await send(`▶️ Задача запущена\nПроект: ${instance.projectName}\nРежим: ${event.mode || "FAST"}\nАгент: ${event.agent || "Team Lead"}`);
      break;
    case "delegation":
      if (!event.parentID) await flushMainProgress(event.sessionId);
      if (!muted && config.notifyDelegation && firstNotification(`${event.sessionId}:delegate:${event.agent}:${event.detail}`)) await send(`👤 Team Lead назначил: ${cleanText(event.agent || "специалист")}\nПроект: ${instance.projectName}\n${cleanText(event.detail, 800)}`);
      break;
    case "assistant_update":
      if (!muted && !lateAssistantUpdate) {
        if (event.parentID) await sendProgress(event, "📝 Обновление работы");
        else scheduleMainProgress(event);
      }
      await sendEventAttachments(event, instance);
      break;
    case "compaction_started":
      await send(`🗜 Начато сжатие контекста\nПроект: ${instance.projectName}\nАгент: ${event.agent || "Team Lead"}\nСессия продолжится автоматически после формирования сводки.`);
      break;
    case "compaction_ended":
      await sendProgress(event, "✅ Сжатие контекста завершено");
      break;
    case "error":
      if (config.notifyErrors) await send(`❌ Ошибка BeeForge/OpenCode\nПроект: ${instance.projectName}\n${cleanText(event.detail, 2500)}`);
      break;
    case "idle":
      if (!event.parentID) cancelMainProgress(event.sessionId);
      if (!muted && config.notifyCompletion) {
        if (event.parentID) await sendProgress(event, "✅ Субагент завершил этап");
        else await sendTeamLeadVerdict(event);
      }
      await sendEventAttachments(event, instance);
      if (!event.parentID) await dispatchNextPrompt(event.sessionId);
      break;
  }
  schedulePinnedStatus();
}

function buildStatusText() {
  pruneInstances();
  const accessLine = readFullAccessStatus().enabled ? "Полный доступ: 🟠 ВКЛЮЧЁН" : "Полный доступ: 🟢 выключен";
  const ownerLine = localModelLeased() ? "Использование модели: 🔒 передано ноутбуку" : "Использование модели: 🖥 только основной ПК";
  let modelLine = "Модель: состояние недоступно";
  try {
    const model = readModelStatus();
    modelLine = `Модель: ${model.Ready ? "READY" : model.Running ? "LOADING" : "STOPPED"} · ${model.Profile || "не выбрана"}`;
  } catch {}
  const allSessions = [...sessions.values()].sort((a, b) => b.updatedAt - a.updatedAt);
  const mainSessions = allSessions.filter((item) => !item.parentID);
  const selected = selectedSession ? sessions.get(selectedSession) : mainSessions[0];
  const elapsed = selected?.startedAt ? Math.max(0, Math.floor((Date.now() - selected.startedAt) / 60000)) : null;
  const context = selected?.contextPercent === undefined ? "" : `\nКонтекст: ${selected.contextPercent}%`;
  const changed = Array.isArray(selected?.changedFiles) && selected.changedFiles.length ? `\nИзменено файлов: ${selected.changedFiles.length} · ${selected.changedFiles.slice(0, 4).join(", ")}` : "";
  const queued = queuedPrompts.filter((item) => item.sessionId === selected?.id).length;
  const focus = selected ? `\nТекущая задача: ${selected.title || selected.projectName}\nПроект: ${selected.projectName}\nРежим: ${selected.mode || "FAST"}\nАгент: ${selected.agent || "Team Lead"}\nСостояние: ${statusLabel(selected.status || selected.stage)}\nВремя: ${elapsed === null ? "—" : `${elapsed} мин`}${context}${changed}${queued ? `\nВ очереди сообщений: ${queued}` : ""}` : "";
  const state = (item) => String(item.status || item.stage || "idle").toLowerCase();
  const waiting = allSessions.filter((item) => state(item) === "idle");
  const working = allSessions.filter((item) => /^(busy|running|working|compacting|error)$/.test(state(item)));
  const waitingMain = waiting.filter((item) => !item.parentID);
  const waitingTeam = waiting.filter((item) => item.parentID);
  const countBy = (items, key) => [...items.reduce((map, item) => {
    const value = key(item) || "не указан";
    map.set(value, (map.get(value) || 0) + 1);
    return map;
  }, new Map()).entries()].sort((a, b) => b[1] - a[1] || String(a[0]).localeCompare(String(b[0]), "ru"));
  const agentName = (value) => /^team[- ]?lead$/i.test(String(value || "")) ? "Team Lead" : String(value || "не указан");
  const lines = [];
  if (working.length) lines.push(`Выполняются сейчас (${working.length}):\n${working.slice(0, 3).map((item) => `• ${item.projectName} · ${agentName(item.agent)} · ${statusLabel(state(item))}`).join("\n")}${working.length > 3 ? `\n… и ещё ${working.length - 3}` : ""}`);
  else lines.push("Выполняются сейчас: нет.");
  if (waiting.length) {
    const roles = countBy(waiting, (item) => agentName(item.agent)).slice(0, 4).map(([name, count]) => `${name} — ${count}`).join(", ");
    const projects = countBy(waiting, (item) => item.projectName).slice(0, 4).map(([name, count]) => `${name}: ${count}`).join(", ");
    lines.push(`Ожидают: ${waitingMain.length} основных сессий${waitingTeam.length ? `, команда: ${waitingTeam.length}` : ""}.\nРоли: ${roles}\nПроекты: ${projects}`);
  } else lines.push("Ожидающих сессий нет.");
  return cleanText(`BeeForge Telegram Bridge\nСостояние: работает\n${modelLine}\n${ownerLine}\n${accessLine}\nOpenCode: ${instances.size} подключено\nАвтоматические сводки: выключены${focus}\n\nКоманда:\n${lines.join("\n\n")}\n\nbusy / «выполняет задачу» означает, что модель сейчас обрабатывает запрос или инструмент.`, 3900);
}

function schedulePinnedStatus(delayMs = 1500) {
  if (config.pinnedStatus === false || stopping) return;
  if (pinnedUpdateTimer) clearTimeout(pinnedUpdateTimer);
  pinnedUpdateTimer = setTimeout(() => { pinnedUpdateTimer = null; void updatePinnedStatus(); }, delayMs);
  pinnedUpdateTimer.unref();
}

async function updatePinnedStatus(forceCreate = false) {
  if (config.pinnedStatus === false || pinnedUpdateInFlight) return;
  pinnedUpdateInFlight = true;
  const text = buildStatusText();
  try {
    if (pinnedMessageId && !forceCreate) {
      try {
        await telegram("editMessageText", { chat_id: config.allowedChatId, message_id: pinnedMessageId, text, disable_web_page_preview: true, reply_markup: mainMenuKeyboard() });
        return;
      } catch (error) {
        if (/message is not modified/i.test(String(error.message))) return;
        audit("pinned_status_edit_failed", { messageId: pinnedMessageId, error: error.message });
        pinnedMessageId = null;
      }
    }
    const sent = await send(`📌 ${text}`, mainMenuKeyboard());
    pinnedMessageId = Number(sent?.message_id || 0) || null;
    saveBridgeState();
    if (pinnedMessageId) {
      try { await telegram("pinChatMessage", { chat_id: config.allowedChatId, message_id: pinnedMessageId, disable_notification: true }); }
      catch (error) { audit("pinned_status_pin_failed", { messageId: pinnedMessageId, error: error.message }); }
    }
  } finally { pinnedUpdateInFlight = false; }
}

async function showStatus() {
  const instance = currentInstance();
  if (instance && selectedSession) queue(instance.id, { type: "session_overview", sessionId: selectedSession, silent: true });
  await send(buildStatusText(), mainMenuKeyboard());
  schedulePinnedStatus(50);
}

async function showProjects() {
  pruneInstances();
  const rows = [];
  const projects = new Map();
  for (const projectPath of config.allowedProjects || []) projects.set(canonical(projectPath), path.win32.resolve(projectPath));
  for (const instance of instances.values()) projects.set(canonical(instance.directory), instance.directory);
  const ordered = [...projects.values()].sort((a, b) => {
    const aConnected = [...instances.values()].some((item) => canonical(item.directory) === canonical(a));
    const bConnected = [...instances.values()].some((item) => canonical(item.directory) === canonical(b));
    return Number(bConnected) - Number(aConnected) || path.win32.basename(a).localeCompare(path.win32.basename(b), "ru");
  });
  const lines = ordered.map((projectPath) => {
    const connected = [...instances.values()].find((item) => canonical(item.directory) === canonical(projectPath));
    const selected = connected ? connected.id === selectedInstance : (selectedDirectory && canonical(selectedDirectory) === canonical(projectPath));
    const token = newCallback({ kind: "select_project", instanceId: connected?.id || "", directory: projectPath, projectName: connected?.projectName || path.win32.basename(projectPath) });
    rows.push([{ text: `${selected ? "✅ " : ""}${connected ? "🟢 " : "⚪ "}${connected?.projectName || path.win32.basename(projectPath)}`, callback_data: `bf:${token}:select` }]);
    return `${connected ? "🟢" : "⚪"} ${path.win32.basename(projectPath)} — ${connected ? "OpenCode подключён" : "не открыт"}`;
  });
  await send(lines.length ? `Проекты OpenCode и разрешённые папки:\n${lines.join("\n")}\n\nЛюбой проект можно выбрать кнопкой; для ⚪ OpenCode будет запущен с нужной папкой. Новый проект: /create Имя или /createat C:\\Путь\\Имя.` : "Проекты пока не найдены. Создайте новый: /create ИмяПроекта", rows.length ? { inline_keyboard: rows } : undefined);
}

async function showSessions() {
  pruneInstances();
  const instance = currentInstance();
  if (!instance) return send("Нет подключённого проекта OpenCode.");
  queue(instance.id, { type: "list_sessions" });
  await send(`Запрашиваю сессии проекта ${instance.projectName}…`);
}

async function handleMessage(message) {
  if (String(message.from?.id) !== String(config.allowedUserId) || String(message.chat?.id) !== String(config.allowedChatId) || message.chat?.type !== "private") {
    audit("unauthorized", { userId: message.from?.id, chatId: message.chat?.id, chatType: message.chat?.type });
    return;
  }
  const text = cleanText(message.text || message.caption || "", 3500);
  const incomingAttachment = telegramAttachmentFromMessage(message);
  if (!text && !incomingAttachment) return;
  if (incomingAttachment && localModelLeased()) return send(remoteLeaseMessage);
  if (message.reply_to_message && text && !incomingAttachment) {
    const pending = [...pendingQuestions.values()].find((item) => Number(item.telegramMessageId) === Number(message.reply_to_message.message_id));
    if (pending) {
      const requestKey = `question:${pending.instanceId}:${pending.requestId}`;
      let callbackToken = openRequests.get(requestKey);
      if (!callbackToken || !callbacks.has(callbackToken)) callbackToken = newCallback({ kind: "question_text", key: `${pending.instanceId}:${pending.requestId}` });
      const callback = callbacks.get(callbackToken); if (callback) callback.used = true;
      openRequests.set(requestKey, callbackToken);
      queue(pending.instanceId, { type: "question_reply", sessionId: pending.sessionId, requestId: pending.requestId, api: pending.api, answer: text, callbackToken, requestKey });
      saveBridgeState();
      return send("Отправляю ответ агенту…");
    }
  }
  const [command, ...rest] = text ? text.split(/\s+/) : ["attachment"];
  audit("telegram_command", { command: incomingAttachment ? "attachment" : (command || "message"), userId: message.from?.id, chatId: message.chat?.id });
  if (incomingAttachment && message.media_group_id) { enqueueMediaGroup(message); return; }
  if (incomingAttachment) return handleInboundAttachment(message);
  if (command === "/help" || command === "/start") return send("BeeForge Telegram\n/status — состояние и закреплённая карточка\n/projects, /sessions, /new [задача]\n/messages — история, fork и безопасный откат\n/files [путь] — просмотр и скачивание файлов\n/worktrees; /worktree create Имя\n/profiles — выбрать профиль BeeForge\n/task — запланировать Team Lead; /tasklist; /taskdel ID\n/queue — очередь сообщений; /queueclear\n/create Имя; /createat C:\\Путь\\Имя\n/send Путь — отправить файл\n/model — состояние модели; /launch — запустить всё\n/fullaccess — управление полным доступом\n/closeall — выгрузить модель и закрыть приложения\n/clear — очистить недавние сообщения чата\n/stop, /mute, /unmute, /cancel\n\nГолосовые сообщения распознаются локально и передаются Team Lead. Альбомы фото и файлов приходят одним запросом. Включение полного доступа, критические действия, revert и удаление worktree требуют двойного подтверждения. Reasoning, полные tool outputs и секреты в Telegram не отправляются.", mainMenuKeyboard());
  if (command === "/status") return showStatus();
  if (command === "/projects") return showProjects();
  if (command === "/sessions") return showSessions();
  if (command === "/profiles") return showProfiles();
  if (command === "/console") return startConsole();
  if (command === "/model") return showModelStatus();
  if (command === "/modelstart") return startLastModel();
  if (command === "/launch") {
    if (localModelLeased()) return startLastModel();
    const directory = selectedDirectory || currentInstance()?.directory || "";
    if (!directory) return send("Сначала выберите проект через /projects.");
    return startLastModel(directory);
  }
  if (command === "/modelstop") return requestLifecycleAction("model");
  if (command === "/opencodeclose") return requestLifecycleAction("opencode");
  if (command === "/consoleclose") return requestLifecycleAction("console");
  if (command === "/closeall") return requestLifecycleAction("all");
  if (command === "/fullaccess") {
    const requested = String(rest[0] || "").toLowerCase();
    if (requested === "on" || requested === "enable" || requested === "вкл") return requestFullAccessEnable();
    if (requested === "off" || requested === "disable" || requested === "выкл") return executeFullAccessAction(false, message.from.id);
    return showFullAccess();
  }
  if (command === "/clear") {
    const token = newCallback({ kind: "clear_chat", anchorMessageId: Number(message.message_id || 0) }, 2 * 60 * 1000);
    return send("⚠️ Очистить последние доступные сообщения в чате? Telegram разрешает удалить сообщения не старше 48 часов. После очистки останется только новое служебное сообщение.", { inline_keyboard: [[{ text: "🧹 Очистить чат", callback_data: `bf:${token}:confirm` }, { text: "Отмена", callback_data: `bf:${token}:cancel` }]] });
  }
  if (command === "/mute") { muted = true; saveBridgeState(); audit("mute", { value: muted, userId: message.from.id }); return send("Обычные уведомления приглушены. Вопросы, разрешения и ошибки останутся активны.", mainMenuKeyboard()); }
  if (command === "/unmute") { muted = false; saveBridgeState(); audit("mute", { value: muted, userId: message.from.id }); return send("Обычные уведомления снова включены.", mainMenuKeyboard()); }
  if (command === "/create") {
    const requestedName = rest.join(" ").trim();
    if (!requestedName) {
      pendingProjectCreation = { kind: "default", createdAt: Date.now() };
      pendingNewSessionInstance = null;
      saveBridgeState();
      return send(`Создание нового проекта в папке по умолчанию:\n${path.win32.resolve(config.defaultProjectRoot || "C:\\AI\\Projects")}\n\nОтправьте следующим сообщением только имя проекта.`);
    }
    try {
      const name = validateProjectName(requestedName);
      const root = path.win32.resolve(config.defaultProjectRoot || "C:\\AI\\Projects");
      return await createProject(path.win32.join(root, name));
    } catch (error) { return send(`❌ ${cleanText(error.message, 900)}`); }
  }
  if (command === "/createat") {
    const requestedPath = rest.join(" ").trim();
    if (!requestedPath) {
      pendingProjectCreation = { kind: "explicit", createdAt: Date.now() };
      pendingNewSessionInstance = null;
      saveBridgeState();
      return send("Создание нового проекта в выбранном месте.\nОтправьте следующим сообщением полный путь, например C:\\Projects\\NewApp.");
    }
    try { return await createProject(validateExplicitProjectPath(requestedPath)); }
    catch (error) { return send(`❌ ${cleanText(error.message, 900)}`); }
  }
  if (pendingProjectCreation && !text.startsWith("/")) {
    const pending = pendingProjectCreation;
    try {
      const directory = pending.kind === "explicit"
        ? validateExplicitProjectPath(text)
        : path.win32.join(path.win32.resolve(config.defaultProjectRoot || "C:\\AI\\Projects"), validateProjectName(text));
      return await createProject(directory);
    } catch (error) {
      pendingProjectCreation = pending;
      saveBridgeState();
      return send(`❌ ${cleanText(error.message, 900)}\n\nПопробуйте ещё раз или отправьте /cancel.`);
    }
  }
  if (command === "/cancel") {
    pendingProjectCreation = null;
    pendingNewSessionInstance = null;
    saveBridgeState();
    return send("Текущее пошаговое действие отменено.");
  }
  if (command === "/tasklist") return showScheduledTasks();
  if (command === "/taskdel") {
    const prefix = rest.join("").trim().toLowerCase();
    const index = scheduledTasks.findIndex((item) => item.id.toLowerCase().startsWith(prefix));
    if (!prefix || index < 0) return send("Задача не найдена. Используйте /tasklist.");
    const [removed] = scheduledTasks.splice(index, 1); saveBridgeState();
    return send(`✅ Расписание удалено: ${removed.id.slice(0, 8)} · ${cleanText(removed.prompt, 200)}`);
  }
  if (command === "/queue") {
    const rows = queuedPrompts.filter((item) => item.sessionId === selectedSession);
    return send(rows.length ? `Очередь Team Lead:\n${rows.map((item, index) => `${index + 1}. ${cleanText(item.prompt, 220)}`).join("\n")}` : "Очередь выбранной сессии пуста.");
  }
  if (command === "/queueclear") {
    for (let index = queuedPrompts.length - 1; index >= 0; index -= 1) if (queuedPrompts[index].sessionId === selectedSession) queuedPrompts.splice(index, 1);
    saveBridgeState(); schedulePinnedStatus(); return send("Очередь выбранной сессии очищена.");
  }
  const instance = currentInstance();
  if (!instance) return send("Нет подключённого разрешённого проекта OpenCode.");
  if (command === "/files") return showFiles(rest.join(" ").trim());
  if (command === "/messages") {
    if (!selectedSession) return send("Сначала выберите основную сессию через /sessions.");
    queue(instance.id, { type: "list_messages", sessionId: selectedSession });
    return send("Запрашиваю безопасную историю основной сессии…");
  }
  if (command === "/worktrees") { queue(instance.id, { type: "list_worktrees" }); return send("Запрашиваю worktree проекта…"); }
  if (command === "/worktree") {
    if (String(rest[0] || "").toLowerCase() !== "create") return send("Формат: /worktree create Имя");
    try {
      const name = validateProjectName(rest.slice(1).join(" ").trim());
      queue(instance.id, { type: "create_worktree", name });
      return send(`Создаю изолированный OpenCode worktree «${name}»…`);
    } catch (error) { return send(`❌ ${cleanText(error.message, 900)}`); }
  }
  if (command === "/task") {
    try {
      const parsed = parseTaskSpec(rest.join(" "));
      const task = { id: crypto.randomUUID(), directory: instance.directory, projectName: instance.projectName, prompt: parsed.prompt, schedule: parsed.schedule, enabled: true, createdAt: new Date().toISOString() };
      task.nextRunAt = nextScheduledAt(task.schedule).toISOString();
      if (task.schedule.kind === "once" && new Date(task.nextRunAt) <= new Date()) throw new Error("Одноразовая задача должна быть запланирована на будущее.");
      scheduledTasks.push(task); saveBridgeState();
      return send(`✅ Задача Team Lead запланирована\nID: ${task.id.slice(0, 8)}\nПроект: ${task.projectName}\nКогда: ${scheduleLabel(task)}\nСледующий запуск: ${new Date(task.nextRunAt).toLocaleString("ru-RU")}`);
    } catch (error) { return send(`❌ ${cleanText(error.message, 1200)}`); }
  }
  if (command === "/send") {
    const requested = rest.join(" ").trim();
    if (!requested) return send("Укажите относительный путь внутри выбранного проекта: /send output\\result.zip");
    try {
      const file = await sendProjectFile(instance.directory, requested);
      return send(`✅ Файл отправлен: ${file.relative}`);
    } catch (error) { return send(`❌ Не удалось отправить файл\n${cleanText(error.message, 1400)}`); }
  }
  if (command === "/new") {
    if (localModelLeased()) return send(remoteLeaseMessage);
    pendingProjectCreation = null;
    saveBridgeState();
    const prompt = rest.join(" ").trim();
    if (!prompt) {
      pendingNewSessionInstance = instance.id;
      return send(`Создание новой основной сессии Team Lead в проекте ${instance.projectName}.\nОтправьте следующим сообщением текст задачи.`);
    }
    queue(instance.id, { type: "new_session", prompt, agent: "team-lead", mode: modeFromText(prompt) });
    return send(`Создаю задачу Team Lead в проекте ${instance.projectName}…`);
  }
  if (command === "/stop") {
    if (!selectedSession) return send("Сессия не выбрана.");
    queue(instance.id, { type: "abort", sessionId: selectedSession });
    return send("Запрос на остановку задачи отправлен.");
  }
  if (pendingNewSessionInstance) {
    if (localModelLeased()) { pendingNewSessionInstance = null; saveBridgeState(); return send(remoteLeaseMessage); }
    const target = instances.get(pendingNewSessionInstance);
    pendingNewSessionInstance = null;
    if (!target) return send("Проект отключился. Выберите его снова через /projects.");
    queue(target.id, { type: "new_session", prompt: text, agent: "team-lead", mode: modeFromText(text) });
    return send(`Создаю новую основную сессию Team Lead в проекте ${target.projectName}…`);
  }
  if (hasBlockingInteraction()) return send("Сейчас открыт вопрос или запрос разрешения. Сначала ответьте на него кнопкой или ответом на соответствующее сообщение; затем обычный текст снова продолжит Team Lead.");
  if (!selectedSession) return send("Сначала создайте основную сессию через /new или выберите её через /sessions.");
  if (localModelLeased()) return send(remoteLeaseMessage);
  const result = enqueuePrompt(instance.id, { type: "prompt", sessionId: selectedSession, prompt: text, agent: "team-lead" });
  await send(result.queued ? `🕓 Team Lead занят. Сообщение добавлено в очередь · позиция ${result.position}.` : "Сообщение передано Team Lead.");
}

async function handleCallback(query) {
  if (String(query.from?.id) !== String(config.allowedUserId) || String(query.message?.chat?.id) !== String(config.allowedChatId) || query.message?.chat?.type !== "private") return answerCallback(query.id, "Доступ запрещён");
  const match = /^bf:([a-f0-9]+):(\w+)$/.exec(query.data || "");
  if (!match) return answerCallback(query.id, "Некорректная кнопка");
  const item = callbacks.get(match[1]);
  if (!item || item.used || item.expiresAt < Date.now()) return answerCallback(query.id, "Запрос уже закрыт или истёк");
  const action = match[2];
  if (item.kind === "menu") {
    item.used = true;
    if (action === "projects") { await showProjects(); return answerCallback(query.id, "Проекты"); }
    if (action === "sessions") { await showSessions(); return answerCallback(query.id, "Сессии"); }
    if (action === "status") { await showStatus(); return answerCallback(query.id, "Статус"); }
    if (action === "model") { await showModelStatus(); return answerCallback(query.id, "Состояние модели"); }
    if (action === "files") { await showFiles(); return answerCallback(query.id, "Файлы"); }
    if (action === "profiles") { await showProfiles(); return answerCallback(query.id, "Профили"); }
    if (action === "fullaccess") { await showFullAccess(); return answerCallback(query.id, "Полный доступ"); }
    if (action === "clear") {
      const token = newCallback({ kind: "clear_chat", anchorMessageId: Number(query.message?.message_id || 0) }, 2 * 60 * 1000);
      await send("⚠️ Очистить последние доступные сообщения в чате? Telegram разрешает удалить сообщения не старше 48 часов. После очистки останется только новое служебное сообщение.", { inline_keyboard: [[{ text: "🧹 Очистить чат", callback_data: `bf:${token}:confirm` }, { text: "Отмена", callback_data: `bf:${token}:cancel` }]] });
      return answerCallback(query.id, "Требуется подтверждение");
    }
    if (action === "messages") {
      const instance = currentInstance();
      if (!instance || !selectedSession) return answerCallback(query.id, "Сначала выберите сессию");
      queue(instance.id, { type: "list_messages", sessionId: selectedSession });
      return answerCallback(query.id, "Запрашиваю историю");
    }
    if (action === "worktrees") {
      const instance = currentInstance();
      if (!instance) return answerCallback(query.id, "Сначала выберите проект");
      queue(instance.id, { type: "list_worktrees" });
      return answerCallback(query.id, "Запрашиваю worktree");
    }
    if (action === "console") { await startConsole(); return answerCallback(query.id, "BeeForge запускается"); }
    if (action === "modelstop" || action === "opencodeclose" || action === "consoleclose" || action === "closeall") {
      const target = action === "modelstop" ? "model" : action === "opencodeclose" ? "opencode" : action === "consoleclose" ? "console" : "all";
      await requestLifecycleAction(target);
      return answerCallback(query.id, "Подтвердите действие");
    }
    if (action === "launch") {
      const directory = selectedDirectory || currentInstance()?.directory || "";
      if (!directory) return answerCallback(query.id, "Сначала выберите проект");
      await startLastModel(directory);
      return answerCallback(query.id, "Запуск начат");
    }
    if (action === "mute" || action === "unmute") {
      muted = action === "mute";
      saveBridgeState();
      audit("mute", { value: muted, userId: query.from.id });
      await send(muted ? "Обычные уведомления приглушены. Вопросы, разрешения и ошибки останутся активны." : "Обычные уведомления снова включены.", mainMenuKeyboard());
      return answerCallback(query.id, muted ? "Уведомления приглушены" : "Уведомления включены");
    }
    if (action === "new") {
      const instance = currentInstance();
      if (!instance) return answerCallback(query.id, "Сначала откройте разрешённый проект");
      pendingProjectCreation = null;
      pendingNewSessionInstance = instance.id;
      saveBridgeState();
      await send(`Создание новой основной сессии Team Lead в проекте ${instance.projectName}.\nОтправьте следующим сообщением текст задачи.`);
      return answerCallback(query.id, "Жду текст задачи");
    }
  }
  if (item.kind === "full_access_menu") {
    item.used = true;
    if (action === "enable") { await requestFullAccessEnable(); return answerCallback(query.id, "Требуется подтверждение"); }
    return answerCallback(query.id, "Отменено");
  }
  if (item.kind === "full_access_first") {
    item.used = true;
    if (action === "cancel") return answerCallback(query.id, "Отменено");
    const token = newCallback({ kind: "full_access_final" }, 60 * 1000);
    await send("🚨 Критическое подтверждение\n\nПосле включения агенты смогут работать без системных запросов разрешения от имени текущего пользователя Windows. Подтвердите в течение 60 секунд.", { inline_keyboard: [[
      { text: "✅ Подтверждаю полный доступ", callback_data: `bf:${token}:confirm` },
      { text: "Отмена", callback_data: `bf:${token}:cancel` },
    ]] });
    return answerCallback(query.id, "Подтвердите ещё раз");
  }
  if (item.kind === "full_access_final") {
    item.used = true;
    if (action === "cancel") return answerCallback(query.id, "Отменено");
    await answerCallback(query.id, "Включаю полный доступ…");
    await executeFullAccessAction(true, query.from.id);
    return;
  }
  if (item.kind === "full_access_disable") {
    item.used = true;
    await answerCallback(query.id, "Восстанавливаю обычный режим…");
    await executeFullAccessAction(false, query.from.id);
    return;
  }
  if (item.kind === "lifecycle") {
    item.used = true;
    saveBridgeState();
    if (action === "cancel") {
      audit("lifecycle_cancelled", { target: item.target, userId: query.from.id });
      await send("Действие отменено.", mainMenuKeyboard());
      return answerCallback(query.id, "Отменено");
    }
    if (action === "confirm") {
      await answerCallback(query.id, "Выполняю…");
      await executeLifecycleAction(item.target, query.from.id);
      return;
    }
  }
  if (item.kind === "clear_chat") {
    item.used = true;
    if (action === "cancel") return answerCallback(query.id, "Очистка отменена");
    await answerCallback(query.id, "Очищаю чат…");
    await clearRecentTelegramChat(Math.max(Number(item.anchorMessageId || 0), Number(query.message?.message_id || 0)));
    return;
  }
  if (item.kind === "permission") {
    if (action === "details") {
      await send(`ℹ️ Детали запроса разрешения\n\n${cleanText(item.detail || "Дополнительные сведения отсутствуют.", 3200)}`);
      return answerCallback(query.id, "Подробности отправлены");
    }
    if (action === "reject") {
      const requestKey = `permission:${item.instanceId}:${item.requestId}`;
      item.used = true; queue(item.instanceId, { type: "permission_reply", sessionId: item.sessionId, requestId: item.requestId, api: item.api, reply: "reject", callbackToken: match[1], requestKey });
      audit("permission", { decision: "reject", sessionId: item.sessionId, userId: query.from.id });
      return answerCallback(query.id, "Отправляю отказ в OpenCode");
    }
    if ((action === "allow" || action === "always") && item.critical) {
      item.used = true;
      const confirm = newCallback({ ...item, used: false, critical: false }, 60 * 1000);
      openRequests.set(`permission:${item.instanceId}:${item.requestId}`, confirm);
      const label = action === "always" ? "Подтверждаю: разрешить всегда" : "Подтверждаю одноразово";
      await send("⚠️ Критическое действие. Подтвердите ещё раз в течение 60 секунд.", { inline_keyboard: [[{ text: label, callback_data: `bf:${confirm}:${action}` }, { text: "Отмена", callback_data: `bf:${confirm}:reject` }]] });
      return answerCallback(query.id, "Требуется второе подтверждение");
    }
    if (action === "allow" || action === "always") {
      const reply = action === "always" ? "always" : "once";
      const requestKey = `permission:${item.instanceId}:${item.requestId}`;
      item.used = true; queue(item.instanceId, { type: "permission_reply", sessionId: item.sessionId, requestId: item.requestId, api: item.api, reply, callbackToken: match[1], requestKey });
      audit("permission", { decision: reply, sessionId: item.sessionId, userId: query.from.id });
      return answerCallback(query.id, reply === "always" ? "Отправляю правило в OpenCode" : "Отправляю разрешение в OpenCode");
    }
  }
  if (item.kind === "question" && action === "answer") {
    const requestKey = `question:${item.instanceId}:${item.requestId}`;
    item.used = true; queue(item.instanceId, { type: "question_reply", sessionId: item.sessionId, requestId: item.requestId, api: item.api, answer: item.answer, callbackToken: match[1], requestKey });
    return answerCallback(query.id, "Отправляю ответ в OpenCode");
  }
  if (item.kind === "question_text" && action === "text") {
    item.used = true; return answerCallback(query.id, "Ответьте текстом на сообщение с вопросом");
  }
  if (item.kind === "select_project" && action === "select") {
    item.used = true;
    const connected = item.instanceId ? instances.get(item.instanceId) : null;
    selectedInstance = connected?.id || null;
    selectedDirectory = connected?.directory || path.win32.resolve(item.directory);
    selectedSession = null;
    pendingNewSessionInstance = null;
    pendingProjectCreation = null;
    saveBridgeState();
    if (connected) return answerCallback(query.id, `Выбран ${connected.projectName}`);
    await send(`Выбран проект ${item.projectName || path.win32.basename(selectedDirectory)}.\nВыберите способ запуска:`, projectActionKeyboard(selectedDirectory));
    return answerCallback(query.id, "Проект выбран");
  }
  if (item.kind === "project_action") {
    item.used = true;
    if (action === "launch") { await startLastModel(item.directory); return answerCallback(query.id, "Запуск модели начат"); }
    if (action === "open") {
      if (localModelLeased()) { await send(remoteLeaseMessage); return answerCallback(query.id, "Модель передана ноутбуку"); }
      const opened = launchOpenCode(item.directory);
      await send(opened ? "✅ OpenCode открыт с выбранным проектом." : "❌ OpenCode.exe не найден.");
      return answerCallback(query.id, opened ? "OpenCode запускается" : "OpenCode не найден");
    }
  }
  if (item.kind === "file_browser") {
    item.used = true;
    const instance = instances.get(item.instanceId) || currentInstance();
    if (!instance) return answerCallback(query.id, "Проект отключён");
    if (action === "open") { await showFiles(item.relative); return answerCallback(query.id, "Каталог открыт"); }
    if (action === "send") {
      try { await sendProjectFile(instance.directory, item.relative); return answerCallback(query.id, "Файл отправлен"); }
      catch (error) { await send(`❌ Не удалось отправить файл\n${cleanText(error.message, 1200)}`); return answerCallback(query.id, "Ошибка отправки"); }
    }
  }
  if (item.kind === "profile" && action === "select") {
    item.used = true;
    const confirm = newCallback({ kind: "profile_confirm", profileId: item.profileId, profileName: item.profileName }, 2 * 60 * 1000);
    await send(`⚠️ Запустить профиль «${item.profileName}»?\nЕсли сейчас работает другая модель, она будет безопасно выгружена. OpenCode и Telegram Bridge останутся работать.`, { inline_keyboard: [[{ text: "✅ Запустить профиль", callback_data: `bf:${confirm}:confirm` }, { text: "Отмена", callback_data: `bf:${confirm}:cancel` }]] });
    return answerCallback(query.id, "Требуется подтверждение");
  }
  if (item.kind === "profile_confirm") {
    item.used = true;
    if (action === "cancel") return answerCallback(query.id, "Отменено");
    await answerCallback(query.id, "Запускаю профиль");
    await startLastModel(selectedDirectory || currentInstance()?.directory || "", item.profileId);
    return;
  }
  if (item.kind === "history") {
    if (action === "fork") {
      item.used = true; queue(item.instanceId, { type: "fork_session", sessionId: item.sessionId, messageId: item.messageId, mode: sessions.get(item.sessionId)?.mode || "FAST" });
      return answerCallback(query.id, "Создаю fork");
    }
    if (action === "revert") {
      item.used = true;
      const confirm = newCallback({ kind: "history_revert", instanceId: item.instanceId, sessionId: item.sessionId, messageId: item.messageId }, 60 * 1000);
      await send("⚠️ Критический откат может перезаписать текущие файлы проекта. Убедитесь, что важные изменения сохранены. Подтвердите ещё раз в течение 60 секунд.", { inline_keyboard: [[{ text: "✅ Подтверждаю откат", callback_data: `bf:${confirm}:confirm` }, { text: "Отмена", callback_data: `bf:${confirm}:cancel` }]] });
      return answerCallback(query.id, "Нужно второе подтверждение");
    }
  }
  if (item.kind === "history_revert") {
    item.used = true;
    if (action === "cancel") return answerCallback(query.id, "Откат отменён");
    queue(item.instanceId, { type: "revert_session", sessionId: item.sessionId, messageId: item.messageId });
    audit("session_revert", { sessionId: item.sessionId, messageId: item.messageId, userId: query.from.id });
    return answerCallback(query.id, "Отправляю откат OpenCode");
  }
  if (item.kind === "worktree") {
    if (action === "open") {
      item.used = true; persistAllowedProject(item.directory); launchOpenCode(item.directory);
      return answerCallback(query.id, "Открываю worktree");
    }
    if (action === "remove") {
      item.used = true;
      const confirm = newCallback({ kind: "worktree_remove", instanceId: item.instanceId, directory: item.directory, name: item.name }, 60 * 1000);
      await send(`⚠️ OpenCode удалит worktree «${item.name}» и связанную ветку. Подтвердите ещё раз в течение 60 секунд.`, { inline_keyboard: [[{ text: "✅ Подтверждаю удаление", callback_data: `bf:${confirm}:confirm` }, { text: "Отмена", callback_data: `bf:${confirm}:cancel` }]] });
      return answerCallback(query.id, "Нужно второе подтверждение");
    }
  }
  if (item.kind === "worktree_remove") {
    item.used = true;
    if (action === "cancel") return answerCallback(query.id, "Удаление отменено");
    queue(item.instanceId, { type: "remove_worktree", directory: item.directory });
    audit("worktree_remove", { directory: item.directory, userId: query.from.id });
    return answerCallback(query.id, "Удаление отправлено OpenCode");
  }
  if (item.kind === "select_session" && action === "select") {
    item.used = true; selectedInstance = item.instanceId; selectedDirectory = instances.get(item.instanceId)?.directory || selectedDirectory; selectedSession = item.sessionId; saveBridgeState();
    queue(item.instanceId, { type: "select_session", sessionId: item.sessionId, silent: true });
    return answerCallback(query.id, "Сессия выбрана");
  }
  return answerCallback(query.id, "Действие недоступно");
}

async function telegramLoop() {
  while (!stopping) {
    try {
      const updates = await telegram("getUpdates", { offset: telegramOffset, timeout: 25, allowed_updates: ["message", "callback_query"] });
      for (const update of updates) {
        // Persist consumption before dispatch so a bridge crash cannot execute a
        // Telegram control command twice. Unacknowledged commands can be retried.
        telegramOffset = Math.max(telegramOffset, update.update_id + 1);
        saveBridgeState();
        if (update.message) await handleMessage(update.message);
        if (update.callback_query) await handleCallback(update.callback_query);
      }
      pruneInstances();
      pruneTransientState();
      await expireCommands();
      setStatus("connected", `${instances.size} OpenCode instance(s)`);
    } catch (error) {
      setStatus("error", cleanText(error.message));
      audit("telegram_error", { error: error.message });
      await new Promise((resolve) => setTimeout(resolve, 3000));
    }
  }
}

function readBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = []; let size = 0;
    request.on("data", (chunk) => { size += chunk.length; if (size > 256 * 1024) request.destroy(new Error("Body too large")); else chunks.push(chunk); });
    request.on("end", () => { try { resolve(chunks.length ? JSON.parse(Buffer.concat(chunks).toString("utf8")) : {}); } catch (error) { reject(error); } });
    request.on("error", reject);
  });
}

function json(response, status, value) {
  const body = JSON.stringify(value); response.writeHead(status, { "content-type": "application/json; charset=utf-8", "content-length": Buffer.byteLength(body) }); response.end(body);
}

const server = http.createServer(async (request, response) => {
  try {
    if (request.socket.remoteAddress !== "127.0.0.1" && request.socket.remoteAddress !== "::ffff:127.0.0.1") return json(response, 403, { error: "loopback only" });
    if (request.headers["x-beeforge-key"] !== bridgeKey) return json(response, 401, { error: "unauthorized" });
    const url = new URL(request.url, `http://127.0.0.1:${config.bridgePort}`);
    if (request.method === "GET" && url.pathname === "/health") return json(response, 200, { ok: true, instances: instances.size });
    if (request.method === "POST" && url.pathname === "/diagnostics/session-list") {
      const instance = currentInstance();
      if (!instance) return json(response, 409, { error: "no connected OpenCode instance" });
      const command = queue(instance.id, { type: "list_sessions", diagnostic: true });
      audit("diagnostic_requested", { commandId: command.id, type: command.type, instanceId: instance.id });
      return json(response, 202, { ok: true, commandId: command.id });
    }
    if (request.method === "POST" && url.pathname === "/register") {
      const body = await readBody(request);
      if (!body.instanceId || !isAllowedProject(body.directory)) { audit("registration_denied", { directory: body.directory }); return json(response, 403, { error: "project not allowed" }); }
      const item = { id: cleanText(body.instanceId, 100), directory: path.win32.resolve(body.directory), projectName: cleanText(body.projectName || path.win32.basename(body.directory), 100), pid: Number(body.pid || 0), lastSeen: Date.now() };
      // A successful plugin registration proves that this directory is open in
      // OpenCode. Persist it in both stores so it survives bridge/app restarts
      // and remains visible in the OpenCode project sidebar.
      persistAllowedProject(item.directory);
      ensureOpenCodeProjectRegistered(item.directory, false);
      for (const [id, existing] of instances) {
        if (id !== item.id && canonical(existing.directory) === canonical(item.directory)) {
          instances.delete(id);
          commands.delete(id);
          if (selectedInstance === id) selectedInstance = item.id;
        }
      }
      const previous = instances.get(item.id);
      instances.set(item.id, item);
      const matchesSelectedDirectory = selectedDirectory && canonical(selectedDirectory) === canonical(item.directory);
      if (matchesSelectedDirectory || (!selectedDirectory && !selectedInstance)) {
        selectedInstance = item.id;
        selectedDirectory = item.directory;
        saveBridgeState();
      }
      if (!previous || previous.pid !== item.pid) audit("instance_registered", { instanceId: item.id, directory: item.directory, pid: item.pid });
      if (!previous || previous.pid !== item.pid) {
        queue(item.id, { type: "list_sessions", silent: true });
        queue(item.id, { type: "sync_pending", silent: true });
      }
      setStatus("connected", `${instances.size} OpenCode instance(s)`); schedulePinnedStatus(); return json(response, 200, { ok: true });
    }
    if (request.method === "POST" && url.pathname === "/event") { const body = await readBody(request); await handleEvent(body); return json(response, 200, { ok: true }); }
    if (request.method === "POST" && url.pathname === "/result") {
      const body = await readBody(request); const pending = pendingCommands.get(body.commandId); pendingCommands.delete(body.commandId); audit("command_result", { commandId: body.commandId, ok: body.ok, error: body.error || "" });
      if (body.ok) closeInteractiveCommand(pending);
      if (body.type === "new_session" && body.ok) { selectedInstance = body.instanceId; selectedDirectory = instances.get(body.instanceId)?.directory || selectedDirectory; selectedSession = body.sessionId; saveBridgeState(); await send(`✅ Сессия Team Lead создана\n${body.projectName}\nID: ${body.sessionId}`); }
      else if (body.type === "list_messages" && body.ok) {
        const rows = [];
        const lines = [];
        for (const message of (body.messages || []).slice(-10)) {
          lines.push(`${message.role === "user" ? "👤" : "🤖"} ${cleanText(message.preview, 260)}`);
          if (message.role === "user") {
            const fork = newCallback({ kind: "history", instanceId: body.instanceId, sessionId: pending?.sessionId, messageId: message.id });
            const revert = newCallback({ kind: "history", instanceId: body.instanceId, sessionId: pending?.sessionId, messageId: message.id });
            rows.push([{ text: `↪ Fork · ${cleanText(message.preview, 28)}`, callback_data: `bf:${fork}:fork` }, { text: "↩ Откат", callback_data: `bf:${revert}:revert` }]);
          }
        }
        await send(lines.length ? `🕘 Последние сообщения основной сессии\n\n${lines.join("\n\n")}` : "В сессии нет сообщений.", rows.length ? { inline_keyboard: rows.slice(-8) } : undefined);
      }
      else if (body.type === "session_overview" && body.ok) {
        const item = sessions.get(pending?.sessionId);
        if (item) {
          const store = readProfiles();
          const active = store.profiles.find((profile) => profile.id === store.lastGoodProfileId) || store.profiles.find((profile) => profile.id === store.activeProfileId);
          const context = Number(active?.context || 0);
          item.contextPercent = context > 0 ? Math.min(100, Math.round(Number(body.tokenCount || 0) * 100 / context)) : undefined;
          item.changedFiles = Array.isArray(body.changedFiles) ? body.changedFiles : [];
          item.model = body.model || item.model;
          sessions.set(item.id, item);
        }
        schedulePinnedStatus(50);
      }
      else if (body.type === "fork_session" && body.ok) {
        selectedInstance = body.instanceId; selectedDirectory = instances.get(body.instanceId)?.directory || selectedDirectory; selectedSession = body.sessionId; saveBridgeState();
        await send(`✅ Создана новая основная сессия Team Lead из выбранной точки\n${cleanText(body.title || body.sessionId, 200)}`);
      }
      else if (body.type === "revert_session" && body.ok) await send("✅ OpenCode выполнил откат к выбранному сообщению. Проверьте Git diff перед продолжением.");
      else if (body.type === "list_worktrees" && body.ok) {
        const rows = [];
        for (const worktree of (body.worktrees || []).slice(0, 20)) {
          const open = newCallback({ kind: "worktree", instanceId: body.instanceId, directory: worktree.directory, name: worktree.name });
          const remove = newCallback({ kind: "worktree", instanceId: body.instanceId, directory: worktree.directory, name: worktree.name });
          rows.push([{ text: `📂 ${cleanText(worktree.name || path.win32.basename(worktree.directory), 32)}`, callback_data: `bf:${open}:open` }, { text: "🗑 Удалить", callback_data: `bf:${remove}:remove` }]);
        }
        await send(rows.length ? "Git worktree выбранного проекта:" : "У проекта нет управляемых OpenCode worktree. Создать: /worktree create Имя", rows.length ? { inline_keyboard: rows } : undefined);
      }
      else if (body.type === "create_worktree" && body.ok) {
        const directory = body.worktree?.directory || "";
        if (directory) { persistAllowedProject(directory); ensureOpenCodeProjectRegistered(directory); }
        await send(`✅ Worktree создан\n${cleanText(directory || JSON.stringify(body.worktree || {}), 1000)}${directory ? "\nМожно открыть его кнопкой ниже." : ""}`, directory ? projectActionKeyboard(directory) : undefined);
      }
      else if (body.type === "remove_worktree" && body.ok) await send("✅ OpenCode удалил worktree и связанную ветку.");
      else if (body.type === "list_sessions" && body.ok) {
        const mainSessions = (body.sessions || []).slice(0, 20);
        for (const session of mainSessions) {
          const old = sessions.get(session.id) || {};
          sessions.set(session.id, { ...old, id: session.id, instanceId: body.instanceId, directory: instances.get(body.instanceId)?.directory || old.directory, projectName: body.projectName || instances.get(body.instanceId)?.projectName || old.projectName, title: session.title || old.title, parentID: "", updatedAt: old.updatedAt || Date.now() });
        }
        const resultDirectory = instances.get(body.instanceId)?.directory || "";
        const matchesSelectedProject = (!selectedDirectory || canonical(selectedDirectory) === canonical(resultDirectory))
          && (!selectedInstance || selectedInstance === body.instanceId);
        if (!selectedSession && mainSessions.length === 1 && matchesSelectedProject) {
          selectedInstance = body.instanceId;
          selectedDirectory = instances.get(body.instanceId)?.directory || selectedDirectory;
          selectedSession = mainSessions[0].id;
          saveBridgeState();
          await send(`✅ Основная сессия восстановлена\n${cleanText(mainSessions[0].title || mainSessions[0].id, 100)}`);
        }
        if (!pending?.silent) {
          const rows = mainSessions.map((s) => { const token = newCallback({ kind: "select_session", instanceId: body.instanceId, sessionId: s.id }); return [{ text: cleanText(s.title || s.id, 48), callback_data: `bf:${token}:select` }]; });
          await send(rows.length ? "Выберите сессию:" : "В проекте нет сессий.", rows.length ? { inline_keyboard: rows } : undefined);
        }
      } else if (body.type === "permission_reply" && body.ok) await send("✅ Решение по разрешению принято OpenCode.");
      else if (body.type === "question_reply" && body.ok) {
        if (pending?.instanceId && pending?.requestId) pendingQuestions.delete(`${pending.instanceId}:${pending.requestId}`);
        await send("✅ Ответ принят OpenCode.");
      } else if (body.type === "sync_pending" && body.ok) {
        for (const item of body.permissions || []) await handleEvent({ kind: "permission", api: "v2", instanceId: body.instanceId, sessionId: item.sessionId, requestId: item.requestId, permission: item.action, detail: cleanText(JSON.stringify({ action: item.action, resources: item.resources, save: item.save, metadata: item.metadata }), 1700) });
        for (const item of body.questions || []) {
          const first = item.questions?.[0] || {};
          await handleEvent({ kind: "question", api: "v2", instanceId: body.instanceId, sessionId: item.sessionId, requestId: item.requestId, question: first.question || "Агент ожидает ответ", options: first.options || [], createdAt: Date.now() });
        }
      } else if (!body.ok) {
        const reopened = reopenInteractiveCommand(pending);
        await send(`❌ Команда Telegram не выполнена\n${cleanText(body.error, 1800)}${reopened ? "\n\nКнопка запроса снова активна — действие можно повторить." : ""}`);
      }
      schedulePinnedStatus();
      return json(response, 200, { ok: true });
    }
    if (request.method === "GET" && url.pathname === "/commands") {
      const id = cleanText(url.searchParams.get("instanceId"), 100); const instance = instances.get(id);
      if (!instance) return json(response, 404, { error: "unknown instance" });
      instance.lastSeen = Date.now(); const list = commands.get(id) || []; commands.set(id, []);
      for (const command of list) {
        const pending = pendingCommands.get(command.id); if (pending) pending.deliveredAt = Date.now();
        audit("command_delivered", { instanceId: id, commandId: command.id, type: command.type });
      }
      return json(response, 200, { commands: list });
    }
    return json(response, 404, { error: "not found" });
  } catch (error) { audit("http_error", { error: error.message }); json(response, 500, { error: "internal error" }); }
});

process.on("uncaughtException", (error) => {
  try { audit("uncaught_exception", { error: error?.stack || error?.message || error }); } catch {}
  try { setStatus("error", cleanText(error?.message || error)); } catch {}
  process.stderr.write(`${error?.stack || error}\n`);
  clearOwnPid(); process.exit(1);
});
process.on("unhandledRejection", (error) => {
  try { audit("unhandled_rejection", { error: error?.stack || error?.message || error }); } catch {}
  try { setStatus("error", cleanText(error?.message || error)); } catch {}
  process.stderr.write(`${error?.stack || error}\n`);
  clearOwnPid(); process.exit(1);
});

process.on("exit", clearOwnPid);
const scheduledTaskTimer = setInterval(() => { void runScheduledTasks().catch((error) => audit("scheduled_task_error", { error: error.message })); }, 30000);
scheduledTaskTimer.unref();
server.listen(Number(config.bridgePort), "127.0.0.1", () => {
  writePid(); setStatus("connected", "Telegram connected; waiting for OpenCode"); audit("bridge_started", { port: config.bridgePort });
  telegramLoop();
  schedulePinnedStatus(2500);
  void runScheduledTasks().catch((error) => audit("scheduled_task_error", { error: error.message }));
});
for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => { stopping = true; setStatus("stopped", signal); server.close(() => { clearOwnPid(); process.exit(0); }); });
