#!/usr/bin/env python3
"""Integration tests for schema/RLS/guards/RPCs against a LOCAL Postgres (stub auth) after scripts/migrate_v1.py --local-test.
Env: SUPABASE_DB_URL. Run: python tests/test_rls.py"""
import os, sys, json, psycopg2
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

def as_user(uid, sql, args=None, keep=False, anon=False):
    cur.execute("reset role")
    cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or "",))
    cur.execute("set local role " + ("anon" if anon else "authenticated"))
    try:
        cur.execute(sql, args); res = cur.fetchall() if cur.description else cur.rowcount
        conn.commit() if keep else conn.rollback(); return res, None
    except psycopg2.Error as e:
        conn.rollback(); return None, (e.pgerror or str(e))

def uid(name): return svc("select id from public.profiles where username=%s", (name,))[0][0]
ADMIN, MAN, QAD, SAY = (str(uid(n)) for n in ("Mansour", "منصور", "قدري", "الصياد"))
conn.commit()

# extra accounts for isolation tests
for u, role in (("رصيص٢", "rassas"), ("مشرف٣", "supervisor")):
    if not svc("select 1 from public.profiles where username=%s", (u,)):
        i = svc("insert into auth.users(email) values (%s) returning id", (f"{u}@t.invalid",))[0][0]
        svc("insert into public.profiles(id,username,display_name,role) values (%s,%s,%s,%s)", (i, u, u, role))
conn.commit()
R2, S3 = str(uid("رصيص٢")), str(uid("مشرف٣"))

n = lambda uid_, q: as_user(uid_, q)[0][0][0]
# ---- migration integrity / idempotency
ok("v1 rows preserved", svc("select (select count(*) from rooms),(select count(*) from people),(select count(*) from daily_sessions),(select count(*) from daily_entries)")[0] == (64, 132, 23, 186))
ok("no duplicate usernames", svc("select count(*) from (select lower(username) from profiles group by 1 having count(*)>1) x")[0][0] == 0)
ok("admin must change password", svc("select must_change_password from profiles where username='Mansour'")[0][0] is True)
ok("منصور linked to قدري", svc("select supervisor_id from rassas_supervisor_links where rassas_id=%s and effective_to is null", (MAN,))[0][0] == QAD)
ok("exactly one current link", svc("select count(*) from rassas_supervisor_links where rassas_id=%s and effective_to is null", (MAN,))[0][0] == 1)

# ---- visibility
ok("admin sees 186 entries", n(ADMIN, "select count(*) from daily_entries") == 186)
ok("منصور sees his 179 entries", n(MAN, "select count(*) from daily_entries") == 179)
ok("قدري sees 178 entries", n(QAD, "select count(*) from daily_entries") == 178)
ok("الصياد sees exactly his 1 entry", n(SAY, "select count(*) from daily_entries") == 1)
ok("الصياد entry hidden from قدري", n(QAD, "select count(*) from daily_entries where supervisor='الصياد'") == 0)
ok("الصياد sees 1 daily (the one containing his entry)", n(SAY, "select count(*) from daily_sessions") == 1)
ok("قدري sees all 23 dailies", n(QAD, "select count(*) from daily_sessions") == 23)
ok("owner-less historical entries visible to admin only",
   n(ADMIN, "select count(*) from daily_entries where rassas_id is null") == 7 and
   n(MAN, "select count(*) from daily_entries where rassas_id is null") == 0)
ok("rassas2 sees nothing of منصور", n(R2, "select count(*) from daily_entries") == 0 and n(R2, "select count(*) from daily_sessions") == 0)
ok("supervisor3 sees nothing", n(S3, "select count(*) from daily_entries") == 0)
ok("anon cannot read profiles/entries", as_user(None, "select count(*) from profiles", anon=True)[1] is not None)
ok("anon can list login options", len(as_user(None, "select * from login_options('supervisor')", anon=True)[0]) >= 3)
ok("login list excludes admin from rassas list", all(r[0] != "Mansour" for r in as_user(None, "select * from login_options('rassas')", anon=True)[0]))

# ---- rassas record-edit restriction (closed dailies)
eid = svc("select id from daily_entries where rassas_id=%s and is_order=false limit 1", (MAN,))[0][0]
conn.commit()
ORIG0 = svc("select original_deficiencies from daily_entries where id=%s", (eid,))[0][0]; conn.commit()
ok("rassas may edit problem on closed record", as_user(MAN, "update daily_entries set problem='x' where id=%s", (eid,))[1] is None)
ok("rassas may edit specifications_text", as_user(MAN, "update daily_entries set specifications_text='s' where id=%s", (eid,))[1] is None)
ok("rassas may edit current deficiencies", as_user(MAN, "update daily_entries set current_deficiencies='a', current_missing_count=1 where id=%s", (eid,), keep=True)[1] is None)
ok("rassas CANNOT edit carpenter", "may not edit field carpenter" in (as_user(MAN, "update daily_entries set carpenter='z' where id=%s", (eid,))[1] or ""))
ok("rassas CANNOT edit piece snapshot", as_user(MAN, "update daily_entries set piece_count_snapshot=99 where id=%s", (eid,))[1] is not None)
ok("rassas CANNOT change owner", as_user(MAN, "update daily_entries set rassas_id=%s where id=%s", (R2, eid))[1] is not None)
ok("rassas CANNOT delete closed record", as_user(MAN, "delete from daily_entries where id=%s", (eid,))[0] == 0)
ok("rassas CANNOT change original deficiencies", as_user(MAN, "update daily_entries set original_deficiencies='q' where id=%s", (eid,))[1] is not None)
ok("supervisor may fully edit own entry", as_user(QAD, "update daily_entries set carpenter='z' where id=%s", (eid,))[1] is None)
ok("editing current deficiencies leaves the original untouched", svc("select original_deficiencies, current_deficiencies from daily_entries where id=%s", (eid,))[0] == (ORIG0, "a"))
say_e = svc("select id from daily_entries where supervisor_id=%s", (SAY,))[0][0]; conn.commit()
ok("قدري cannot edit الصياد's entry (0 rows)", as_user(QAD, "update daily_entries set carpenter='z' where id=%s", (say_e,))[0] == 0)
ok("الصياد can edit his entry", as_user(SAY, "update daily_entries set problem='p' where id=%s", (say_e,))[0] == 1)

# ---- catalogue / lists / accounts
ok("supervisor cannot add room", as_user(QAD, "insert into rooms(name) values ('x')")[1] is not None)
ok("rassas can add room", as_user(MAN, "insert into rooms(name) values ('x')")[1] is None)
ok("rassas cannot edit name lists", as_user(MAN, "insert into people(name,role) values ('x','carpenter')")[1] is not None)
ok("supervisor can edit name lists", as_user(QAD, "insert into people(name,role) values ('x','carpenter')")[1] is None)
ok("nobody but service creates profiles", all(as_user(u, "insert into profiles(id,username,display_name,role) values (gen_random_uuid(),'h','h','admin')")[1] is not None for u in (ADMIN, MAN, QAD)))
as_user(MAN, "update profiles set role='admin' where id=%s", (MAN,), keep=True); conn.commit()
ok("rassas cannot promote self", svc("select role::text from profiles where id=%s", (MAN,))[0][0] == "rassas")
ok("non-admin cannot read others' profiles", n(MAN, "select count(*) from profiles") == 1 and n(ADMIN, "select count(*) from profiles") >= 6)
ok("directory shows active users to everyone", n(MAN, "select count(*) from directory") >= 6)
ok("non-admin cannot read audit of others", n(R2, "select count(*) from audit_log") == 0)
ok("secrets unreachable", as_user(ADMIN, "select * from private.secrets")[1] is not None)

# ---- links + multiple dailies
ok("supervisor cannot call change_supervisor", as_user(QAD, "select change_supervisor(%s)", (SAY,))[1] is not None)
ok("rassas cannot pick a non-supervisor", as_user(MAN, "select change_supervisor(%s)", (R2,))[1] is not None)
as_user(MAN, "select change_supervisor(%s)", (SAY,), keep=True)
s1 = as_user(MAN, "select create_session()", keep=True)[0][0][0]     # 0008: picking never creates; creation is explicit
s1b = as_user(MAN, "select create_session()", keep=True)[0][0][0]
ok("repeat change is idempotent (same daily, no duplicate)", s1 == s1b and svc("select count(*) from daily_sessions where rassas_id=%s and status in ('active','paused')", (MAN,))[0][0] == 1)
conn.commit()
ok("link now points to الصياد, history kept", svc("select count(*) from rassas_supervisor_links where rassas_id=%s", (MAN,))[0][0] == 2)
e_new = as_user(MAN, "insert into daily_entries(daily_session_id,room_name_snapshot,piece_count_snapshot,rassas_id,supervisor_id,installer,supervisor) values (%s,'r',5,%s,%s,'spoof','spoof') returning id", (s1, R2, QAD), keep=True)
ok("entry insert: owner ids forced from daily (spoof ignored)", e_new[1] is None and svc("select rassas_id::text,supervisor_id::text,supervisor from daily_entries where id=%s", (e_new[0][0][0],))[0] == (MAN, SAY, "الصياد"))
conn.commit()
ok("الصياد now sees 2 entries + 2 dailies", n(SAY, "select count(*) from daily_entries") == 2 and n(SAY, "select count(*) from daily_sessions") == 2)
as_user(MAN, "select change_supervisor(%s)", (QAD,), keep=True)
s2 = as_user(MAN, "select create_session()", keep=True)[0][0][0]
ok("switch back + explicit create makes a new daily for قدري; الصياد's daily is paused", s2 != s1 and svc("select status::text from daily_sessions where id=%s", (s1,))[0][0] == "paused" and svc("select status::text from daily_sessions where id=%s", (s2,))[0][0] == "active")
conn.commit()
ok("insert into paused daily rejected", as_user(MAN, "insert into daily_entries(daily_session_id) values (%s)", (s1,))[1] is not None)
s3 = as_user(MAN, "select change_supervisor(%s)", (SAY,), keep=True)[0][0][0]
ok("returning to الصياد RESUMES the same daily", s3 == s1 and svc("select count(*) from daily_sessions where rassas_id=%s and status in ('active','paused')", (MAN,))[0][0] == 2)
conn.commit()
ok("select_session switches selection", as_user(MAN, "select select_session(%s)", (s2,), keep=True)[1] is None and svc("select status::text from daily_sessions where id=%s", (s2,))[0][0] == "active")
conn.commit()
ok("قدري keeps seeing his old dailies after link changes", n(QAD, "select count(*) from daily_sessions") == 24)
ok("daily ownership immutable", as_user(MAN, "update daily_sessions set supervisor_id=%s where id=%s", (SAY, s2))[1] is not None)
ok("supervisor cannot close a daily", as_user(QAD, "select close_session(%s)", (s2,))[1] is not None)
ok("rassas2 cannot close منصور's daily", as_user(R2, "select close_session(%s)", (s2,))[1] is not None)
as_user(MAN, "select close_session(%s)", (s2,), keep=True); conn.commit()
ok("closed daily is read-only", as_user(MAN, "update daily_sessions set day_name='x' where id=%s", (s2,))[1] is not None)
ok("repeat close is idempotent", as_user(MAN, "select close_session(%s)", (s2,))[1] is None)
ok("admin can act for a rassas", as_user(ADMIN, "select change_supervisor(%s,%s)", (QAD, MAN))[1] is None)

# ---- audit + notifications
svc("delete from notifications"); conn.commit()
as_user(MAN, "update daily_entries set problem='audit-me' where id=%s", (eid,), keep=True); conn.commit()
a = svc("select actor_name, actor_role::text, op, changes->'problem'->>'new', rassas_id::text, supervisor_id::text from audit_log order by id desc limit 1")[0]
ok("audit row has actor/role/new value/owners", a[:4] == ("منصور", "rassas", "UPDATE", "audit-me") and a[4] == MAN)
rec = {r[0] for r in svc("select recipient_id::text from notifications")}
ok("notifications: admin + entry's supervisor, not the actor, not الصياد", ADMIN in rec and QAD in rec and MAN not in rec and SAY not in rec and R2 not in rec)
ok("notification list is private", n(QAD, "select count(*) from notifications") == 1 and n(R2, "select count(*) from notifications") == 0)
ok("user can mark own notification read", as_user(QAD, "update notifications set read_at=now()")[0] == 1)
ok("user cannot change notification recipient", as_user(QAD, "update notifications set recipient_id=%s", (SAY,))[1] is not None)

# ---- backup gate
ok("non-admin cannot set backup password", as_user(MAN, "select set_backup_password('secret1')")[1] is not None)
as_user(ADMIN, "select set_backup_password('secret1')", keep=True); conn.commit()
ok("password stored hashed", svc("select hash from private.secrets")[0][0].startswith("$2"))
ok("wrong backup password refused", as_user(MAN, "select export_backup('nope')")[0][0][0]["ok"] is False)
ex = as_user(MAN, "select export_backup('secret1')")[0][0][0]
ok("rassas export OK + filename pattern", ex["ok"] and ex["fileName"].startswith("almasnaa-data-منصور-") and ex["fileName"].endswith(".json"), ex.get("fileName"))
ok("export is scoped to the rassas's rows and has no secrets", len(ex["data"]["entries"]) >= 179 and ex["data"]["schemaVersion"] == 2 and "password" not in json.dumps(ex["data"]).lower())
full = as_user(ADMIN, "select export_backup('secret1')")[0][0][0]
ok("admin export is full and named as full backup", len(full["data"]["entries"]) == 187 and full["fileName"].startswith("almasnaa-full-backup-"), len(full["data"]["entries"]))
ok("import by non-admin rejected", as_user(MAN, "select import_backup('secret1', %s::jsonb, false)", (json.dumps(full["data"]),))[1] is not None)
dry = as_user(ADMIN, "select import_backup('secret1', %s::jsonb, false)", (json.dumps(full["data"]),))[0][0][0]
ok("re-import of same data: nothing new (no duplicates)", dry["ok"] and set(dry["wouldInsert"].values()) == {0}, dry)
bad = json.loads(json.dumps(full["data"])); bad["entries"][0]["daily_session_id"] = "00000000-0000-0000-0000-000000000000"
ok("broken relation rejected before any write", as_user(ADMIN, "select import_backup('secret1', %s::jsonb, true)", (json.dumps(bad),))[0][0][0]["error"] == "broken_relations")
ok("wrong schemaVersion rejected", as_user(ADMIN, "select import_backup('secret1', %s::jsonb, false)", (json.dumps({"app":"almasnaa","schemaVersion":1}),))[0][0][0]["error"] == "unsupported_file")
ok("delete_all with wrong password refused", as_user(ADMIN, "select delete_all_data('bad')")[0][0][0]["ok"] is False)
ok("delete_all by non-admin rejected", as_user(MAN, "select delete_all_data('secret1')")[1] is not None)
# destructive round-trip inside one transaction, rolled back at the end
cur.execute("reset role"); cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (ADMIN,)); cur.execute("set local role authenticated")
cur.execute("select delete_all_data('secret1')"); d = cur.fetchone()[0]
cur.execute("select (select count(*) from daily_entries),(select count(*) from rooms),(select count(*) from profiles)")
c = cur.fetchone()
ok("delete_all removes operational data only (accounts kept)", d["ok"] and c[0] == 0 and c[1] == 0 and c[2] >= 6)
cur.execute("select import_backup('secret1', %s::jsonb, true)", (json.dumps(full["data"]),)); r = cur.fetchone()[0]
cur.execute("select count(*) from daily_entries"); ce = cur.fetchone()[0]
ok("restore from admin export brings everything back atomically", r["ok"] and ce == 187, (r, ce))
conn.rollback()

# ---- disabled account
svc("update profiles set status='disabled' where id=%s", (QAD,)); conn.commit()
ok("disabled user sees no data", n(QAD, "select count(*) from daily_entries") == 0 and n(QAD, "select count(*) from rooms") == 0)
ok("disabled user absent from login list", all(r[0] != "قدري" for r in as_user(None, "select * from login_options('supervisor')", anon=True)[0]))
ok("cannot link a disabled supervisor", as_user(MAN, "select change_supervisor(%s)", (QAD,))[1] is not None)
svc("update profiles set status='active' where id=%s", (QAD,)); conn.commit()

# ---- 0004: account administration rules + owner assignment
newid = svc("insert into auth.users(email) values ('new@t.invalid') returning id")[0][0]; conn.commit()
ok("admin can create a profile", as_user(ADMIN, "insert into profiles(id,username,display_name,role) values (%s,'جديد','جديد','supervisor')", (newid,), keep=True)[1] is None)
ok("non-admin cannot create/edit profiles", as_user(MAN, "update profiles set display_name='x' where id=%s", (newid,))[0] == 0)
ok("audit records the ADMIN as executor of account creation", svc("select actor_name, actor_role::text from audit_log where entity='profiles' and entity_id=%s order by id desc limit 1", (str(newid),))[0] == ("Mansour", "admin"))
ok("role can change while account has no history", as_user(ADMIN, "update profiles set role='rassas' where id=%s", (newid,))[1] is None)
ok("role cannot change once history exists", "history" in (as_user(ADMIN, "update profiles set role='admin' where id=%s", (QAD,))[1] or ""))
ok("admin cannot change own role / disable self", as_user(ADMIN, "update profiles set role='supervisor' where id=%s", (ADMIN,))[1] is not None and as_user(ADMIN, "update profiles set status='disabled' where id=%s", (ADMIN,))[1] is not None)
ok("cannot delete account with history", as_user(ADMIN, "delete from profiles where id=%s", (QAD,))[1] is not None)
ok("account without history can be physically deleted", as_user(ADMIN, "delete from profiles where id=%s", (newid,))[1] is None)
ok("logical delete frees the username", as_user(ADMIN, "update profiles set status='disabled', deleted_at=now() where id=%s", (S3,), keep=True)[1] is None and as_user(ADMIN, "insert into profiles(id,username,display_name,role) select %s, username, 'x', 'supervisor' from profiles where id=%s", (str(svc("insert into auth.users(email) values ('dup@t.invalid') returning id")[0][0]), S3), keep=True)[1] is None)
conn.commit()
ok("last active admin cannot be disabled", as_user(ADMIN, "update profiles set status='disabled' where id<>%s and role='admin'", (ADMIN,))[0] == 0)
# a second admin may disable the first, but not when he is the last one
adm2 = svc("insert into auth.users(email) values ('adm2@t.invalid') returning id")[0][0]; svc("insert into profiles(id,username,display_name,role) values (%s,'admin2','admin2','admin')", (adm2,)); conn.commit()
ok("with two admins, one can disable the other", as_user(str(adm2), "update profiles set status='disabled' where id=%s", (ADMIN,))[1] is None)
ok("...but the remaining one is protected", as_user(str(adm2), "update profiles set status='disabled' where id=%s", (str(adm2),))[1] is not None)
orph = [r[0] for r in svc("select id from daily_entries where rassas_id is null and supervisor_id is null")]; conn.commit()
ok("7 owner-less entries listed for review", len(orph) == 7 and svc("select count(*) from migration_review where entity='daily_entries' and reason like 'no rassas/supervisor%'")[0][0] == 7)
ok("rassas/supervisor cannot assign owners", as_user(MAN, "select assign_entry_owner(%s::uuid[], %s, %s)", (orph[:2], MAN, QAD))[1] is not None)
ok("admin assigns 3 owner-less entries", as_user(ADMIN, "select assign_entry_owner(%s::uuid[], %s, %s)", (orph[:3], MAN, QAD), keep=True)[0][0][0] == 3)
ok("assigned entries now visible to منصور/قدري with snapshots", svc("select count(*) from daily_entries where id = any(%s::uuid[]) and installer='منصور' and supervisor='قدري' and needs_review=false", (orph[:3],))[0][0] == 3 and n(MAN, "select count(*) from daily_entries where rassas_id is null") == 0)
ok("review list shrinks to 4", svc("select count(*) from migration_review where entity='daily_entries' and reason like 'no rassas/supervisor%'")[0][0] == 4)
ok("re-assigning already-owned entries changes nothing", as_user(ADMIN, "select assign_entry_owner(%s::uuid[], %s, %s)", (orph[:3], MAN, SAY))[0][0][0] == 0)
ok("assigning to a non-supervisor is rejected", as_user(ADMIN, "select assign_entry_owner(%s::uuid[], %s, %s)", (orph[3:], MAN, R2))[1] is not None)

# ---- 0005 / Phase 3: external rooms, idempotent client inserts, multi-daily behaviour used by the app
as_user(MAN, "select change_supervisor(%s)", (QAD,), keep=True); sid = as_user(MAN, "select create_session()", keep=True)[0][0][0]; conn.commit()
ext = as_user(MAN, "insert into daily_entries(id,daily_session_id,room_name_snapshot,piece_count_snapshot,is_external,merchant_name,installer,supervisor) values ('11111111-1111-4111-8111-111111111111',%s,'خارجية',5,true,'تاجر','x','y')", (sid,), keep=True); conn.commit()
ok("external entry: names stay blank (v1), ownership still set by id", ext[1] is None and svc("select installer,supervisor,rassas_id::text,supervisor_id::text from daily_entries where id='11111111-1111-4111-8111-111111111111'")[0] == ("", "", MAN, QAD))
reg = as_user(MAN, "insert into daily_entries(id,daily_session_id,room_name_snapshot,piece_count_snapshot) values ('22222222-2222-4222-8222-222222222222',%s,'داخلية',9)", (sid,), keep=True); conn.commit()
ok("internal entry: names filled from the daily snapshot", svc("select installer,supervisor from daily_entries where id='22222222-2222-4222-8222-222222222222'")[0] == ("منصور", "قدري"))
dup = as_user(MAN, "insert into daily_entries(id,daily_session_id,room_name_snapshot,piece_count_snapshot) values ('22222222-2222-4222-8222-222222222222',%s,'داخلية',9) on conflict (id) do nothing", (sid,), keep=True)
ok("client retry with same id (ON CONFLICT DO NOTHING) creates no duplicate", dup[1] is None and svc("select count(*) from daily_entries where id='22222222-2222-4222-8222-222222222222'")[0][0] == 1)
ok("inserted rows get SERVER time, not client time", svc("select created_at > now() - interval '1 minute' from daily_entries where id='22222222-2222-4222-8222-222222222222'")[0][0])
ok("rassas diff-update of one field on an open daily works (partial payload)", as_user(MAN, "update daily_entries set problem='p' where id='22222222-2222-4222-8222-222222222222'", keep=True)[1] is None)
conn.commit()
ok("supervisor sees the open daily's entries but cannot insert into it", n(QAD, "select count(*) from daily_entries where daily_session_id=%s" % ("'%s'" % sid)) == 2 and as_user(QAD, "insert into daily_entries(daily_session_id,room_name_snapshot) values (%s,'z')", (sid,))[1] is not None)
ok("supervisor sees the open daily row (for the switcher)", n(QAD, "select count(*) from daily_sessions where status in ('active','paused')") >= 1)
as_user(MAN, "select close_session(%s)", (sid,), keep=True); conn.commit()
ok("after close: rassas can still edit allowed field", as_user(MAN, "update daily_entries set specifications_text='s' where id='22222222-2222-4222-8222-222222222222'")[1] is None)
ok("after close: rassas can NOT delete or edit other fields", as_user(MAN, "delete from daily_entries where id='22222222-2222-4222-8222-222222222222'")[0] == 0 and as_user(MAN, "update daily_entries set numbering='9' where id='22222222-2222-4222-8222-222222222222'")[1] is not None)

print(f"\n{P} passed, {F} failed"); sys.exit(1 if F else 0)
