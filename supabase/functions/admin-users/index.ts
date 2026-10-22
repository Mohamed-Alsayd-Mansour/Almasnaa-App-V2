// Almasnaa v2 — admin-users Edge Function (account management).
// Deploy:  supabase functions deploy admin-users
// Secrets SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY are injected by Supabase; the service key
// never leaves this function. Only an ACTIVE admin (verified from the JWT) may call it.
// Profile writes are executed with the ADMIN'S OWN JWT, so audit_log records the real executor and the
// DB guards in 0004 (last admin, self-disable, role change with history, ...) apply on top of the checks here.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const ROLES = ["admin", "rassas", "supervisor"];
const fail = (status: number, error: string) => json(status, { ok: false, error });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return fail(405, "method not allowed");

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  const caller = createClient(url, anon, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const admin = createClient(url, service, { auth: { persistSession: false } });

  const { data: u, error: uerr } = await caller.auth.getUser();
  if (uerr || !u?.user) return fail(401, "غير مصرح");
  const { data: me } = await admin.from("profiles").select("id, role, status, deleted_at").eq("id", u.user.id).maybeSingle();
  if (!me || me.role !== "admin" || me.status !== "active" || me.deleted_at) return fail(403, "هذه العملية للأدمن فقط");

  let body: Record<string, any>;
  try { body = await req.json(); } catch { return fail(400, "طلب غير صالح"); }
  const action = String(body.action ?? "");

  const validPassword = (p: unknown) => typeof p === "string" && p.length >= 6;
  const cleanName = (s: unknown) => String(s ?? "").trim();
  const usernameTaken = async (name: string, exceptId?: string) => {
    const { data } = await admin.from("profiles").select("id, username").is("deleted_at", null);
    return (data ?? []).some((r: any) => r.username.trim().toLowerCase() === name.toLowerCase() && r.id !== exceptId);
  };
  const setBan = async (id: string, banned: boolean) =>
    admin.auth.admin.updateUserById(id, { ban_duration: banned ? "876000h" : "none" });

  try {
    switch (action) {
      case "create": {
        const username = cleanName(body.username);
        const display = cleanName(body.display_name) || username;
        const role = String(body.role ?? "");
        if (!username) return fail(400, "اسم المستخدم مطلوب");
        if (!ROLES.includes(role)) return fail(400, "الدور غير صالح");
        if (!validPassword(body.password)) return fail(400, "كلمة المرور 6 أحرف على الأقل");
        if (await usernameTaken(username)) return fail(409, "اسم المستخدم مستخدم من قبل");

        const email = `u_${crypto.randomUUID().replaceAll("-", "").slice(0, 16)}@almasnaa.invalid`;
        const created = await admin.auth.admin.createUser({ email, password: body.password, email_confirm: true });
        if (created.error || !created.data.user) return fail(400, "تعذّر إنشاء الحساب: " + (created.error?.message ?? ""));
        const id = created.data.user.id;
        const ins = await caller.from("profiles").insert({ id, username, display_name: display, role, must_change_password: !!body.force_change });
        if (ins.error) {
          await admin.auth.admin.deleteUser(id);          // no half-created accounts
          return fail(400, "تعذّر حفظ الحساب: " + ins.error.message);
        }
        return json(200, { ok: true, id });
      }

      case "update": {
        const id = String(body.id ?? "");
        const patch: Record<string, unknown> = {};
        if (body.username !== undefined) {
          const n = cleanName(body.username);
          if (!n) return fail(400, "اسم المستخدم مطلوب");
          if (await usernameTaken(n, id)) return fail(409, "اسم المستخدم مستخدم من قبل");
          patch.username = n;
        }
        if (body.display_name !== undefined) patch.display_name = cleanName(body.display_name);
        if (body.role !== undefined) {
          if (!ROLES.includes(String(body.role))) return fail(400, "الدور غير صالح");
          patch.role = body.role;
        }
        if (Object.keys(patch).length === 0) return fail(400, "لا يوجد تغيير");
        const r = await caller.from("profiles").update(patch).eq("id", id).select("id");
        if (r.error) return fail(400, r.error.message);
        if (!r.data?.length) return fail(404, "الحساب غير موجود");
        return json(200, { ok: true });
      }

      case "set_password": {
        const id = String(body.id ?? "");
        if (!validPassword(body.password)) return fail(400, "كلمة المرور 6 أحرف على الأقل");
        const target = await admin.from("profiles").select("id").eq("id", id).is("deleted_at", null).maybeSingle();
        if (!target.data) return fail(404, "الحساب غير موجود");
        const r = await admin.auth.admin.updateUserById(id, { password: body.password });
        if (r.error) return fail(400, r.error.message);
        if (body.force_change !== undefined) await caller.from("profiles").update({ must_change_password: !!body.force_change }).eq("id", id);
        return json(200, { ok: true });
      }

      case "set_status": {
        const id = String(body.id ?? "");
        const status = String(body.status ?? "");
        if (!["active", "disabled"].includes(status)) return fail(400, "الحالة غير صالحة");
        const r = await caller.from("profiles").update({ status }).eq("id", id).select("id");
        if (r.error) return fail(400, r.error.message);          // DB guard: self / last admin
        if (!r.data?.length) return fail(404, "الحساب غير موجود");
        await setBan(id, status === "disabled");                  // blocks new sessions; RLS already blocks data at once
        return json(200, { ok: true });
      }

      case "delete": {
        const id = String(body.id ?? "");
        if (body.confirm !== true) return fail(400, "يلزم تأكيد الحذف");
        if (id === me.id) return fail(400, "لا يمكنك حذف حسابك");
        // try a physical delete first; the DB guard refuses (23503) when the account has any history
        const del = await caller.from("profiles").delete().eq("id", id).select("id");
        if (!del.error && del.data?.length) {
          await admin.auth.admin.deleteUser(id);
          return json(200, { ok: true, mode: "physical" });
        }
        if (del.error && del.error.code !== "23503") return fail(400, del.error.message);
        // has history -> logical delete (disable + deleted_at); history and audit stay intact
        const lg = await caller.from("profiles").update({ status: "disabled", deleted_at: new Date().toISOString() }).eq("id", id).select("id");
        if (lg.error) return fail(400, lg.error.message);
        if (!lg.data?.length) return fail(404, "الحساب غير موجود");
        await setBan(id, true);
        return json(200, { ok: true, mode: "logical" });
      }

      default:
        return fail(400, "إجراء غير معروف");
    }
  } catch (e) {
    console.error("admin-users error", (e as Error).message);   // never log passwords or tokens
    return fail(500, "خطأ غير متوقع في الخادم");
  }
});
