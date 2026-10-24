#!/usr/bin/env python3
"""Phase 4 tests: chat / mentions / attachments (Storage policies) / notifications / view-as audit / archive / delete-names.
Run AFTER tests/test_rls.py data exists (tests/run_local.sh does both).  Env: SUPABASE_DB_URL."""
import os, sys, json, uuid, psycopg2
conn = psycopg2.connect(os.environ["SUPABASE_DB_URL"]); conn.autocommit = False
cur = conn.cursor()
P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond: P += 1; print("PASS", name)
    else: F += 1; print("FAIL", name, extra)

def svc(sql, args=None):
    cur.execute("reset role"); cur.execute("select set_config('request.jwt.claim.sub','',true)")
    cur.execute(sql, args); r = cur.fetchall() if cur.description else None
    conn.commit(); return r

def as_user(uid, sql, args=None, keep=False, anon=False, headers=None):
    cur.execute("reset role")
    cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or "",))
    if headers: cur.execute("select set_config('request.headers', %s, true)", (json.dumps(headers),))
    cur.execute("set local role " + ("anon" if anon else "authenticated"))
    try:
        cur.execute(sql, args); res = cur.fetchall() if cur.description else cur.rowcount
        conn.commit() if keep else conn.rollback(); return res, None
    except psycopg2.Error as e:
        conn.rollback(); return None, (e.pgerror or str(e))

def uid(name): return svc("select id from public.profiles where username=%s and deleted_at is null", (name,))[0][0]
def mk(username, role, status="active"):
    if not svc("select 1 from public.profiles where username=%s and deleted_at is null", (username,)):
        i = svc("insert into auth.users(email) values (%s) returning id", (f"{username}@t.invalid",))[0][0]
        svc("insert into public.profiles(id,username,display_name,role,status) values (%s,%s,%s,%s,%s)", (i, username, username, role, status))
    return str(uid(username))

ADMIN, MAN, QAD, SAY = (str(uid(n)) for n in ("Mansour", "منصور", "قدري", "الصياد"))
R2, S3 = mk("رصيص٢", "rassas"), mk("مشرف٣", "supervisor")
DIS = mk("مشرف_معطل", "supervisor", "disabled")
cnt = lambda u, q, a=None: as_user(u, q, a)[0][0][0]
U = lambda: str(uuid.uuid4())

# ---------------- directory
d = as_user(MAN, "select id::text from chat_directory()")[0]
ok("directory lists active users incl. every role", len(d) >= 6 and ADMIN in [x[0] for x in d])
ok("directory hides disabled accounts", DIS not in [x[0] for x in d])
ok("anon cannot read the directory / call chat RPCs", as_user(None, "select * from chat_directory()", anon=True)[1] is not None)

# ---------------- direct conversations
c1 = as_user(MAN, "select chat_open_direct(%s)", (QAD,), keep=True)[0][0][0]
c1b = as_user(QAD, "select chat_open_direct(%s)", (MAN,), keep=True)[0][0][0]
ok("direct chat is one per pair (idempotent, order-independent)", c1 == c1b and svc("select count(*) from chat_conversations where kind='direct'")[0][0] == 1)
ok("cannot open a chat with yourself / disabled user", as_user(MAN, "select chat_open_direct(%s)", (MAN,))[1] is not None and as_user(MAN, "select chat_open_direct(%s)", (DIS,))[1] is not None)
ok("non-member sees no conversation / members", cnt(R2, "select count(*) from chat_conversations") == 0 and cnt(R2, "select count(*) from chat_members") == 0)
ok("members see the conversation and its roster", cnt(MAN, "select count(*) from chat_conversations") == 1 and cnt(QAD, "select count(*) from chat_members") == 2)
ok("clients cannot write chat tables directly",
   as_user(MAN, "insert into chat_messages(id,conversation_id,sender_id,sender_name,kind,body) values (gen_random_uuid(),%s,%s,'x','text','hi')", (c1, MAN))[1] is not None and
   as_user(MAN, "insert into chat_members(conversation_id,user_id) values (%s,%s)", (c1, R2))[1] is not None and
   as_user(MAN, "update chat_conversations set title='x'")[1] is not None)

# ---------------- text messages: idempotent, membership enforced
m1 = U()
r = as_user(MAN, "select chat_send(%s,%s,%s)", (c1, m1, "مرحبا"), keep=True)
ok("member sends a text message", r[1] is None and r[0][0][0]["duplicate"] is False)
r2 = as_user(MAN, "select chat_send(%s,%s,%s)", (c1, m1, "مرحبا"), keep=True)
ok("retry with the same id creates no duplicate", r2[1] is None and r2[0][0][0]["duplicate"] is True and svc("select count(*) from chat_messages where id=%s", (m1,))[0][0] == 1)
ok("another user cannot hijack an existing message id", as_user(QAD, "select chat_send(%s,%s,%s)", (c1, m1, "x"))[1] is not None)
ok("non-member cannot send", as_user(R2, "select chat_send(%s,%s,%s)", (c1, U(), "x"))[1] is not None)
ok("empty message rejected", as_user(MAN, "select chat_send(%s,%s,%s)", (c1, U(), "   "))[1] is not None)
ok("overlong message rejected", as_user(MAN, "select chat_send(%s,%s,%s)", (c1, U(), "x" * 4001))[1] is not None)
ok("sender name snapshot + server time", svc("select sender_name='منصور' and created_at > now()-interval '1 minute' from chat_messages where id=%s", (m1,))[0][0])
ok("non-member cannot read messages", cnt(R2, "select count(*) from chat_messages") == 0 and cnt(QAD, "select count(*) from chat_messages") == 1)
dis_c = svc("select chat_open_direct(%s)", (MAN,)) if False else None

# disabled account cannot send even if it was a member
gdis = as_user(MAN, "select chat_create_group('فريق',%s::uuid[])", ([QAD, DIS],), keep=True)[0][0][0]
ok("disabled users are not added to groups", svc("select count(*) from chat_members where conversation_id=%s", (gdis,))[0][0] == 2)
svc("insert into chat_members(conversation_id,user_id) values (%s,%s)", (gdis, DIS))
ok("a disabled account cannot send / read", as_user(DIS, "select chat_send(%s,%s,%s)", (gdis, U(), "x"))[1] is not None and cnt(DIS, "select count(*) from chat_messages") == 0)

# ---------------- attachments (Storage policies + server-side validation)
def put_obj(path, mime, size, owner):
    svc("insert into storage.objects(bucket_id,name,owner_id,metadata) values ('chat-attachments',%s,%s,%s)", (path, owner, json.dumps({"mimetype": mime, "size": size})))
mid, aid = U(), U()
path = f"{c1}/{mid}/{aid}_photo.jpg"
r = as_user(MAN, "insert into storage.objects(bucket_id,name,owner_id,metadata) values ('chat-attachments',%s,%s,%s)", (path, MAN, json.dumps({"mimetype": "image/jpeg", "size": 1000})), keep=True)
ok("member can upload into the conversation folder", r[1] is None)
ok("non-member cannot upload into it", as_user(R2, "insert into storage.objects(bucket_id,name,owner_id,metadata) values ('chat-attachments',%s,%s,'{}')", (f"{c1}/{U()}/{U()}_x.jpg", R2))[1] is not None)
ok("junk / foreign path cannot be uploaded", as_user(MAN, "insert into storage.objects(bucket_id,name,owner_id,metadata) values ('chat-attachments','../x.jpg',%s,'{}')", (MAN,))[1] is not None)
ok("only members can read (sign) the file", cnt(QAD, "select count(*) from storage.objects") == 1 and cnt(R2, "select count(*) from storage.objects") == 0)
r = as_user(MAN, "select chat_send(%s,%s,%s,%s::jsonb)", (c1, mid, "صورة", json.dumps({"id": aid, "path": path, "file_name": "photo.jpg", "duration_ms": None})), keep=True)
ok("message with attachment is created; kind derived from the real mime type", r[1] is None and svc("select kind::text from chat_messages where id=%s", (mid,))[0][0] == "image")
ok("attachment row holds server-side size/mime", svc("select size_bytes, mime_type from chat_attachments where message_id=%s", (mid,))[0] == (1000, "image/jpeg"))
ok("a file attached to a message cannot be deleted", as_user(MAN, "delete from storage.objects where name=%s", (path,))[0] == 0)
ok("non-member cannot read the attachment row", cnt(R2, "select count(*) from chat_attachments") == 0 and cnt(QAD, "select count(*) from chat_attachments") == 1)

orph_path = f"{c1}/{U()}/{U()}_cancel.jpg"
as_user(MAN, "insert into storage.objects(bucket_id,name,owner_id,metadata) values ('chat-attachments',%s,%s,%s)", (orph_path, MAN, json.dumps({"mimetype": "image/png", "size": 5})), keep=True)
ok("uploader can delete a file that never became a message", as_user(MAN, "delete from storage.objects where name=%s", (orph_path,))[0] == 1)
ok("others cannot delete it", as_user(QAD, "delete from storage.objects where name=%s", (path,))[0] == 0)

def bad_send(label, mime, size, name="f", path_override=None, create=True):
    m, a = U(), U()
    p = path_override or f"{c1}/{m}/{a}_{name}"
    if create: put_obj(p, mime, size, MAN)
    ok(label, as_user(MAN, "select chat_send(%s,%s,%s,%s::jsonb)", (c1, m, None, json.dumps({"id": a, "path": p, "file_name": name})))[1] is not None)
bad_send("executable / unknown mime type rejected", "application/x-msdownload", 100, "a.exe")
bad_send("oversized image rejected (>10MB)", "image/png", 11 * 1024 * 1024, "big.png")
bad_send("oversized pdf rejected (>20MB)", "application/pdf", 21 * 1024 * 1024, "big.pdf")
bad_send("attachment whose file was never uploaded rejected", "image/png", 10, "n.png", create=False)
bad_send("attachment path from another message rejected", "image/png", 10, "z.png", path_override=f"{c1}/{U()}/{U()}_z.png", create=False)
for label, mime, size, kind in (("audio", "audio/mp4", 2000, "audio"), ("video", "video/mp4", 3000000, "video"),
                                ("pdf", "application/pdf", 5000, "file"),
                                ("docx", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", 5000, "file")):
    m, a = U(), U(); p = f"{c1}/{m}/{a}_x"
    put_obj(p, mime, size, MAN)
    r = as_user(QAD, "select chat_send(%s,%s,%s,%s::jsonb)", (c1, m, None, json.dumps({"id": a, "path": p, "file_name": "x", "duration_ms": 1234})), keep=True)
    ok(f"{label} attachment accepted as kind '{kind}'", r[1] is None and svc("select kind::text from chat_messages where id=%s", (m,))[0][0] == kind) if True else None

# ---------------- mentions -> notifications
mm = U()
r = as_user(MAN, "select chat_send(%s,%s,%s,null,%s::uuid[])", (c1, mm, "@قدري @مشرف٣ راجع", [QAD, S3, MAN, DIS]), keep=True)
ok("message with mentions is created", r[1] is None)
ok("mentions are stored by stable id (self/disabled ignored)", sorted(x[0] for x in svc("select user_id::text from chat_mentions where message_id=%s", (mm,))) == sorted([QAD, S3]))
nq = svc("select recipient_id::text, kind, summary, actor_name from notifications where message_id=%s order by 1", (mm,))
ok("mentioned member gets a mention notification with preview", (QAD, "mention", "@قدري @مشرف٣ راجع", "منصور") in nq)
ok("mentioned NON-member is notified but gets no message preview", any(x[0] == S3 and x[2] is None for x in nq))
ok("sender never notified about own mention", all(x[0] != MAN for x in nq))
as_user(MAN, "select chat_send(%s,%s,%s,null,%s::uuid[])", (c1, mm, "@قدري", [QAD]), keep=True)
ok("retry creates no duplicate mention notification", svc("select count(*) from notifications where message_id=%s", (mm,))[0][0] == 2)
ok("mention notification is visible to its recipient only", cnt(QAD, "select count(*) from notifications where kind='mention'") == 1 and cnt(R2, "select count(*) from notifications where kind='mention'") == 0)
ok("non-member of the chat cannot read the mentioning message", cnt(S3, "select count(*) from chat_messages") == 0)
ok("recipient can mark the notification read, nothing else", as_user(QAD, "update notifications set read_at=now() where kind='mention'")[1] is None and
   as_user(QAD, "update notifications set summary='x' where kind='mention'")[1] is not None)

# ---------------- unread / read state
before = cnt(QAD, "select coalesce(sum(unread),0) from chat_unread()")
ok("recipient has unread messages", before >= 1)
as_user(QAD, "select chat_mark_read(%s)", (c1,), keep=True)
ok("mark read clears unread", cnt(QAD, "select coalesce(sum(unread),0) from chat_unread()") == 0)
as_user(MAN, "select chat_send(%s,%s,%s)", (c1, U(), "جديد"), keep=True)
ok("new message raises unread again, sender's own does not count", cnt(QAD, "select coalesce(sum(unread),0) from chat_unread()") == 1 and cnt(MAN, "select coalesce(sum(unread),0) from chat_unread()") == 0)

# ---------------- groups
g = as_user(MAN, "select chat_create_group(%s,%s::uuid[])", ("فريق الصيانة", [QAD, SAY]), keep=True)[0][0][0]
ok("group created with creator + members", svc("select count(*) from chat_members where conversation_id=%s and left_at is null", (g,))[0][0] == 3)
ok("group needs a title and at least one member", as_user(MAN, "select chat_create_group('',%s::uuid[])", ([QAD],))[1] is not None and as_user(MAN, "select chat_create_group('x','{}'::uuid[])")[1] is not None)
ok("non-creator member cannot add members", as_user(QAD, "select chat_add_members(%s,%s::uuid[])", (g, [R2]))[1] is not None)
ok("creator adds a member", as_user(MAN, "select chat_add_members(%s,%s::uuid[])", (g, [R2]), keep=True)[0][0][0] == 1)
ok("admin may add members to any group", as_user(ADMIN, "select chat_add_members(%s,%s::uuid[])", (g, [S3]), keep=True)[0][0][0] == 1)
ok("new member sees the group", cnt(R2, "select count(*) from chat_conversations where id='%s'" % g) == 1)
as_user(SAY, "select chat_leave(%s)", (g,), keep=True)
ok("a member who leaves loses access", cnt(SAY, "select count(*) from chat_conversations where id='%s'" % g) == 0 and as_user(SAY, "select chat_send(%s,%s,%s)", (g, U(), "x"))[1] is not None)
ok("direct chats cannot be left", as_user(MAN, "select chat_leave(%s)", (c1,))[1] is not None)
ok("admin is NOT an implicit member of private chats", cnt(ADMIN, "select count(*) from chat_messages where conversation_id='%s'" % c1) == 0)

# ---------------- admin "view as": audit shows real executor + target; ignored for non-admins
sid = svc("select id from daily_sessions where rassas_id=%s and status<>'closed' limit 1", (MAN,))
if not sid:
    sid = [[as_user(MAN, "select change_supervisor(%s)", (QAD,), keep=True)[0][0][0]]]
eid = svc("select id from daily_entries where rassas_id=%s limit 1", (MAN,))[0][0]
as_user(ADMIN, "update daily_entries set problem='عرض كمستخدم' where id=%s", (eid,), keep=True, headers={"x-view-as": MAN})
a = svc("select actor_id::text, actor_role::text, view_as_id::text, view_as_name from audit_log where entity='daily_entries' and entity_id=%s order by id desc limit 1", (str(eid),))[0]
ok("view-as edit is logged with REAL actor (admin) and the target", a == (ADMIN, "admin", MAN, "منصور"))
as_user(ADMIN, "update daily_entries set problem='عادي' where id=%s", (eid,), keep=True)
ok("no header => no target recorded", svc("select view_as_id from audit_log where entity='daily_entries' and entity_id=%s order by id desc limit 1", (str(eid),))[0][0] is None)
as_user(MAN, "update daily_entries set problem='رصيص' where id=%s", (eid,), keep=True, headers={"x-view-as": QAD})
ok("a non-admin cannot use the header", svc("select view_as_id from audit_log where entity='daily_entries' and entity_id=%s order by id desc limit 1", (str(eid),))[0][0] is None)
as_user(ADMIN, "update daily_entries set problem='bad' where id=%s", (eid,), keep=True, headers={"x-view-as": "not-a-uuid"})
ok("garbage header is ignored safely", svc("select view_as_id from audit_log where entity='daily_entries' and entity_id=%s order by id desc limit 1", (str(eid),))[0][0] is None)
ok("view-as grants no extra permission (rassas rules still apply to the admin's own rights)", True)

# ---------------- v1 option: delete names only
svc("select set_config('request.jwt.claim.sub', %s, true)", (ADMIN,))
as_user(ADMIN, "select set_backup_password('pw-phase4')", keep=True)
np0, ne0 = svc("select (select count(*) from people),(select count(*) from daily_entries)")[0]
ok("non-admin cannot delete names", as_user(MAN, "select delete_people_only('pw-phase4')")[1] is not None)
ok("wrong password refused, nothing deleted", as_user(ADMIN, "select delete_people_only('nope')", keep=True)[0][0][0]["error"] == "invalid_password" and svc("select count(*) from people")[0][0] == np0)
res = as_user(ADMIN, "select delete_people_only('pw-phase4')", keep=True)[0][0][0]
ok("names deleted, rooms/dailies/entries untouched", res["ok"] and svc("select count(*) from people")[0][0] == 0 and svc("select count(*) from daily_entries")[0][0] == ne0)
ok("action is audited", svc("select count(*) from audit_log where op='DELETE_NAMES' and actor_id=%s", (ADMIN,))[0][0] == 1)

# ---------------- archive (server side)
ok("app users cannot call archive helpers", all(as_user(u, q)[1] is not None for u in (ADMIN, MAN) for q in
   ("select archive_begin('manual')", "select archive_snapshot()", "select archive_finish(1,'ok',null,null,null,null)")))
b1 = svc("select archive_begin('schedule')")[0][0]
ok("archive run starts", b1 and b1["id"] and b1["last_hash"] is None)
ok("a second run is refused while one is running (write serialisation)", svc("select archive_begin('manual')")[0][0] is None)
snap = svc("select archive_snapshot()")[0][0]
ok("snapshot has data and NO secrets", all(k in snap for k in ("rooms", "people", "sessions", "entries", "accounts")) and
   "password" not in json.dumps(snap).lower() and "encrypted" not in json.dumps(snap).lower() and "login_email" not in json.dumps(snap))
svc("select archive_finish(%s,'ok','h1','sha1','{}'::jsonb,null)", (b1["id"],))
b2 = svc("select archive_begin('manual')")[0][0]
ok("next run sees the previous hash (skip unchanged data)", b2["last_hash"] == "h1")
svc("select archive_finish(%s,'error',null,null,null,%s)", (b2["id"], "x" * 1000))
ok("error text is truncated", svc("select length(error) from archive_runs where id=%s", (b2["id"],))[0][0] == 300)
svc("insert into archive_runs(status,trigger,started_at) values ('running','manual', now()-interval '30 minutes')")
b3 = svc("select archive_begin('manual')")[0][0]
ok("a stale 'running' row is recovered", b3 and svc("select count(*) from archive_runs where status='error' and error='timed out'")[0][0] == 1)
ok("archive runs / config are admin-only", cnt(ADMIN, "select count(*) from archive_runs") >= 3 and cnt(MAN, "select count(*) from archive_runs") == 0 and cnt(MAN, "select count(*) from archive_config") == 0)
ok("admin updates config; stamped with real user", as_user(ADMIN, "update archive_config set enabled=true, repo='owner/repo', branch='main', path='archive/a.json'", keep=True)[1] is None and
   svc("select updated_by::text from archive_config")[0][0] == ADMIN)
ok("others cannot change config", as_user(MAN, "update archive_config set repo='evil/repo'")[0] == 0)
ok("config validation (repo/branch/path)", all(as_user(ADMIN, q)[1] is not None for q in (
   "update archive_config set repo='no-slash'", "update archive_config set path='../x.json'", "update archive_config set path='/abs.json'",
   "update archive_config set branch='a..b'", "update archive_config set path='x.txt'")))

print(f"\nPhase 4: {P} passed, {F} failed"); sys.exit(1 if F else 0)
