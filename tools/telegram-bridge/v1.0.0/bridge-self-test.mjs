import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const root = fs.mkdtempSync(path.join(os.tmpdir(), "beeforge-telegram-test-"));
const realConfig = JSON.parse(fs.readFileSync("C:\\AI\\BeeForge AI Console\\config\\telegram.json", "utf8"));
const port = 47756;
const configPath = path.join(root, "telegram.json");
const keyPath = path.join(root, "bridge.key");
const statusPath = path.join(root, "status.json");
const pidPath = path.join(root, "bridge.pid");
const logPath = path.join(root, "bridge.log");
const projectRoot = path.join(root, "projects");
const attachmentProject = path.join(projectRoot, "AttachmentProject");
const openCodeDataPath = path.join(root, "opencode.global.dat");
const profilesPath = path.join(root, "profiles.json");
fs.mkdirSync(projectRoot);
fs.mkdirSync(attachmentProject);
fs.writeFileSync(configPath, JSON.stringify({ ...realConfig, bridgePort: port, allowedProjects: ["C:\\BridgeTest", "C:\\OfflineProject"], allowPreviouslyOpenedProjects: true, defaultProjectRoot: projectRoot }), "utf8");
fs.writeFileSync(keyPath, "bridge-self-test-key", "utf8");
fs.writeFileSync(openCodeDataPath, JSON.stringify({ server: JSON.stringify({ list: [], projects: { local: [{ worktree: "C:\\ExistingProject", expanded: true }] }, lastProject: { local: "C:\\ExistingProject" }, recentlyClosed: {} }) }), "utf8");
fs.writeFileSync(profilesPath, `\uFEFF${JSON.stringify({ activeProfileId: "bom-profile", lastGoodProfileId: "bom-profile", profiles: [{ id: "bom-profile", name: "BOM profile" }] })}`, "utf8");
process.env.BEEFORGE_BRIDGE_SELF_TEST = "1";
process.env.BEEFORGE_OPENCODE_GLOBAL_DATA = openCodeDataPath;
process.env.BEEFORGE_PROFILES_PATH = profilesPath;

const sentMessages = [];
const sentUploads = [];
const deletedMessageBatches = [];
let pendingUpdates = [];
let updateId = 1;
globalThis.fetch = async (url, options = {}) => {
  const target = String(url);
  if (target.includes("api.telegram.org/file/bot")) return new Response(Buffer.from("telegram attachment body", "utf8"), { status: 200, headers: { "content-length": "24", "content-type": "text/plain" } });
  if (!target.includes("api.telegram.org")) throw new Error(`Unexpected external fetch: ${target}`);
  const method = target.split("/").pop();
  const body = typeof options.body === "string" ? JSON.parse(options.body) : {};
  if (method === "sendDocument" || method === "sendPhoto") {
    sentUploads.push({ method, body: options.body });
    const uploaded = options.body?.get?.(method === "sendPhoto" ? "photo" : "document");
    if (uploaded?.name === "concurrent-screenshot.png") await new Promise((resolve) => setTimeout(resolve, 80));
    return Response.json({ ok: true, result: { message_id: 900 + sentUploads.length, chat: { id: Number(realConfig.allowedChatId) } } });
  }
  if (method === "deleteMessages") {
    deletedMessageBatches.push(body.message_ids || []);
    return Response.json({ ok: true, result: true });
  }
  if (method === "getUpdates") {
    await new Promise((resolve) => setTimeout(resolve, 25));
    const result = pendingUpdates.splice(0);
    return Response.json({ ok: true, result });
  }
  if (method === "sendMessage") {
    sentMessages.push(body);
    return Response.json({ ok: true, result: { message_id: sentMessages.length, chat: { id: Number(realConfig.allowedChatId) } } });
  }
  if (method === "editMessageText" || method === "pinChatMessage") return Response.json({ ok: true, result: true });
  if (method === "getFile") return Response.json({ ok: true, result: { file_id: body.file_id, file_path: "documents/sample.txt", file_size: 24 } });
  if (method === "answerCallbackQuery") return Response.json({ ok: true, result: true });
  throw new Error(`Unexpected Telegram method: ${method}`);
};

process.argv = [process.execPath, "bridge.mjs", "--config", configPath, "--token-file", "C:\\AI\\BeeForge AI Console\\secrets\\telegram-token.dpapi", "--key-file", keyPath, "--status", statusPath, "--pid", pidPath, "--log", logPath];
await import(`./bridge.mjs?selftest=${Date.now()}`);

const headers = { "content-type": "application/json", "x-beeforge-key": "bridge-self-test-key" };
async function local(route, method = "GET", body) {
  const response = await fetchLocal(`http://127.0.0.1:${port}${route}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  if (!response.ok) throw new Error(`${route}: HTTP ${response.status}`);
  return response.json();
}
const fetchLocal = (url, options) => import("node:http").then(({ request }) => new Promise((resolve, reject) => {
  const target = new URL(url);
  const req = request({ hostname: target.hostname, port: target.port, path: target.pathname + target.search, method: options.method, headers: options.headers }, (res) => {
    const chunks = [];
    res.on("data", (chunk) => chunks.push(chunk));
    res.on("end", () => resolve(new Response(Buffer.concat(chunks), { status: res.statusCode, headers: res.headers })));
  });
  req.on("error", reject);
  if (options.body) req.write(options.body);
  req.end();
}));

for (let attempt = 0; attempt < 40; attempt++) {
  try { if ((await local("/health")).ok) break; } catch {}
  await new Promise((resolve) => setTimeout(resolve, 25));
}
await local("/register", "POST", { instanceId: "instance-1", directory: "C:\\BridgeTest", projectName: "BridgeTest", pid: process.pid });
await local("/register", "POST", { instanceId: "instance-2", directory: "C:\\PreviouslyOpened", projectName: "PreviouslyOpened", pid: process.pid });
const registeredConfig = JSON.parse(fs.readFileSync(configPath, "utf8"));
const registeredOpenCodeOuter = JSON.parse(fs.readFileSync(openCodeDataPath, "utf8"));
const registeredOpenCodeServer = JSON.parse(registeredOpenCodeOuter.server);
if (!registeredConfig.allowedProjects.some((item) => path.win32.resolve(item).toLowerCase() === "c:\\previouslyopened")) throw new Error("An opened OpenCode project was not persisted in the BeeForge allowlist");
if (!registeredOpenCodeServer.projects.local.some((item) => path.win32.resolve(item.worktree).toLowerCase() === "c:\\previouslyopened")) throw new Error("An opened OpenCode project was not persisted in the OpenCode sidebar");
await local("/event", "POST", { instanceId: "instance-2", kind: "prompted", sessionId: "main-2", parentID: "", agent: "team-lead", mode: "FAST" });
const focusedState = JSON.parse(fs.readFileSync(path.join(root, "bridge-state.json"), "utf8"));
if (focusedState.selectedDirectory !== "C:\\PreviouslyOpened" || focusedState.selectedSession !== "main-2") throw new Error("Main prompt did not move project focus");
await local("/event", "POST", { instanceId: "instance-1", kind: "permission", api: "v2", sessionId: "main-1", requestId: "permission-1", agent: "Software Engineer", permission: "bash", detail: "npm test token=super-secret-value Bearer abc.def.ghi" });

let alwaysCallback = "";
for (let attempt = 0; attempt < 40 && !alwaysCallback; attempt++) {
  const keyboard = sentMessages.flatMap((item) => item.reply_markup?.inline_keyboard || []).flat();
  alwaysCallback = keyboard.find((button) => button.text?.includes("Разрешить всегда"))?.callback_data || "";
  if (!alwaysCallback) await new Promise((resolve) => setTimeout(resolve, 25));
}
if (!alwaysCallback) throw new Error("Always button was not rendered");
if (sentMessages.some((item) => String(item.text || "").includes("super-secret-value") || String(item.text || "").includes("abc.def.ghi"))) throw new Error("Sensitive permission detail leaked to Telegram");
pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-1", from: { id: Number(realConfig.allowedUserId) }, message: { chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: alwaysCallback } });

let commands = [];
for (let attempt = 0; attempt < 80 && !commands.length; attempt++) {
  await new Promise((resolve) => setTimeout(resolve, 25));
  commands = (await local("/commands?instanceId=instance-1")).commands || [];
}
const permission = commands.find((item) => item.type === "permission_reply");
if (permission?.reply !== "always") throw new Error("Always callback did not queue reply=always");
await local("/result", "POST", { commandId: permission.id, type: "permission_reply", ok: false, instanceId: "instance-1", error: "simulated SDK failure" });
const callbackToken = alwaysCallback.split(":")[1];
const failedState = JSON.parse(fs.readFileSync(path.join(root, "bridge-state.json"), "utf8"));
if (!failedState.callbacks?.some((row) => row.token === callbackToken && row.item?.used === false)) throw new Error("Failed permission callback was not persisted for retry");
pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-2", from: { id: Number(realConfig.allowedUserId) }, message: { chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: alwaysCallback } });

let retryCommands = [];
for (let attempt = 0; attempt < 80 && !retryCommands.length; attempt++) {
  await new Promise((resolve) => setTimeout(resolve, 25));
  retryCommands = (await local("/commands?instanceId=instance-1")).commands || [];
}
const permissionRetry = retryCommands.find((item) => item.type === "permission_reply");
if (permissionRetry?.reply !== "always" || permissionRetry.id === permission.id) throw new Error("Failed permission command was not reactivated for retry");
await local("/result", "POST", { commandId: permissionRetry.id, type: "permission_reply", ok: true, instanceId: "instance-1" });
if (!sentMessages.some((item) => item.text?.includes("Решение по разрешению принято OpenCode"))) throw new Error("Successful permission was not confirmed to Telegram");
const successfulState = JSON.parse(fs.readFileSync(path.join(root, "bridge-state.json"), "utf8"));
if (successfulState.callbacks?.some((row) => row.token === callbackToken)) throw new Error("Successful permission callback remained active");

const envCleanupMessageStart = sentMessages.length;
await local("/event", "POST", { instanceId: "instance-1", kind: "permission", api: "v2", sessionId: "main-1", requestId: "permission-env-cleanup", agent: "Systems Engineer", permission: "bash", detail: "python sshx.py; Remove-Item Env:\\XRAY_SSH_PASS -ErrorAction SilentlyContinue" });
let envCleanupCallback = "";
for (let attempt = 0; attempt < 40 && !envCleanupCallback; attempt++) {
  const keyboard = sentMessages.slice(envCleanupMessageStart).flatMap((item) => item.reply_markup?.inline_keyboard || []).flat();
  envCleanupCallback = keyboard.find((button) => button.text?.includes("Один раз"))?.callback_data || "";
  if (!envCleanupCallback) await new Promise((resolve) => setTimeout(resolve, 25));
}
if (!envCleanupCallback) throw new Error("Environment cleanup permission button was not rendered");
pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-env-cleanup", from: { id: Number(realConfig.allowedUserId) }, message: { chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: envCleanupCallback } });
let envCleanupCommands = [];
for (let attempt = 0; attempt < 80 && !envCleanupCommands.length; attempt++) {
  await new Promise((resolve) => setTimeout(resolve, 25));
  envCleanupCommands = (await local("/commands?instanceId=instance-1")).commands || [];
}
const envCleanupPermission = envCleanupCommands.find((item) => item.type === "permission_reply" && item.requestId === "permission-env-cleanup");
if (envCleanupPermission?.reply !== "once") throw new Error("Environment-variable cleanup was incorrectly treated as a critical permission");
if (sentMessages.slice(envCleanupMessageStart).some((item) => item.text?.includes("Критическое действие"))) throw new Error("Environment-variable cleanup triggered a second confirmation");
await local("/result", "POST", { commandId: envCleanupPermission.id, type: "permission_reply", ok: true, instanceId: "instance-1" });

const destructiveMessageStart = sentMessages.length;
await local("/event", "POST", { instanceId: "instance-1", kind: "permission", api: "v2", sessionId: "main-1", requestId: "permission-delete", agent: "Systems Engineer", permission: "bash", detail: "Remove-Item C:\\BridgeTest\\important.txt" });
let destructiveCallback = "";
for (let attempt = 0; attempt < 40 && !destructiveCallback; attempt++) {
  const keyboard = sentMessages.slice(destructiveMessageStart).flatMap((item) => item.reply_markup?.inline_keyboard || []).flat();
  destructiveCallback = keyboard.find((button) => button.text?.includes("Один раз"))?.callback_data || "";
  if (!destructiveCallback) await new Promise((resolve) => setTimeout(resolve, 25));
}
if (!destructiveCallback) throw new Error("Destructive permission button was not rendered");
pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-delete", from: { id: Number(realConfig.allowedUserId) }, message: { chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: destructiveCallback } });
for (let attempt = 0; attempt < 80 && !sentMessages.slice(destructiveMessageStart).some((item) => item.text?.includes("Критическое действие")); attempt++) await new Promise((resolve) => setTimeout(resolve, 25));
if (!sentMessages.slice(destructiveMessageStart).some((item) => item.text?.includes("Критическое действие"))) throw new Error("Destructive file removal did not require a second confirmation");

pendingUpdates.push({ update_id: updateId++, message: { message_id: 20, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/start" } });
for (let index = 1; index <= 4; index += 1) {
  await local("/event", "POST", { instanceId: "instance-1", kind: "idle", sessionId: `status-wait-${index}`, parentID: "", agent: "team-lead", status: "idle", finalText: `Готово ${index}` });
}
pendingUpdates.push({ update_id: updateId++, message: { message_id: 201, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/status" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 21, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/projects" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 22, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/mute" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 23, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/unmute" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 231, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/create" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 232, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "DialogProject" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 24, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/create DemoProject" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 25, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/modelstart" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 26, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/launch" } });
pendingUpdates.push({ update_id: updateId++, message: { message_id: 27, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/model" } });
  pendingUpdates.push({ update_id: updateId++, message: { message_id: 28, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/console" } });
  pendingUpdates.push({ update_id: updateId++, message: { message_id: 29, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/closeall" } });
  pendingUpdates.push({ update_id: updateId++, message: { message_id: 30, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/profiles" } });
  pendingUpdates.push({ update_id: updateId++, message: { message_id: 31, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/fullaccess on" } });
let dialogOpenQueued = false;
let lifecycleConfirmQueued = false;
let fullAccessFirstQueued = false;
let fullAccessFinalQueued = false;
let fullAccessDisableQueued = false;
for (let attempt = 0; attempt < 80; attempt++) {
  await new Promise((resolve) => setTimeout(resolve, 25));
  const dialogProjectMessage = sentMessages.find((item) => item.text?.includes("DialogProject") && (item.reply_markup?.inline_keyboard || []).flat().some((button) => button.text?.includes("Только OpenCode")));
  const dialogOpenCallback = (dialogProjectMessage?.reply_markup?.inline_keyboard || []).flat().find((button) => button.text?.includes("Только OpenCode"))?.callback_data;
  if (dialogOpenCallback && !dialogOpenQueued) {
    dialogOpenQueued = true;
    pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-open-dialog-project", from: { id: Number(realConfig.allowedUserId) }, message: { chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: dialogOpenCallback } });
  }
  const lifecycleMessage = sentMessages.find((item) => item.text?.includes("Подтвердите действие") && item.text?.includes("выгрузить модель"));
  const lifecycleConfirm = (lifecycleMessage?.reply_markup?.inline_keyboard || []).flat().find((button) => button.text?.startsWith("✅ Да,"))?.callback_data;
  if (lifecycleConfirm && !lifecycleConfirmQueued) {
    lifecycleConfirmQueued = true;
    pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-lifecycle-all", from: { id: Number(realConfig.allowedUserId) }, message: { chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: lifecycleConfirm } });
  }
  const fullAccessWarning = sentMessages.find((item) => item.text?.includes("Полный доступ отключает системные запросы"));
  const fullAccessFirst = (fullAccessWarning?.reply_markup?.inline_keyboard || []).flat().find((button) => button.text === "Продолжить")?.callback_data;
  if (fullAccessFirst && !fullAccessFirstQueued) {
    fullAccessFirstQueued = true;
    pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-full-access-first", from: { id: Number(realConfig.allowedUserId) }, message: { chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: fullAccessFirst } });
  }
  const fullAccessCritical = sentMessages.find((item) => item.text?.includes("Критическое подтверждение") && item.text?.includes("После включения агенты"));
  const fullAccessFinal = (fullAccessCritical?.reply_markup?.inline_keyboard || []).flat().find((button) => button.text?.includes("Подтверждаю полный доступ"))?.callback_data;
  if (fullAccessFinal && !fullAccessFinalQueued) {
    fullAccessFinalQueued = true;
    pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-full-access-final", from: { id: Number(realConfig.allowedUserId) }, message: { chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: fullAccessFinal } });
  }
  const fullAccessEnabled = sentMessages.some((item) => item.text?.includes("Полный доступ ВКЛЮЧЁН"));
  if (fullAccessEnabled && !fullAccessDisableQueued) {
    fullAccessDisableQueued = true;
    pendingUpdates.push({ update_id: updateId++, message: { message_id: 32, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/fullaccess off" } });
  }
  const hasNew = sentMessages.some((item) => (item.reply_markup?.inline_keyboard || []).flat().some((button) => button.text?.includes("Новая сессия")));
  const projectsListed = sentMessages.some((item) => item.text?.includes("PreviouslyOpened") && item.text?.includes("BridgeTest"));
  const offlineSelectable = sentMessages.some((item) => (item.reply_markup?.inline_keyboard || []).flat().some((button) => button.text?.includes("OfflineProject")));
  const unmuted = sentMessages.some((item) => item.text?.includes("снова включены"));
  const modelMenu = sentMessages.some((item) => (item.reply_markup?.inline_keyboard || []).flat().some((button) => button.text?.includes("Запустить всё")));
  const profilesMenu = sentMessages.some((item) => (item.reply_markup?.inline_keyboard || []).flat().some((button) => button.text?.includes("BOM profile")));
  const modelStart = sentMessages.some((item) => item.text?.includes("Тестовый запуск последней модели"));
  const modelStatus = sentMessages.some((item) => item.text?.includes("🤖 BeeLlama") && item.text?.includes("Qwen38 Daily 162K Q2 - Very FAST"));
  const consoleLaunch = sentMessages.some((item) => item.text?.includes("self-test") && item.text?.includes("PID: 1"));
  const compactStatus = sentMessages.find((item) => item.text?.includes("Ожидают:") && item.text?.includes("BridgeTest:") && item.text?.includes("Роли:"));
  if (!compactStatus || compactStatus.text.includes("Основные сессии:")) throw new Error("Waiting Team Lead sessions were not compacted in /status");
  const lifecycleMenu = sentMessages.some((item) => {
    const rows = item.reply_markup?.inline_keyboard || [];
    const buttons = rows.flat();
    const launchRow = rows.findIndex((row) => row.length === 1 && row[0].text?.includes("Запустить всё"));
    const closeRow = rows.findIndex((row) => row.length === 1 && row[0].text?.includes("Завершить всё"));
    return launchRow >= 0 && closeRow === launchRow + 1
      && !buttons.some((button) => /(?:Выгрузить модель|Закрыть OpenCode|Закрыть BeeForge|Открыть BeeForge Console)/.test(button.text || ""));
  });
  const lifecycleCompleted = sentMessages.some((item) => item.text?.includes("self-test all") && item.text?.includes("Telegram-мост продолжает работать"));
  const fullAccessCompleted = fullAccessEnabled && sentMessages.some((item) => item.text?.includes("Полный доступ выключен"));
  const created = fs.existsSync(path.join(projectRoot, "DemoProject"));
  const dialogCreated = fs.existsSync(path.join(projectRoot, "DialogProject"));
  const dialogOpened = sentMessages.some((item) => item.text?.includes("OpenCode открыт с выбранным проектом"));
  const launchLog = fs.existsSync(logPath) ? fs.readFileSync(logPath, "utf8") : "";
  const dialogDeepLinkLogged = launchLog.includes('"kind":"opencode_launch"') && launchLog.includes("opencode%3A") === false && launchLog.includes("DialogProject") && launchLog.includes("opencode://open-project?directory=");
  const openCodeData = JSON.parse(fs.readFileSync(openCodeDataPath, "utf8"));
  const openCodeServer = JSON.parse(openCodeData.server);
  const dialogRegisteredInOpenCode = path.win32.basename(openCodeServer.projects.local[0]?.worktree || "") === "DialogProject"
    && path.win32.basename(openCodeServer.lastProject?.local || "") === "DialogProject"
    && fs.existsSync(`${openCodeDataPath}.beeforge-backup`);
  const savedConfig = JSON.parse(fs.readFileSync(configPath, "utf8"));
  const persisted = savedConfig.allowedProjects.some((item) => path.win32.basename(item) === "DemoProject");
  const dialogPersisted = savedConfig.allowedProjects.some((item) => path.win32.basename(item) === "DialogProject");
  if (hasNew && projectsListed && offlineSelectable && unmuted && modelMenu && profilesMenu && modelStart && modelStatus && consoleLaunch && compactStatus && lifecycleMenu && lifecycleCompleted && fullAccessCompleted && created && persisted && dialogCreated && dialogPersisted && dialogOpened && dialogDeepLinkLogged && dialogRegisteredInOpenCode) {
    pendingUpdates.push({ update_id: updateId++, message: { message_id: 700, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "/clear" } });
    let clearChatConfirm = "";
    for (let clearAttempt = 0; clearAttempt < 80 && !clearChatConfirm; clearAttempt++) {
      await new Promise((resolve) => setTimeout(resolve, 25));
      const confirmation = sentMessages.find((item) => item.text?.includes("После очистки останется"));
      clearChatConfirm = (confirmation?.reply_markup?.inline_keyboard || []).flat().find((button) => button.text?.includes("Очистить чат"))?.callback_data || "";
    }
    if (!clearChatConfirm) throw new Error("Chat clear confirmation was not rendered");
    pendingUpdates.push({ update_id: updateId++, callback_query: { id: "callback-clear-chat-confirm", from: { id: Number(realConfig.allowedUserId) }, message: { message_id: 701, chat: { id: Number(realConfig.allowedChatId), type: "private" } }, data: clearChatConfirm } });
    for (let clearAttempt = 0; clearAttempt < 80 && !sentMessages.some((item) => item.text?.includes("Чат очищен")); clearAttempt++) await new Promise((resolve) => setTimeout(resolve, 25));
    const deletedIdCount = deletedMessageBatches.reduce((total, batch) => total + batch.length, 0);
    if (!sentMessages.some((item) => item.text?.includes("Чат очищен")) || deletedIdCount !== 701 || !deletedMessageBatches.every((batch) => batch.length <= 100)) throw new Error(`Chat clear did not scan the complete available ID range in confirmed batches: ${deletedIdCount}`);
    const beforeForeignRestore = JSON.parse(fs.readFileSync(path.join(root, "bridge-state.json"), "utf8"));
    await local("/result", "POST", { commandId: "foreign-list", type: "list_sessions", ok: true, instanceId: "instance-2", projectName: "PreviouslyOpened", sessions: [{ id: "foreign-session", title: "Foreign project session" }] });
    const afterForeignRestore = JSON.parse(fs.readFileSync(path.join(root, "bridge-state.json"), "utf8"));
    if (beforeForeignRestore.selectedDirectory !== afterForeignRestore.selectedDirectory || afterForeignRestore.selectedSession === "foreign-session") throw new Error("A foreign project's session stole focus from the selected new project");
    const instanceTwoCommands = (await local("/commands?instanceId=instance-2")).commands || [];
    if (instanceTwoCommands.some((item) => item.type === "prompt" && item.prompt === "DialogProject")) throw new Error("Dialog project name was incorrectly routed to Team Lead");
    await local("/register", "POST", { instanceId: "instance-attachment", directory: attachmentProject, projectName: "AttachmentProject", pid: process.pid });
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "prompted", sessionId: "attachment-main", parentID: "", agent: "team-lead", mode: "FAST" });
    const finalVerdict = "Готово. Team Lead принял работу специалиста.\n\nЧто сделано\n- Репозиторий проверен полностью.\n- FULL_TEAM_LEAD_VERDICT_SENTINEL сохранён.\n\nСледующие шаги\n- Продолжить реализацию по запросу пользователя.";
    const verdictMessageStart = sentMessages.length;
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "assistant_update", sessionId: "attachment-main", parentID: "", agent: "team-lead", finalText: finalVerdict });
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "idle", sessionId: "attachment-main", parentID: "", agent: "devops-engineer", finalText: finalVerdict });
    for (let verdictAttempt = 0; verdictAttempt < 40 && !sentMessages.some((item) => item.text?.includes("FULL_TEAM_LEAD_VERDICT_SENTINEL")); verdictAttempt++) await new Promise((resolve) => setTimeout(resolve, 25));
    const verdictMessages = sentMessages.slice(verdictMessageStart).filter((item) => item.text?.includes("FULL_TEAM_LEAD_VERDICT_SENTINEL"));
    const verdictMessage = verdictMessages[0];
    if (!verdictMessage?.text?.includes("Финальный отчёт Team Lead") || verdictMessage.text.includes("Агент: devops-engineer") || !verdictMessage.text.includes(finalVerdict)) throw new Error("Parent-session final verdict was not delivered in full as Team Lead");
    if (verdictMessages.length !== 1 || sentMessages.slice(verdictMessageStart).some((item) => item.text?.includes("📝 Обновление работы"))) throw new Error("Completed Team Lead answer was duplicated as progress plus final verdict");
    const orderingStart = sentMessages.length;
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "assistant_update", sessionId: "ordering-main", parentID: "", agent: "team-lead", status: "working", finalText: "LEAD_BEFORE_DELEGATION_SENTINEL" });
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "delegation", sessionId: "ordering-main", parentID: "", agent: "solution-architect", detail: "ORDERING_DELEGATION_SENTINEL" });
    for (let orderingAttempt = 0; orderingAttempt < 60 && !sentMessages.slice(orderingStart).some((item) => item.text?.includes("LEAD_BEFORE_DELEGATION_SENTINEL")); orderingAttempt++) await new Promise((resolve) => setTimeout(resolve, 25));
    const orderingMessages = sentMessages.slice(orderingStart);
    const leadUpdateIndex = orderingMessages.findIndex((item) => item.text?.includes("LEAD_BEFORE_DELEGATION_SENTINEL"));
    const delegationIndex = orderingMessages.findIndex((item) => item.text?.includes("ORDERING_DELEGATION_SENTINEL"));
    if (leadUpdateIndex < 0 || delegationIndex < 0 || leadUpdateIndex > delegationIndex) throw new Error("Team Lead explanation was not delivered before its delegation notification");
    const longVerdict = `LONG_VERDICT_START\n${"Первая подробная часть. ".repeat(170)}\nLONG_VERDICT_MIDDLE\n${"Вторая подробная часть. ".repeat(170)}\nLONG_VERDICT_END`;
    const longVerdictStart = sentMessages.length;
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "idle", sessionId: "attachment-main", parentID: "", agent: "devops-engineer", finalText: longVerdict });
    for (let longAttempt = 0; longAttempt < 40 && !sentMessages.slice(longVerdictStart).some((item) => item.text?.includes("LONG_VERDICT_END")); longAttempt++) await new Promise((resolve) => setTimeout(resolve, 25));
    const longVerdictMessages = sentMessages.slice(longVerdictStart);
    const joinedLongVerdict = longVerdictMessages.map((item) => item.text || "").join("\n");
    if (longVerdictMessages.length < 2 || longVerdictMessages.some((item) => (item.text || "").length > 3900) || !joinedLongVerdict.includes("LONG_VERDICT_START") || !joinedLongVerdict.includes("LONG_VERDICT_MIDDLE") || !joinedLongVerdict.includes("LONG_VERDICT_END") || joinedLongVerdict.includes("превышает лимит")) throw new Error("Long Team Lead verdict was not delivered completely in Telegram-sized chunks");
    pendingUpdates.push({ update_id: updateId++, message: { message_id: 300, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, caption: "Проверь этот файл", document: { file_id: "telegram-file-1", file_name: "sample.txt", mime_type: "text/plain", file_size: 24 } } });
    let attachmentCommand = null;
    for (let attachmentAttempt = 0; attachmentAttempt < 80 && !attachmentCommand; attachmentAttempt++) {
      await new Promise((resolve) => setTimeout(resolve, 25));
      attachmentCommand = ((await local("/commands?instanceId=instance-attachment")).commands || []).find((item) => item.type === "prompt");
    }
    if (!attachmentCommand?.attachments?.[0]?.path || !fs.existsSync(attachmentCommand.attachments[0].path) || !attachmentCommand.prompt.includes(".beeforge")) throw new Error("Inbound Telegram document was not stored and queued for Team Lead");
    pendingUpdates.push(
      { update_id: updateId++, message: { message_id: 301, media_group_id: "album-1", from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, caption: "Проверь оба файла", document: { file_id: "album-file-1", file_name: "one.txt", mime_type: "text/plain", file_size: 24 } } },
      { update_id: updateId++, message: { message_id: 302, media_group_id: "album-1", from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, document: { file_id: "album-file-2", file_name: "two.txt", mime_type: "text/plain", file_size: 24 } } },
    );
    let albumCommand = null;
    for (let albumAttempt = 0; albumAttempt < 100 && !albumCommand; albumAttempt++) {
      await new Promise((resolve) => setTimeout(resolve, 25));
      albumCommand = ((await local("/commands?instanceId=instance-attachment")).commands || []).find((item) => item.type === "prompt" && item.attachments?.length === 2);
    }
    if (!albumCommand || !albumCommand.prompt.includes("Проверь оба файла")) throw new Error("Telegram media group was not batched into one Team Lead prompt");
    await local("/event", "POST", { instanceId: "instance-1", kind: "permission_closed", sessionId: "main-1", requestId: "permission-delete" });
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "status", sessionId: "attachment-main", parentID: "", agent: "team-lead", status: "busy" });
    pendingUpdates.push({ update_id: updateId++, message: { message_id: 303, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "QUEUE_SENTINEL" } });
    for (let queueAttempt = 0; queueAttempt < 40; queueAttempt++) await new Promise((resolve) => setTimeout(resolve, 25));
    const queuedState = JSON.parse(fs.readFileSync(path.join(root, "bridge-state.json"), "utf8"));
    if (!queuedState.queuedPrompts?.some((item) => item.prompt === "QUEUE_SENTINEL")) throw new Error("Busy Team Lead input was not persisted in the prompt queue");
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "idle", sessionId: "attachment-main", parentID: "", agent: "team-lead", finalText: "Готово" });
    let queuedCommand = null;
    for (let queueAttempt = 0; queueAttempt < 40 && !queuedCommand; queueAttempt++) {
      await new Promise((resolve) => setTimeout(resolve, 25));
      queuedCommand = ((await local("/commands?instanceId=instance-attachment")).commands || []).find((item) => item.type === "prompt" && item.prompt === "QUEUE_SENTINEL");
    }
    if (!queuedCommand) throw new Error("Queued Team Lead input was not dispatched after the session became idle");
    // OpenCode may deliver message.updated after session.idle. Its historical
    // status=working must not block the next Telegram message.
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "assistant_update", sessionId: "attachment-main", parentID: "", agent: "team-lead", status: "working", finalText: "Позднее техническое обновление" });
    await new Promise((resolve) => setTimeout(resolve, 1000));
    if (sentMessages.some((item) => item.text?.includes("Позднее техническое обновление"))) throw new Error("A late assistant update was posted after the final Team Lead verdict");
    pendingUpdates.push({ update_id: updateId++, message: { message_id: 304, from: { id: Number(realConfig.allowedUserId) }, chat: { id: Number(realConfig.allowedChatId), type: "private" }, text: "POST_IDLE_QUEUE_SENTINEL" } });
    let postIdleCommand = null;
    for (let postIdleAttempt = 0; postIdleAttempt < 80 && !postIdleCommand; postIdleAttempt++) {
      await new Promise((resolve) => setTimeout(resolve, 25));
      postIdleCommand = ((await local("/commands?instanceId=instance-attachment")).commands || []).find((item) => item.type === "prompt" && item.prompt === "POST_IDLE_QUEUE_SENTINEL");
    }
    if (!postIdleCommand) throw new Error("A late assistant update re-blocked an idle Team Lead session");
    const outputDirectory = path.join(attachmentProject, "output");
    fs.mkdirSync(outputDirectory);
    fs.writeFileSync(path.join(outputDirectory, "result.txt"), "outgoing attachment", "utf8");
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "assistant_update", sessionId: "attachment-main", parentID: "", agent: "team-lead", finalText: "Готово\nTELEGRAM_FILE: output/result.txt", attachments: ["output/result.txt"] });
    for (let uploadAttempt = 0; uploadAttempt < 40 && !sentUploads.length; uploadAttempt++) await new Promise((resolve) => setTimeout(resolve, 25));
    if (sentUploads[0]?.method !== "sendDocument") throw new Error("Outgoing Team Lead file was not uploaded to Telegram");
    fs.writeFileSync(path.join(outputDirectory, "tall-screenshot.png"), Buffer.from("89504e470d0a1a0a0000000d49484452", "hex"));
    await local("/event", "POST", { instanceId: "instance-attachment", kind: "assistant_update", sessionId: "attachment-main", parentID: "", agent: "team-lead", finalText: "Готово\nTELEGRAM_FILE: output/tall-screenshot.png", attachments: ["output/tall-screenshot.png"] });
    for (let photoAttempt = 0; photoAttempt < 40 && sentUploads.filter((item) => item.method === "sendDocument").length < 2; photoAttempt++) await new Promise((resolve) => setTimeout(resolve, 25));
    const uploadMethods = sentUploads.map((item) => item.method).join(",");
    if (sentUploads.some((item) => item.method === "sendPhoto") || uploadMethods !== "sendDocument,sendDocument") throw new Error(`Outgoing images must be sent only as original documents: ${uploadMethods}`);
    fs.writeFileSync(path.join(outputDirectory, "concurrent-screenshot.png"), Buffer.from("89504e470d0a1a0a0000000d49484452", "hex"));
    const concurrentAttachmentEvent = { instanceId: "instance-attachment", sessionId: "attachment-main", parentID: "", agent: "team-lead", finalText: "Готово\nTELEGRAM_FILE: output/concurrent-screenshot.png", attachments: ["output/concurrent-screenshot.png"] };
    await Promise.all([
      local("/event", "POST", { ...concurrentAttachmentEvent, kind: "assistant_update" }),
      local("/event", "POST", { ...concurrentAttachmentEvent, kind: "idle" }),
    ]);
    const concurrentUploads = sentUploads.filter((item) => {
      const file = item.body?.get?.("document");
      return file?.name === "concurrent-screenshot.png";
    });
    if (concurrentUploads.length !== 1) throw new Error(`Concurrent assistant/idle events uploaded one screenshot ${concurrentUploads.length} times`);
    console.log("BRIDGE_CALLBACK_SELF_TEST_OK | always,retry-after-failure,env-cleanup-noncritical,destructive-second-confirmation,confirmed,new-session-menu,project-discovery,offline-selectable,focus,mute-unmute,create-project,create-project-dialog,opencode-registration,opencode-deep-link,console,last-model-launch,model-status,lifecycle-confirmation,full-access-double-confirmation,full-access-disable,team-lead-final-verdict,inbound-attachment,outbound-attachment");
    process.exit(0);
  }
}
throw new Error("Project routing/create/mute integration did not complete");
