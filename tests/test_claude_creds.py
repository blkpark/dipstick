#!/usr/bin/env python3
"""Credential stores that drift apart: which copy is read, and which get healed.
Run it directly — `python3 tests/test_claude_creds.py`.

The failure this guards: a wrapper restored an old login snapshot over every
store, its refresh token already dead server-side, and the gauge went dark while
a live copy sat in a sibling store. File stores only — the keychain is not
touched.
"""
import importlib.util
import json
import os
import sys
import tempfile
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_loader(
    "dipstick", importlib.machinery.SourceFileLoader("dipstick", os.path.join(ROOT, "tools/dipstick")))
dip = importlib.util.module_from_spec(spec)
sys.modules["dipstick"] = dip
spec.loader.exec_module(dip)

now_ms = int(time.time() * 1000)

with tempfile.TemporaryDirectory() as tmp:
    def store(name, rt, exp_ms, extra=None):
        path = os.path.join(tmp, name)
        doc = {"claudeAiOauth": {"accessToken": "AT-" + rt, "refreshToken": rt,
                                 "expiresAt": exp_ms, "subscriptionType": "max"},
               "mcpOAuth": extra or {"srv": 1}}
        with open(path, "w") as fh:
            json.dump(doc, fh)
        return path

    live = store("live.json", "RT_NEW", now_ms + 3600_000)
    dead = store("dead.json", "RT_OLD", now_ms - 3600_000, {"keep": "me"})
    other = store("other.json", "RT_OTHER", now_ms + 7200_000)

    # The latest expiry wins, wherever it sits in the list.
    cred, _ = dip.claude_credentials(services=["__none__"], files=[dead, live, other])
    assert cred["file"] == other, cred["file"]

    # A token known to work is handed to the expired sibling only.
    cred, _ = dip.claude_credentials(services=["__none__"], files=[live])
    cred["stores"] = [("file", live), ("file", dead), ("file", other)]
    dip.claude_propagate(cred)
    healed = json.load(open(dead))
    assert healed["claudeAiOauth"]["refreshToken"] == "RT_NEW"
    assert healed["mcpOAuth"] == {"keep": "me"}, "the rest of the document must survive"
    assert os.stat(dead).st_mode & 0o777 == 0o600
    assert json.load(open(other))["claudeAiOauth"]["refreshToken"] == "RT_OTHER", \
        "a live, different session is somebody else's, not a stale copy"

print("ok")
