#!/usr/bin/env python3
"""Server-side guarantees behind the admin 'إدارة قاعدة البيانات' screen (it only uses the admin's own JWT).
Self-contained. Env: SUPABASE_DB_URL. Run after migrations 0001..0008."""
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
def mk(name, role):
    i = svc("insert into auth.users(email) values (%s) returning id", (f"{name}@t.invalid",))[0][0]
    svc("insert into public.profiles(id,username,display_name,role) values (%s,%s,%s,%s)", (i, name, name, role))
    return str(i)
def uid(name): return str(svc("select id from public.profiles where username=%s", (name,))[0][0])
for n, r in (("adm", "admin"), ("r1", "rassas"), ("sa", "supervisor"), ("sb", "supervisor")):
    if not svc("select 1 from public.profiles where username=%s", (n,)): mk(n, r)
conn.commit()
ADMIN, R1, SA, SB = uid("adm"), uid("r1"), uid("sa"), uid("sb")
cnt = lambda u, q: as_user(u, q)[0][0][0]

# data: one daily with an entry for (R1, SA); one empty daily for (R1, SB); one owner-less legacy entry
svc("delete from daily_entries"); svc("delete from daily_sessions"); svc("delete from rassas_supervisor_links")
as_user(R1, "select change_supervisor(%s)", (SA,), keep=True)
s1 = as_user(R1, "select create_session()", keep=True)[0][0][0]
e1 = as_user(R1, "insert into daily_entries(daily_session_id,room_name_snapshot,piece_count_snapshot) values (%s,'غرفة',5) returning id", (s1,), keep=True)[0][0][0]
as_user(R1, "select change_supervisor(%s)", (SB,), keep=True)
s2 = as_user(R1, "select create_session()", keep=True)[0][0][0]
svc("set app.bulk='on'")  # legacy seed only (as the v1 migration does)
orphan = svc("insert into daily_entries(daily_session_id,room_name_snapshot) values (%s,'قديمة') returning id", (s1,))[0][0]
conn.commit(); svc("reset app.bulk")

# ---- admin CRUD through the admin's own JWT (audited with the real actor)
ok("admin inserts a room", as_user(ADMIN, "insert into rooms(name,piece_count) values ('اختبار',3)", keep=True)[1] is None)
rid = svc("select id from rooms where name='اختبار'")[0][0]
ok("admin edits the room", as_user(ADMIN, "update rooms set piece_count=4 where id=%s", (rid,), keep=True)[1] is None)
ok("admin adds a person", as_user(ADMIN, "insert into people(name,role) values ('نجار تجريبي','carpenter')", keep=True)[1] is None)
a = svc("select actor_name, actor_role::text, op from audit_log where entity='rooms' and entity_id=%s order by id desc limit 1", (str(rid),))[0]
ok("audit: edit recorded with the real actor and role", a == ("adm", "admin", "UPDATE"))
ok("admin deletes the room; audited", as_user(ADMIN, "delete from rooms where id=%s", (rid,), keep=True)[1] is None and svc("select count(*) from audit_log where entity='rooms' and entity_id=%s and op='DELETE'", (str(rid),))[0][0] == 1)

# ---- sessions / entries guards still apply to admin
ok("admin cannot delete a daily that has entries (FK restrict)", as_user(ADMIN, "delete from daily_sessions where id=%s", (s1,))[1] is not None)
ok("admin can delete an EMPTY daily", as_user(ADMIN, "delete from daily_sessions where id=%s", (s2,))[1] is None)
ok("owner is immutable for owned entries", as_user(ADMIN, "update daily_entries set supervisor_id=%s where id=%s", (SB, e1))[1] is not None)
ok("admin edits an entry text field", as_user(ADMIN, "update daily_entries set problem='x' where id=%s", (e1,), keep=True)[1] is None)

# ---- non-admins cannot reach admin-only data
ok("rassas cannot read migration_review", cnt(R1, "select count(*) from migration_review") == 0)
svc("insert into migration_review(entity,entity_id,reason) values ('daily_entries','z','t') on conflict do nothing"); conn.commit()
ok("admin reads migration_review; rassas/supervisor see nothing", cnt(ADMIN, "select count(*) from migration_review") >= 1 and cnt(R1, "select count(*) from migration_review") == 0 and cnt(SA, "select count(*) from migration_review") == 0)
ok("rassas cannot read other profiles", cnt(R1, "select count(*) from profiles") == 1)
ok("supervisor cannot read the full audit log", cnt(SB, "select count(*) from audit_log where entity='rooms'") == 0)
ok("rassas cannot delete a daily", cnt(R1, "select count(*) from daily_sessions") >= 1 and as_user(R1, "delete from daily_sessions where id=%s", (s1,))[0] in (0, None))
ok("supervisor cannot delete an entry that is not theirs", as_user(SB, "delete from daily_entries where id=%s", (e1,))[0] in (0, None))
ok("supervisor cannot write to app_settings", as_user(SA, "insert into app_settings(key,value) values ('k','1')")[1] is not None)

# ---- owner-less entries: invisible to others, assignable only by admin, never guessed
ok("owner-less entry visible to admin only", cnt(ADMIN, "select count(*) from daily_entries where rassas_id is null") == 1 and cnt(R1, "select count(*) from daily_entries where rassas_id is null") == 0 and cnt(SA, "select count(*) from daily_entries where rassas_id is null") == 0)
ok("rassas cannot assign owners", as_user(R1, "select assign_entry_owner(%s::uuid[], %s, %s)", ([str(orphan)], R1, SA))[1] is not None)
ok("admin assigns explicitly", as_user(ADMIN, "select assign_entry_owner(%s::uuid[], %s, %s)", ([str(orphan)], R1, SA), keep=True)[0][0][0] == 1)
ok("assignment is audited", svc("select count(*) from audit_log where entity='daily_entries' and entity_id=%s and op='UPDATE' and actor_name='adm'", (str(orphan),))[0][0] >= 1)
ok("nothing was deleted by any of this", svc("select count(*) from daily_entries")[0][0] == 2)
print(f"\n{P} passed, {F} failed"); raise SystemExit(1 if F else 0)
