#!/usr/bin/env python3
"""0008: picking/changing the supervisor never creates a daily; create_session is the only creator.
Self-contained (seeds its own users). Env: SUPABASE_DB_URL. Run after migrations 0001..0008."""
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
    cur.execute("reset role")
    cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or "",))
    cur.execute("set local role authenticated")
    try:
        cur.execute(sql, args); res = cur.fetchall() if cur.description else cur.rowcount
        conn.commit() if keep else conn.rollback(); return res, None
    except psycopg2.Error as e:
        conn.rollback(); return None, (e.pgerror or str(e))

def mk(name, role):
    ex = svc("select id from public.profiles where username=%s", (name,))
    if ex: return str(ex[0][0])
    i = svc("insert into auth.users(email) values (%s) returning id", (f"{name}@t.invalid",))[0][0]
    svc("insert into public.profiles(id,username,display_name,role) values (%s,%s,%s,%s)", (i, name, name, role))
    return str(i)
svc("delete from daily_entries"); svc("delete from daily_sessions"); svc("delete from rassas_supervisor_links")
ADMIN = mk("adm", "admin"); R1 = mk("r1", "rassas"); R2 = mk("r2", "rassas"); SA = mk("sa", "supervisor"); SB = mk("sb", "supervisor")
conn.commit()
cnt = lambda where="true": svc(f"select count(*) from daily_sessions where {where}")[0][0]

# ---- picking a supervisor
r = as_user(R1, "select change_supervisor(%s)", (SA,), keep=True)
ok("first pick: no daily exists -> returns NULL", r[1] is None and r[0][0][0] is None)
ok("first pick created NO daily", cnt() == 0)
ok("first pick still linked the supervisor", svc("select supervisor_id::text from rassas_supervisor_links where rassas_id=%s and effective_to is null", (R1,))[0][0] == SA)
for _ in range(3): as_user(R1, "select change_supervisor(%s)", (SA,), keep=True)   # login / reload / reconnect
ok("repeated picks (login, reload, reconnect) create nothing", cnt() == 0)

# ---- explicit creation
s1 = as_user(R1, "select create_session()", keep=True)[0][0][0]
ok("create_session creates one active daily for the linked supervisor", cnt() == 1 and svc("select status::text,rassas_id::text,supervisor_id::text from daily_sessions where id=%s", (s1,))[0] == ("active", R1, SA))
s1b = as_user(R1, "select create_session()", keep=True)[0][0][0]
ok("create_session is idempotent (double tap: same daily, no duplicate)", s1b == s1 and cnt() == 1)
ok("pick again returns the existing daily and creates nothing", as_user(R1, "select change_supervisor(%s)", (SA,), keep=True)[0][0][0] == s1 and cnt() == 1)

# ---- changing supervisor
r = as_user(R1, "select change_supervisor(%s)", (SB,), keep=True)
ok("change to a supervisor without a daily: NULL, nothing created", r[0][0][0] is None and cnt() == 1)
ok("previous daily was PAUSED (not closed, not deleted)", svc("select status::text from daily_sessions where id=%s", (s1,))[0][0] == "paused")
ok("no active daily now (explicit creation required)", cnt("status='active'") == 0)
ok("ownership of the old daily unchanged", svc("select rassas_id::text,supervisor_id::text from daily_sessions where id=%s", (s1,))[0] == (R1, SA))
s2 = as_user(R1, "select create_session()", keep=True)[0][0][0]
ok("explicit create for the new supervisor", s2 != s1 and svc("select supervisor_id::text,status::text from daily_sessions where id=%s", (s2,))[0] == (SB, "active") and cnt() == 2)
r = as_user(R1, "select change_supervisor(%s)", (SA,), keep=True)
ok("returning to a previous supervisor RESUMES its daily (no new row)", r[0][0][0] == s1 and cnt() == 2 and svc("select status::text from daily_sessions where id=%s", (s1,))[0][0] == "active" and svc("select status::text from daily_sessions where id=%s", (s2,))[0][0] == "paused")
ok("exactly one active daily per rassas", cnt(f"rassas_id='{R1}' and status='active'") == 1)

# ---- closed daily + new explicit one
as_user(R1, "select close_session(%s)", (s1,), keep=True)
r = as_user(R1, "select change_supervisor(%s)", (SA,), keep=True)
ok("closed daily is never resurrected by picking", r[0][0][0] is None and svc("select status::text from daily_sessions where id=%s", (s1,))[0][0] == "closed")
s3 = as_user(R1, "select create_session()", keep=True)[0][0][0]
ok("a NEW daily can be created manually after closing", s3 not in (s1, s2) and cnt() == 3)

# ---- permissions / ownership
ok("supervisor cannot create_session", as_user(SA, "select create_session()")[1] is not None)
ok("rassas cannot create for another rassas", as_user(R1, "select create_session(null,%s)", (R2,))[1] is not None)
ok("rassas cannot pass a supervisor other than the linked one", as_user(R1, "select create_session(%s)", (SB,))[1] is not None)
ok("create_session without a linked supervisor is rejected", as_user(R2, "select create_session()")[1] is not None and cnt(f"rassas_id='{R2}'") == 0)
ok("admin must name the rassas", as_user(ADMIN, "select create_session()")[1] is not None)
as_user(R2, "select change_supervisor(%s)", (SB,), keep=True)
ok("admin can create explicitly for a rassas", as_user(ADMIN, "select create_session(null,%s)", (R2,), keep=True)[1] is None and cnt(f"rassas_id='{R2}'") == 1)
ok("direct anon-style insert path still guarded (rassas cannot spoof owner)", as_user(R1, "insert into daily_sessions(day_name,date,start_time,status,supervisor_id) values ('x',now(),now(),'paused',%s)", (SB,))[1] is not None)
ok("other rassas daily untouched by R1 operations", cnt(f"rassas_id='{R2}'") == 1)
print(f"\n{P} passed, {F} failed"); raise SystemExit(1 if F else 0)
