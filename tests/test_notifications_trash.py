#!/usr/bin/env python3
"""0007 tests: notification archive / trash / restore / permanent delete (per-recipient, RLS-enforced)."""
import os, sys, psycopg2
conn = psycopg2.connect(os.environ["SUPABASE_DB_URL"]); conn.autocommit = False
cur = conn.cursor(); P = F = 0
def ok(n, c, x=""):
    global P, F
    if c: P += 1; print("PASS", n)
    else: F += 1; print("FAIL", n, x)
def svc(sql, a=None):
    cur.execute("reset role"); cur.execute(sql, a); r = cur.fetchall() if cur.description else None
    conn.commit(); return r
def as_user(u, sql, a=None, keep=True):
    cur.execute("reset role"); cur.execute("select set_config('request.jwt.claim.sub',%s,true)", (u,))
    cur.execute("set local role authenticated")
    try:
        cur.execute(sql, a); r = cur.fetchall() if cur.description else cur.rowcount
        conn.commit() if keep else conn.rollback(); return r, None
    except psycopg2.Error as e:
        conn.rollback(); return None, str(e)
uid = lambda n: str(svc("select id from profiles where username=%s and deleted_at is null", (n,))[0][0])
ADMIN, MAN, QAD = uid("Mansour"), uid("منصور"), uid("قدري")

# generate notifications: an admin edits an entry owned by MAN -> MAN (and other admins) are notified
eid = svc("select id from daily_entries where rassas_id=%s limit 1", (MAN,))[0][0]
for i in range(3):
    as_user(ADMIN, "update daily_entries set problem=%s where id=%s", (f"إشعار {i}", eid))
mine = [r[0] for r in svc("select id from notifications where recipient_id=%s order by id desc limit 3", (MAN,))]
ok("recipient has notifications to manage", len(mine) == 3)
other = svc("select id from notifications where recipient_id<>%s limit 1", (MAN,))[0][0]

n1, n2, n3 = mine
r, e = as_user(MAN, "update notifications set archived_at=now() where id=%s", (n1,))
ok("archive moves a notification to the archive", e is None and r == 1 and svc("select archived_at is not null and deleted_at is null from notifications where id=%s", (n1,))[0][0])
as_user(MAN, "update notifications set archived_at=null where id=%s", (n1,))
ok("un-archive brings it back to the inbox", svc("select archived_at is null from notifications where id=%s", (n1,))[0][0])

r, e = as_user(MAN, "update notifications set deleted_at=now() where id=%s", (n2,))
ok("delete = soft delete (row kept in trash, not erased)", r == 1 and svc("select deleted_at is not null from notifications where id=%s", (n2,))[0][0])
ok("restore from trash", as_user(MAN, "update notifications set deleted_at=null where id=%s", (n2,))[0] == 1 and svc("select deleted_at is null from notifications where id=%s", (n2,))[0][0])

ok("cannot permanently delete a notification that is not in the trash", as_user(MAN, "delete from notifications where id=%s", (n3,))[0] == 0 and svc("select count(*) from notifications where id=%s", (n3,))[0][0] == 1)
as_user(MAN, "update notifications set deleted_at=now() where id=%s", (n3,))
ok("permanent delete works from the trash", as_user(MAN, "delete from notifications where id=%s", (n3,))[0] == 1 and svc("select count(*) from notifications where id=%s", (n3,))[0][0] == 0)

ok("cannot archive/delete/restore someone else's notification", all(as_user(MAN, q, (other,))[0] == 0 for q in (
   "update notifications set archived_at=now() where id=%s", "update notifications set deleted_at=now() where id=%s")))
svc("update notifications set deleted_at=now() where id=%s", (other,))
ok("cannot permanently delete someone else's trashed notification", as_user(MAN, "delete from notifications where id=%s", (other,))[0] == 0)
ok("only read_at/archived_at/deleted_at are writable", as_user(MAN, "update notifications set audit_id=null where id=%s", (n1,))[1] is not None and
   as_user(MAN, "update notifications set recipient_id=%s where id=%s", (QAD, n1))[1] is not None)
ok("bulk: archive several at once", as_user(MAN, "update notifications set archived_at=now() where recipient_id=%s and deleted_at is null and archived_at is null", (MAN,))[0] >= 1)
print(f"\nNotifications 0007: {P} passed, {F} failed"); sys.exit(1 if F else 0)
