"""Firebase REST helper for the evidence script: a "second device" that signs in
with real Email/Password accounts and talks to the real Firestore through the
public REST API, so every call is checked by the deployed security rules.

usage: python3 -B tools/fs.py COMMAND [args...]
  signup EMAIL PASSWORD                 create an Auth account (prints uid)
  create-record EMAIL PASSWORD FIRST LAST ROLE
  record EMAIL PASSWORD                 print users/{uid} as that user
  post EMAIL PASSWORD NAME TEXT         create a message (server timestamp)
  messages EMAIL PASSWORD               list the board, oldest first
  count-text EMAIL PASSWORD TEXT        how many messages have exactly TEXT
  count-author EMAIL PASSWORD           how many messages this user wrote
  signed-out-read                       read the board with no sign-in
  cross-edit EMAIL PASSWORD DOC_ID      edit somebody else's message
"""
import json
import pathlib
import re
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent


def config():
    project = (ROOT / ".firebase_project").read_text().strip()
    key = None
    opts = ROOT / "lib" / "firebase_options.dart"
    if opts.exists():
        text = opts.read_text()
        web = re.search(r"FirebaseOptions\s+web\s*=\s*FirebaseOptions\((.*?)\);", text, re.S)
        block = web.group(1) if web else text
        m = re.search(r"apiKey:\s*'([^']+)'", block)
        key = m.group(1) if m else None
    if not key:
        gs = json.loads((ROOT / "android" / "app" / "google-services.json").read_text())
        key = gs["client"][0]["api_key"][0]["current_key"]
    return project, key


PROJECT, API_KEY = config()
DOCS = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"
AUTH = "https://identitytoolkit.googleapis.com/v1/accounts"


def call(method, url, body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read() or b"{}")
        except ValueError:
            return e.code, {}


def sign_in(email, password):
    status, out = call("POST", f"{AUTH}:signInWithPassword?key={API_KEY}",
                       {"email": email, "password": password, "returnSecureToken": True})
    if status != 200:
        sys.exit(f"sign-in failed for {email}: {status} {out}")
    return out["localId"], out["idToken"]


def val(v):
    for k in ("stringValue", "timestampValue", "integerValue", "booleanValue"):
        if k in v:
            return v[k]
    return None


def flat(doc):
    f = doc.get("fields", {})
    return {k: val(v) for k, v in f.items()}


def commit_create(token, name, fields, ts_field):
    body = {"writes": [{
        "update": {"name": name, "fields": {k: {"stringValue": v} for k, v in fields.items()}},
        "updateTransforms": [{"fieldPath": ts_field, "setToServerValue": "REQUEST_TIME"}],
        "currentDocument": {"exists": False},
    }]}
    return call("POST", f"{DOCS}:commit", body, token)


def list_messages(token):
    q = {"structuredQuery": {"from": [{"collectionId": "messages"}],
                             "orderBy": [{"field": {"fieldPath": "createdAt"}, "direction": "ASCENDING"}]}}
    status, out = call("POST", f"{DOCS}:runQuery", q, token)
    rows = [r["document"] for r in out if isinstance(r, dict) and "document" in r] if status == 200 else []
    return status, rows


def main():
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "signup":
        email, pw = args
        status, out = call("POST", f"{AUTH}:signUp?key={API_KEY}",
                           {"email": email, "password": pw, "returnSecureToken": True})
        print(out.get("localId") if status == 200 else f"signup failed {status} {out}")
    elif cmd == "create-record":
        email, pw, first, last, role = args
        uid, token = sign_in(email, pw)
        status, out = commit_create(token, f"projects/{PROJECT}/databases/(default)/documents/users/{uid}",
                                    {"uid": uid, "firstName": first, "lastName": last, "role": role},
                                    "registrationDateTime")
        print(f"HTTP {status}", "" if status == 200 else json.dumps(out))
    elif cmd == "record":
        email, pw = args
        uid, token = sign_in(email, pw)
        status, out = call("GET", f"{DOCS}/users/{uid}", token=token)
        print(f"// GET users/{uid} as {email}: HTTP {status}")
        print(json.dumps({"name": out.get("name"), "fields": flat(out)} if status == 200 else out, indent=2))
    elif cmd == "post":
        email, pw, name, text = args
        uid, token = sign_in(email, pw)
        import uuid
        doc_id = "rest_" + uuid.uuid4().hex[:16]
        status, out = commit_create(token, f"projects/{PROJECT}/databases/(default)/documents/messages/{doc_id}",
                                    {"text": text, "authorUid": uid, "authorName": name}, "createdAt")
        print(f"HTTP {status} messages/{doc_id}", "" if status == 200 else json.dumps(out))
    elif cmd == "messages":
        email, pw = args
        _, token = sign_in(email, pw)
        status, rows = list_messages(token)
        print(f"// runQuery messages orderBy createdAt as {email}: HTTP {status}, {len(rows)} documents")
        for d in rows:
            f = flat(d)
            print(json.dumps({"id": d["name"].rsplit("/", 1)[1], **f}))
    elif cmd == "count-text":
        email, pw, text = args
        _, token = sign_in(email, pw)
        _, rows = list_messages(token)
        print(sum(1 for d in rows if flat(d).get("text") == text))
    elif cmd == "count-author":
        email, pw = args
        uid, token = sign_in(email, pw)
        _, rows = list_messages(token)
        print(sum(1 for d in rows if flat(d).get("authorUid") == uid))
    elif cmd == "signed-out-read":
        status, out = call("GET", f"{DOCS}/messages?pageSize=1")
        print(f"// GET messages with NO sign-in: HTTP {status}")
        print(json.dumps(out.get("error", out), indent=2))
    elif cmd == "cross-edit":
        email, pw, doc_id = args
        _, token = sign_in(email, pw)
        status, out = call("PATCH", f"{DOCS}/messages/{doc_id}?updateMask.fieldPaths=text",
                           {"fields": {"text": {"stringValue": "Edited by an intruder over REST"}}}, token)
        print(f"// PATCH messages/{doc_id} as {email} (not the author): HTTP {status}")
        print(json.dumps(out.get("error", out), indent=2))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
