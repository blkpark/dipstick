#!/usr/bin/env python3
"""Credit spending derived from a balance or a running total.
Run it directly — `python3 tests/test_credits.py`.

Nobody reports "credits spent today", so the gauge subtracts consecutive
readings. What must not count as spending: a top-up (balance rises) and a month
rollover (used total drops back toward zero).
"""
import datetime
import importlib.util
import os
import sqlite3
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_loader(
    "dipstick", importlib.machinery.SourceFileLoader("dipstick", os.path.join(ROOT, "tools/dipstick")))
dip = importlib.util.module_from_spec(spec)
sys.modules["dipstick"] = dip
spec.loader.exec_module(dip)

db = sqlite3.connect(":memory:")
db.executescript(dip.SCHEMA)
t0 = datetime.datetime(2026, 10, 20, 0, 0)

def put(sub, kind, hours, value):
    db.execute("INSERT INTO credits(taken_at,sub,kind,value) VALUES(?,?,?,?)",
               ((t0 + datetime.timedelta(hours=hours)).isoformat(timespec="seconds"), sub, kind, value))

# balance: 100 the night before, spend 10, top up 50, spend 5  -> 15 spent today
put("Codex Pro", "balance", -2, 100)
put("Codex Pro", "balance", 1, 90)
put("Codex Pro", "balance", 2, 140)
put("Codex Pro", "balance", 3, 135)
spent, since = dip.credit_spent(db, "Codex Pro", "balance", t0)
assert spent == 15 and since is None, (spent, since)

# used: 30 before the period, 32, 35, then month rolls over and reads 4 -> 2+3+4 = 9
put("Claude Max", "used", -1, 30)
put("Claude Max", "used", 1, 32)
put("Claude Max", "used", 2, 35)
put("Claude Max", "used", 3, 4)
spent, since = dip.credit_spent(db, "Claude Max", "used", t0)
assert spent == 9, spent

# a series that begins inside the period says so
put("New", "balance", 5, 50)
put("New", "balance", 6, 47)
spent, since = dip.credit_spent(db, "New", "balance", t0)
assert spent == 3 and since == t0 + datetime.timedelta(hours=5), (spent, since)

# nothing recorded -> no figure, not zero
assert dip.credit_spent(db, "None", "balance", t0) == (None, None)

print("ok")
