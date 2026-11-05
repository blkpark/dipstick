#!/usr/bin/env python3
"""Only one Codex account takes launches. Run it directly —
`python3 tests/test_codex_single.py`.

The failure this guards: pace moving work to another Codex account when the
chosen one runs short. Running out is a stop, not a switch.
"""
import importlib.machinery
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
scores = {"Codex ProLite": 1.0, "Codex Pro": 90.0, "Claude Max": 20.0}
dip.sub_score = lambda group: scores[group[0]["sub"]]
dip.binding_score = lambda windows: 0
rows = [{"sub": s, "account": "a", "windows": []} for s in scores]

# Two accounts, nothing chosen, main elsewhere: refuse rather than guess.
dip.set_setting(db, "main", "Claude Max")
assert dip.pick_launch(db, rows, "codex")[0] is None
assert dip.pick_launch(db, rows)[0] == "Claude Max"

# A Codex main is the choice, even with the other account far ahead on pace.
dip.set_main(db, "Codex ProLite")
assert dip.pick_launch(db, rows, "codex")[0] == "Codex ProLite"
scores["Claude Max"] = 0.0
assert dip.pick_launch(db, rows)[0] == "Codex ProLite"

# Leaving Codex keeps the choice; an anonymous pick never rides the other one.
dip.set_main(db, "Claude Max")
assert dip.codex_selected(db, rows) == "Codex ProLite"
assert dip.pick_launch(db, rows)[0] != "Codex Pro"

# Changing it moves the single choice, and a Codex main with it.
dip.set_main(db, "Codex ProLite")
dip.set_codex(db, "Codex Pro")
assert dip.get_setting(db, "main") == "Codex Pro"
assert dip.pick_launch(db, rows, "codex")[0] == "Codex Pro"

# One account needs no choosing.
assert dip.codex_selected(db, rows[:1]) == "Codex ProLite"
# Only the chosen account is shown; with none chosen all stay, to choose from.
assert [r["sub"] for r in dip.one_codex(db, rows)] == ["Codex Pro", "Claude Max"]
dip.set_setting(db, "codex_account", "")
dip.set_setting(db, "main", "Claude Max")
assert len(dip.one_codex(db, rows)) == 3

print("ok")
