// Almasnaa v2 — github-archive Edge Function (Phase 4).
// Writes a full JSON snapshot of the data to a GitHub repo, entirely SERVER-SIDE.
// The GitHub token exists only as the Edge Function secret GITHUB_ARCHIVE_TOKEN — it is never stored in the
// database, never sent to the app, never logged and never included in error messages.
//
// Secrets (supabase secrets set ...):  GITHUB_ARCHIVE_TOKEN  (fine-grained PAT, Contents: read & write, one repo)
//                                      ARCHIVE_CRON_SECRET   (long random string; used by the scheduled GitHub Action)
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.
//
// Callers:  • an active ADMIN (JWT)            -> { action: "run" | "test", config? }
//           • the scheduler (x-archive-secret)  -> { }  (runs only when the archive is enabled)
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-archive-secret",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const REPO_RE = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const BRANCH_RE = /^[A-Za-z0-9._/-]+$/;
const PATH_RE = /^[A-Za-z0-9._/-]+\.json$/;

type Cfg = { enabled: boolean; repo: string; branch: string; path: string };

function validConfig(c: Cfg): string | null {
  if (!REPO_RE.test(c.repo)) return "اسم المستودع غير صالح (owner/repo)";
  if (!BRANCH_RE.test(c.branch) || c.branch.includes("..")) return "اسم الفرع غير صالح";
  if (!PATH_RE.test(c.path) || c.path.includes("..") || c.path.startsWith("/")) return "مسار الملف غير صالح (يجب أن ينتهي بـ .json)";
  return null;
}

const timingSafeEqual = (a: string, b: string) => {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let d = 0;
  for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
};

const toBase64 = (text: string) => {
  const bytes = new TextEncoder().encode(text);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(bin);
};

const sha256 = async (text: string) => {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
};

// Short, safe messages only — never the raw GitHub response and never the token.
const gh = async (token: string, method: string, url: string, body?: unknown) => {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "almasnaa-archive",
      ...(body ? { "Content-Type": "application/json" } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data: any = null;
  try { data = await res.json(); } catch { /* empty body */ }
  return { status: res.status, data };
};

const explain = (status: number) =>
  status === 401 ? "رمز GitHub مرفوض أو منتهي" :
  status === 403 ? "صلاحيات الرمز غير كافية أو تم تجاوز الحد" :
  status === 404 ? "المستودع أو الفرع غير موجود (أو لا يملك الرمز صلاحية عليه)" :
  status === 409 || status === 422 ? "تعارض في الكتابة" :
  `فشل الاتصال بـ GitHub (${status})`;

const api = (c: Cfg) => `https://api.github.com/repos/${c.repo}/contents/${c.path.split("/").map(encodeURIComponent).join("/")}`;

async function currentSha(token: string, c: Cfg): Promise<{ sha: string | null; error?: string }> {
  const r = await gh(token, "GET", `${api(c)}?ref=${encodeURIComponent(c.branch)}`);
  if (r.status === 200 && r.data?.sha) return { sha: r.data.sha };
  if (r.status === 404) {
    // 404 = file missing (fine) OR repo/branch missing/forbidden: tell them apart
    const repo = await gh(token, "GET", `https://api.github.com/repos/${c.repo}/branches/${encodeURIComponent(c.branch)}`);
    if (repo.status === 200) return { sha: null };
    return { sha: null, error: explain(repo.status === 404 ? 404 : repo.status) };
  }
  return { sha: null, error: explain(r.status) };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { ok: false, error: "method not allowed" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const token = Deno.env.get("GITHUB_ARCHIVE_TOKEN") ?? "";
  const cron = Deno.env.get("ARCHIVE_CRON_SECRET") ?? "";
  const admin = createClient(url, service, { auth: { persistSession: false } });

  // ---- who is calling?
  let trigger: "manual" | "schedule";
  let userId: string | null = null;
  const secret = req.headers.get("x-archive-secret");
  if (secret) {
    if (!cron || !timingSafeEqual(secret, cron)) return json(401, { ok: false, error: "غير مصرح" });
    trigger = "schedule";
  } else {
    const authHeader = req.headers.get("Authorization") ?? "";
    const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
    const { data: u, error } = await caller.auth.getUser();
    if (error || !u?.user) return json(401, { ok: false, error: "غير مصرح" });
    const { data: me } = await admin.from("profiles").select("role,status,deleted_at").eq("id", u.user.id).maybeSingle();
    if (!me || me.role !== "admin" || me.status !== "active" || me.deleted_at) return json(403, { ok: false, error: "هذه العملية للأدمن فقط" });
    trigger = "manual"; userId = u.user.id;
  }

  let body: Record<string, any> = {};
  try { body = await req.json(); } catch { /* scheduler sends {} */ }
  const action = trigger === "schedule" ? "run" : String(body.action ?? "run");

  if (!token) return json(200, { ok: false, error: "لم يتم ضبط GITHUB_ARCHIVE_TOKEN في أسرار الخادم (انظر docs/PHASE4_SETUP.md)" });

  // ---- connection test for a config the admin has NOT saved yet
  if (action === "test") {
    const c: Cfg = { enabled: true, repo: String(body.config?.repo ?? ""), branch: String(body.config?.branch ?? "main"), path: String(body.config?.path ?? "") };
    const bad = validConfig(c);
    if (bad) return json(200, { ok: false, error: bad });
    const r = await currentSha(token, c);
    return json(200, r.error ? { ok: false, error: r.error } : { ok: true, fileExists: r.sha !== null });
  }
  if (action !== "run") return json(400, { ok: false, error: "action غير معروف" });

  // ---- run
  const { data: cfgRow } = await admin.from("archive_config").select("enabled,repo,branch,path").eq("id", 1).maybeSingle();
  const cfg = cfgRow as Cfg | null;
  if (!cfg || !cfg.repo) return json(200, { ok: false, error: "لم يتم إعداد مستودع الأرشفة بعد" });
  if (trigger === "schedule" && !cfg.enabled) return json(200, { ok: true, skipped: "disabled" });
  const bad = validConfig(cfg);
  if (bad) return json(200, { ok: false, error: bad });

  const { data: began, error: berr } = await admin.rpc("archive_begin", { p_trigger: trigger, p_user: userId });
  if (berr) return json(500, { ok: false, error: "تعذر بدء الأرشفة" });
  if (!began) return json(200, { ok: false, error: "هناك عملية أرشفة قيد التنفيذ الآن، حاول بعد قليل" });
  const runId: number = began.id;
  const finish = (status: string, hash: string | null, sha: string | null, counts: unknown, error: string | null) =>
    admin.rpc("archive_finish", { p_id: runId, p_status: status, p_hash: hash, p_sha: sha, p_counts: counts, p_error: error });

  try {
    const { data: snap, error: serr } = await admin.rpc("archive_snapshot");
    if (serr || !snap) { await finish("error", null, null, null, "تعذر قراءة البيانات"); return json(200, { ok: false, error: "تعذر قراءة البيانات" }); }

    const { exportedAt: _drop, ...stable } = snap as Record<string, unknown>;
    const hash = await sha256(JSON.stringify(stable));
    const counts = Object.fromEntries(Object.entries(snap as Record<string, unknown>).filter(([, v]) => Array.isArray(v)).map(([k, v]) => [k, (v as unknown[]).length]));

    if (began.last_hash === hash) { await finish("skipped", hash, null, counts, null); return json(200, { ok: true, skipped: "unchanged", counts }); }

    const content = toBase64(JSON.stringify(snap, null, 1));
    const message = `almasnaa archive ${new Date().toISOString()} (${trigger})`;
    let lastStatus = 0;
    for (let attempt = 0; attempt < 4; attempt++) {
      const cur = await currentSha(token, cfg);
      if (cur.error) { await finish("error", null, null, counts, cur.error); return json(200, { ok: false, error: cur.error }); }
      const put = await gh(token, "PUT", api(cfg), { message, content, branch: cfg.branch, ...(cur.sha ? { sha: cur.sha } : {}) });
      lastStatus = put.status;
      if (put.status === 200 || put.status === 201) {
        const commit = put.data?.commit?.sha ?? null;
        await finish("ok", hash, commit, counts, null);
        return json(200, { ok: true, commit, counts });
      }
      if (put.status === 409 || put.status === 422) { await new Promise((r) => setTimeout(r, 400 * (attempt + 1))); continue; }   // conflict: re-read sha, retry
      break;
    }
    const msg = explain(lastStatus);
    await finish("error", null, null, counts, msg);
    return json(200, { ok: false, error: msg });
  } catch (_e) {
    await finish("error", null, null, null, "خطأ غير متوقع أثناء الأرشفة");
    return json(200, { ok: false, error: "خطأ غير متوقع أثناء الأرشفة" });
  }
});
