#!/usr/bin/env python3
"""0009: rassas/supervisor names come from accounts (by UUID), are snapshotted, and are admin-only to edit.
Self-contained; wipes dailies/entries of the throw-away DB. Env: SUPABASE_DB_URL. Run after 0001..0009."""
import os, psycopg2
conn = psycopg2.connect(os.environ["SUPABASE_DB_URL"]); conn.autocommit = False
cur = conn.cursor()
P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond: P += 1; print("PASS", name)
    else: F += 1; print("FAIL", name, extra)
def svc(sql, args=None):
    cur.execute("reset role"); cur.execute("select set_config('request.jwt.claim.sub','',true)")
    cur.execute(sql, args); return cur.fetchall() if cur.description else None
def as_user(uid, sql, args=None, keep=False):
    cur.execute("reset role"); cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or "",))
    cur.execute("set local role authenticated")
    try:
        cur.execute(sql, args); res = cur.fetchall() if cur.description else cur.rowcount
        conn.commit() if keep else conn.rollback(); return res, None
    except psycopg2.Error as e:
        conn.rollback(); return None, (e.pgerror or str(e))
def uid(name): return str(svc("select id from public.profiles where username=%s", (name,))[0][0])
def mk(name, role, display):
    ex = svc("select id from public.profiles where username=%s", (name,))
    if ex:
        svc("update profiles set display_name=%s, status='active' where id=%s", (display, ex[0][0])); return str(ex[0][0])
    i = svc("insert into auth.users(email) values (%s) returning id", (f"{name}@t.invalid",))[0][0]
    svc("insert into public.profiles(id,username,display_name,role) values (%s,%s,%s,%s)", (i, name, display, role)); return str(i)

svc("delete from daily_entries"); svc("delete from daily_sessions"); svc("delete from rassas_supervisor_links")
svc("delete from people where role in ('installer','supervisor')")
ADMIN = mk("adm", "admin", "adm"); R1 = mk("r1", "rassas", "رصيص أ"); SA = mk("sa", "supervisor", "مشرف أ"); SB = mk("sb", "supervisor", "مشرف ب")
conn.commit()
dirnames = lambda role: [r[0] for r in svc("select display_name from directory where role=%s order by 1", (role,))]

# ---- 1/2: lists come from accounts only (no hand-typed copies)
ok("people has no installer/supervisor rows (names list is not a second source)", svc("select count(*) from people where role in ('installer','supervisor')")[0][0] == 0)
NEW = mk("sc", "supervisor", "مشرف جديد"); conn.commit()
ok("a newly created supervisor account appears in the supervisor list automatically", "مشرف جديد" in dirnames("supervisor"))
NR = mk("r9", "rassas", "رصيص جديد"); conn.commit()
ok("a newly created rassas account appears in the rassas list automatically", "رصيص جديد" in dirnames("rassas"))
svc("update profiles set status='disabled' where id=%s", (NEW,)); conn.commit()
ok("a disabled account leaves the list", "مشرف جديد" not in dirnames("supervisor"))
ok("supervisor cannot add a hand-typed supervisor name", as_user(SA, "insert into people(name,role) values ('وهمي','supervisor')")[1] is not None)
ok("admin cannot add a hand-typed rassas name", as_user(ADMIN, "insert into people(name,role) values ('وهمي','installer')")[1] is not None)
ok("other name lists (carpenter) still work", as_user(ADMIN, "insert into people(name,role) values ('نجار','carpenter')", keep=True)[1] is None)
ok("cannot re-label a carpenter into a supervisor", as_user(ADMIN, "update people set role='supervisor' where name='نجار'")[1] is not None)

# ---- 4: the daily stores the linked identities automatically
as_user(R1, "select change_supervisor(%s)", (SA,), keep=True)
S = as_user(R1, "select create_session()", keep=True)[0][0][0]
row = svc("select rassas_id::text, supervisor_id::text, rassas_name_snapshot, supervisor_name_snapshot from daily_sessions where id=%s", (S,))[0]
ok("daily stores rassas/supervisor UUIDs and names from their accounts", row == (R1, SA, "رصيص أ", "مشرف أ"), row)
E = as_user(R1, "insert into daily_entries(daily_session_id,room_name_snapshot,installer,supervisor) values (%s,'غرفة','مزوَّر','مزوَّر') returning id", (S,), keep=True)[0][0][0]
ok("entry ignores names sent by the client and takes them from the daily", svc("select installer,supervisor,rassas_id::text,supervisor_id::text from daily_entries where id=%s", (E,))[0] == ("رصيص أ", "مشرف أ", R1, SA))
X = as_user(R1, "insert into daily_entries(daily_session_id,room_name_snapshot,is_external,installer,supervisor) values (%s,'خارجية',true,'x','y') returning id", (S,), keep=True)[0][0][0]
ok("external entry keeps blank names (v1) but ownership by UUID", svc("select installer,supervisor,rassas_id::text from daily_entries where id=%s", (X,))[0] == ("", "", R1))

# ---- 4/5/6: nobody but the admin can change the names (direct API calls)
ok("rassas cannot change installer on an open daily entry", as_user(R1, "update daily_entries set installer='مزوَّر' where id=%s", (E,))[1] is not None)
ok("rassas cannot change supervisor name on an entry", as_user(R1, "update daily_entries set supervisor='مزوَّر' where id=%s", (E,))[1] is not None)
ok("supervisor cannot change installer on an entry", as_user(SA, "update daily_entries set installer='مزوَّر' where id=%s", (E,))[1] is not None)
ok("supervisor cannot change supervisor name on an entry", as_user(SA, "update daily_entries set supervisor='مزوَّر' where id=%s", (E,))[1] is not None)
ok("rassas can still edit allowed fields on the same entry", as_user(R1, "update daily_entries set problem='ok', numbering='5' where id=%s", (E,), keep=True)[1] is None)
ok("rassas cannot rewrite the daily's name snapshots", as_user(R1, "update daily_sessions set rassas_name_snapshot='مزوَّر' where id=%s", (S,))[1] is not None)
ok("rassas cannot rewrite the daily's supervisor snapshot", as_user(R1, "update daily_sessions set supervisor_name_snapshot='مزوَّر' where id=%s", (S,))[1] is not None)
ok("rassas can still change the daily's status (pause/close paths unaffected)", as_user(R1, "select close_session(%s)", (S,), keep=True)[1] is None)
ok("closed record: rassas still cannot touch the names", as_user(R1, "update daily_entries set installer='مزوَّر' where id=%s", (E,))[1] is not None)
ok("closed record: supervisor still cannot touch the names", as_user(SA, "update daily_entries set supervisor='مزوَّر' where id=%s", (E,))[1] is not None)
ok("names unchanged after all attempts", svc("select installer,supervisor from daily_entries where id=%s", (E,))[0] == ("رصيص أ", "مشرف أ"))

# ---- 5: admin only
ok("admin can correct the names on a past record", as_user(ADMIN, "update daily_entries set installer='رصيص أ (مصحَّح)' where id=%s", (E,), keep=True)[1] is None
   and svc("select installer from daily_entries where id=%s", (E,))[0][0] == "رصيص أ (مصحَّح)")
ok("admin cannot change ownership UUIDs (still immutable)", as_user(ADMIN, "update daily_entries set rassas_id=%s where id=%s", (NR, E))[1] is not None)
ok("admin edit is audited with the real actor", svc("select count(*) from audit_log where entity='daily_entries' and entity_id=%s and op='UPDATE' and actor_name='adm'", (str(E),))[0][0] >= 1)

# ---- 7/8: renaming an account never rewrites history; new dailies use the new name
svc("update profiles set display_name='رصيص أ (اسم جديد)' where id=%s", (R1,)); conn.commit()
ok("history keeps the original names after the account is renamed", svc("select rassas_name_snapshot from daily_sessions where id=%s", (S,))[0][0] == "رصيص أ"
   and svc("select installer from daily_entries where id=%s", (X,))[0][0] == "")
S2 = as_user(R1, "select create_session()", keep=True)[0][0][0]
ok("a NEW daily snapshots the new name, the old daily keeps the old one", svc("select rassas_name_snapshot from daily_sessions where id=%s", (S2,))[0][0] == "رصيص أ (اسم جديد)"
   and svc("select rassas_name_snapshot from daily_sessions where id=%s", (S,))[0][0] == "رصيص أ")
ok("historical rows are still tied to their owners by UUID", svc("select rassas_id::text, supervisor_id::text from daily_sessions where id=%s", (S,))[0] == (R1, SA))
svc("update profiles set display_name='رصيص أ' where id=%s", (R1,)); conn.commit()
print(f"\n{P} passed, {F} failed"); raise SystemExit(1 if F else 0)
