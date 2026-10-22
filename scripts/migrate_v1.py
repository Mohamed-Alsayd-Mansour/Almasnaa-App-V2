#!/usr/bin/env python3
"""
Almasnaa v1 -> v2 migration + initial account seed.

Run from a trusted machine (NEVER from the app). Needs:
  SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY   (Admin API: create auth users)
  SUPABASE_DB_URL                            (direct Postgres URL, for the one atomic transaction)
  SEED_PASSWORD_ADMIN, SEED_PASSWORD_MANSOUR, SEED_PASSWORD_QADRI, SEED_PASSWORD_SAYYAD
Usage:
  python migrate_v1.py --input almasnaa-data.json [--backup-dir backups] [--report report.json]
Local test (no Supabase, stub auth.users):  add --local-test (uses SUPABASE_DB_URL only).

Properties: data rows are applied in one SQL transaction; Auth accounts are created through Supabase's
separate Admin API and are reused on retries. V1 UUIDs are preserved and duplicate data rows are skipped.
The v1 file is copied and hashed before parsing and is never modified.
"""
import argparse, hashlib, json, os, re, shutil, sys, datetime as dt
from collections import Counter, defaultdict
import psycopg2, psycopg2.extras

# username, display name, role, env var holding the initial password
ACCOUNTS = [
    ("Mansour", "Mansour", "admin",      "SEED_PASSWORD_ADMIN"),
    ("منصور",   "منصور",   "rassas",     "SEED_PASSWORD_MANSOUR"),
    ("قدري",    "قدري",    "supervisor", "SEED_PASSWORD_QADRI"),
    ("الصياد",  "الصياد",  "supervisor", "SEED_PASSWORD_SAYYAD"),
]
DEFAULT_LINK = ("منصور", "قدري")


def load_dotenv_file(path):
    """Load simple KEY=VALUE entries from a local .env file without overriding OS environment."""
    if not os.path.isfile(path):
        return
    with open(path, "r", encoding="utf-8-sig") as env_file:
        for line_no, raw_line in enumerate(env_file, start=1):
            line = raw_line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:].lstrip()
            key, separator, raw_value = line.partition("=")
            key = key.strip()
            if not separator or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                raise SystemExit(f"Invalid .env entry on line {line_no}; expected KEY=VALUE.")
            # Environment variables set in the shell take precedence over .env.
            if key in os.environ:
                continue
            value = raw_value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
                quote = value[0]
                value = value[1:-1]
                if quote == '"':
                    value = value.replace(r"\\n", "\\n").replace(r"\\r", "\\r").replace(r'\\"', '"').replace(r"\\\\", "\\")
            else:
                value = re.split(r"\\s+#", value, maxsplit=1)[0].rstrip()
            os.environ[key] = value


def validate_environment(local_test):
    required = ["SUPABASE_DB_URL"] + [account[3] for account in ACCOUNTS]
    if not local_test:
        required += ["SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"]
    missing = [name for name in required if not os.environ.get(name, "").strip()]
    if missing:
        raise SystemExit(
            "Missing required values: " + ", ".join(missing) +
            ". Copy .env.example to .env, fill the values locally, and run again. "
            "Never commit or share .env."
        )
    for _, username, _, envvar in ACCOUNTS:
        password = os.environ.get(envvar, "")
        if len(password) < 6:
            raise SystemExit(f"{envvar} for account {username} must be at least 6 characters.")


def find_auth_user_id(base, key, email):
    """Find an existing deterministic Auth user so retries can recover after a DB rollback."""
    import requests

    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    page = 1
    per_page = 100
    while page <= 100:
        response = requests.get(
            f"{base.rstrip('/')}/auth/v1/admin/users",
            headers=headers,
            params={"page": page, "per_page": per_page},
            timeout=30,
        )
        if response.status_code >= 300:
            raise SystemExit(
                "Could not inspect existing Supabase Auth users "
                f"(HTTP {response.status_code}). Check SUPABASE_URL and "
                "SUPABASE_SERVICE_ROLE_KEY locally; no key or response body was printed."
            )
        payload = response.json()
        users = payload.get("users", []) if isinstance(payload, dict) else []
        for user in users:
            if str(user.get("email", "")).strip().lower() == email.lower():
                return str(user["id"])
        if len(users) < per_page:
            return None
        page += 1
    raise SystemExit("Too many Auth users to safely locate the migration account; stop for manual review.")


ENTRY_COLS = ["id","daily_session_id","room_id","room_name_snapshot","piece_count_snapshot","is_external","is_order",
 "merchant_name","customer_name","numbering","carpenter","service","installer","supervisor","repairer","wrap_location",
 "has_specifications","specifications_text","special_piece_count","problem","is_partial","part_name","partial_piece_count",
 "original_deficiencies","current_deficiencies","original_missing_count","current_missing_count",
 "last_deficiency_update_at","created_at","updated_at"]
ROOM_COLS = ["id","name","piece_count","glass_piece_count","partition_piece_count","partition_count","marble_piece_count","created_at","updated_at"]


def ensure_auth_users(conn, local_test):
    """Returns {username: uuid}. Creates missing accounts; never resets an existing password."""
    ids = {}
    cur = conn.cursor()
    for username, display, role, envvar in ACCOUNTS:
        cur.execute("select id from public.profiles where lower(btrim(username)) = lower(btrim(%s)) and deleted_at is null", (username,))
        row = cur.fetchone()
        if row:
            ids[username] = str(row[0]); continue
        pw = os.environ.get(envvar)
        if not pw:
            raise SystemExit(f"Missing {envvar} for account {username}; refusing to continue.")
        email = f"u_{hashlib.sha1(username.encode()).hexdigest()[:12]}@almasnaa.invalid"

        if local_test:
            cur.execute("select id from auth.users where lower(email) = lower(%s)", (email,))
            existing_auth = cur.fetchone()
            if existing_auth:
                uid = str(existing_auth[0])
            else:
                cur.execute(
                    "insert into auth.users(email, encrypted_password) "
                    "values (%s, crypt(%s, gen_salt('bf'))) returning id",
                    (email, pw),
                )
                uid = str(cur.fetchone()[0])
        else:
            import requests
            base = os.environ["SUPABASE_URL"].rstrip("/")
            key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
            # Auth is managed separately from the SQL transaction. Reuse a deterministic
            # Auth account if an earlier attempt created it but rolled back the DB transaction.
            existing_id = find_auth_user_id(base, key, email)
            if existing_id:
                uid = existing_id
            else:
                response = requests.post(
                    f"{base}/auth/v1/admin/users",
                    headers={"apikey": key, "Authorization": f"Bearer {key}"},
                    json={"email": email, "password": pw, "email_confirm": True},
                    timeout=30,
                )
                if response.status_code >= 300:
                    existing_id = find_auth_user_id(base, key, email)
                    if existing_id:
                        uid = existing_id
                    else:
                        raise SystemExit(
                            f"Supabase Auth refused to create account {username} "
                            f"(HTTP {response.status_code}); no secret response body was printed."
                        )
                else:
                    uid = str(response.json()["id"])

        cur.execute(
            "insert into public.profiles(id, username, display_name, role, must_change_password) "
            "values (%s,%s,%s,%s,%s)",
            (uid, username, display, role, role == "admin"),
        )
        ids[username] = uid
    return ids


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--backup-dir", default="backups")
    ap.add_argument("--report", default="migration-report.json")
    ap.add_argument("--local-test", action="store_true")
    a = ap.parse_args()

    # Load local credentials before reading the input or opening a DB connection.
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    load_dotenv_file(os.path.join(repo_root, ".env"))
    validate_environment(a.local_test)

    try:
        with open(a.input, "rb") as source_file:
            raw = source_file.read()
    except OSError as exc:
        raise SystemExit(f"Cannot read input file {a.input!r}: {exc}") from exc
    sha = hashlib.sha256(raw).hexdigest()
    os.makedirs(a.backup_dir, exist_ok=True)
    bpath = os.path.join(a.backup_dir, f"almasnaa-v1-{dt.datetime.now():%Y%m%d-%H%M%S}-{sha[:8]}.json")
    shutil.copyfile(a.input, bpath)
    doc = json.loads(raw)
    if doc.get("app") != "almasnaa" or doc.get("version") != 1:
        sys.exit("input is not an Almasnaa v1 export (app=almasnaa, version=1)")
    d = doc["data"]
    before = {k: len(d[k]) for k in ("rooms", "people", "sessions", "entries")}

    conn = psycopg2.connect(os.environ["SUPABASE_DB_URL"])
    conn.autocommit = False
    cur = conn.cursor(cursor_factory=psycopg2.extras.DictCursor)
    cur.execute("select set_config('app.audit_skip','on',true), set_config('app.bulk','on',true)")

    ids = ensure_auth_users(conn, a.local_test)
    rassas, qadri, sayyad = ids["منصور"], ids["قدري"], ids["الصياد"]
    sup_by_name = {"قدري": qadri, "الصياد": sayyad}
    rassas_by_name = {"منصور": rassas}
    review = []

    # default link منصور -> قدري (only if the rassas has no current link)
    cur.execute("insert into public.rassas_supervisor_links(rassas_id, supervisor_id, changed_by) "
                "select %s,%s,%s where not exists (select 1 from public.rassas_supervisor_links where rassas_id=%s and effective_to is null)",
                (rassas, qadri, ids["Mansour"], rassas))

    # rooms / people (ids preserved)
    psycopg2.extras.execute_values(cur, f"insert into public.rooms ({','.join(ROOM_COLS)}) values %s on conflict (id) do nothing",
                                   [tuple(r.get(c) for c in ROOM_COLS) for r in d["rooms"]])
    psycopg2.extras.execute_values(cur, "insert into public.people (id,name,role,created_at) values %s on conflict (id) do nothing",
                                   [(p["id"], p["name"], p["role"], p["created_at"]) for p in d["people"]])

    # ownership is derived ONLY from names written in the v1 rows themselves
    by_session = defaultdict(list)
    for e in d["entries"]: by_session[e["daily_session_id"]].append(e)

    sess_rows = []
    for s in d["sessions"]:
        es = by_session.get(s["id"], [])
        ras = Counter(e["installer"] for e in es if e["installer"] in rassas_by_name)
        sup = Counter(e["supervisor"] for e in es if e["supervisor"] in sup_by_name)
        r_id = rassas_by_name[ras.most_common(1)[0][0]] if ras else None
        top = sup.most_common(2)
        s_id = None
        if top and (len(top) == 1 or top[0][1] > top[1][1]):
            s_id = sup_by_name[top[0][0]]
        elif top:
            review.append(("daily_sessions", s["id"], "supervisor tie between entries"))
        if r_id is None: review.append(("daily_sessions", s["id"], "no rassas found in entries"))
        if s_id is None and not top: review.append(("daily_sessions", s["id"], "no supervisor found in entries"))
        status = s["status"] if s["status"] in ("active", "closed") else "closed"
        sess_rows.append((s["id"], s["day_name"], s["date"], s["start_time"], s.get("end_time"), status,
                          r_id, s_id, "منصور" if r_id else "", next((n for n, u in sup_by_name.items() if u == s_id), ""), s["id"]))
    psycopg2.extras.execute_values(cur,
        "insert into public.daily_sessions (id,day_name,date,start_time,end_time,status,rassas_id,supervisor_id,"
        "rassas_name_snapshot,supervisor_name_snapshot,legacy_id) values %s on conflict (id) do nothing", sess_rows)

    room_ids = {r["id"] for r in d["rooms"]}
    ent_rows = []
    for e in d["entries"]:
        r_id = rassas_by_name.get(e["installer"]); s_id = sup_by_name.get(e["supervisor"])
        nr = False
        if e["installer"] and r_id is None: review.append(("daily_entries", e["id"], f"unknown rassas name: {e['installer']}")); nr = True
        if e["supervisor"] and s_id is None: review.append(("daily_entries", e["id"], f"unknown supervisor name: {e['supervisor']}")); nr = True
        if not e["installer"] and not e["supervisor"]:
            review.append(("daily_entries", e["id"], "no rassas/supervisor recorded in v1 (kept as historical, owner not guessed)")); nr = True
        legacy_room = e.get("room_id") if e.get("room_id") and e["room_id"] not in room_ids else None
        base = {c: e.get(c) for c in ENTRY_COLS}
        if base["room_id"] not in room_ids: base["room_id"] = None
        if legacy_room: review.append(("daily_entries", e["id"], "room was deleted in v1; snapshot kept, room_id empty"))
        ent_rows.append(tuple(base[c] for c in ENTRY_COLS) + (r_id, s_id, nr, legacy_room))
    cols = ENTRY_COLS + ["rassas_id", "supervisor_id", "needs_review", "legacy_room_id"]
    psycopg2.extras.execute_values(cur, f"insert into public.daily_entries ({','.join(cols)}) values %s on conflict (id) do nothing", ent_rows)

    psycopg2.extras.execute_values(cur, "insert into public.migration_review(entity,entity_id,reason) values %s on conflict do nothing", review)

    # verification (inside the same transaction)
    ids_in = {"rooms": [r["id"] for r in d["rooms"]], "people": [p["id"] for p in d["people"]],
              "daily_sessions": [s["id"] for s in d["sessions"]], "daily_entries": [e["id"] for e in d["entries"]]}
    after = {}
    for t, lst in ids_in.items():
        cur.execute(f"select count(*) from public.{t} where id = any(%s::uuid[])", (lst,))
        after[t] = cur.fetchone()[0]
    ok = (after["rooms"] == before["rooms"] and after["people"] == before["people"] and
          after["daily_sessions"] == before["sessions"] and after["daily_entries"] == before["entries"])
    if not ok:
        conn.rollback(); sys.exit(f"verification FAILED, rolled back. before={before} after={after}")

    cur.execute("select count(*) from public.daily_entries where id = any(%s::uuid[]) and rassas_id = %s", (ids_in["daily_entries"], rassas))
    to_rassas = cur.fetchone()[0]
    cur.execute("select supervisor_id, count(*) from public.daily_entries where id = any(%s::uuid[]) group by 1", (ids_in["daily_entries"],))
    per_sup = {str(k): v for k, v in cur.fetchall()}
    report = {"v1_file_sha256": sha, "v1_backup_copy": bpath, "counts_v1": before, "counts_v2_for_these_ids": after,
              "entries_owned_by_mansour": to_rassas,
              "entries_by_supervisor_id": {("قدري" if k == qadri else "الصياد" if k == sayyad else k): v for k, v in per_sup.items()},
              "needs_review": [{"entity": x[0], "id": x[1], "reason": x[2]} for x in review],
              "accounts_created_or_found": {k: v for k, v in ids.items()}}
    conn.commit()
    json.dump(report, open(a.report, "w", encoding="utf8"), ensure_ascii=False, indent=2)
    print(json.dumps({k: report[k] for k in ("counts_v1", "counts_v2_for_these_ids", "entries_owned_by_mansour", "entries_by_supervisor_id")}, ensure_ascii=False, indent=1))
    print(f"needs_review: {len(review)} item(s) -> {a.report}")


if __name__ == "__main__":
    main()
