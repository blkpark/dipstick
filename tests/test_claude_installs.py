#!/usr/bin/env python3
"""Multi-account discovery: the keychain entry a CLAUDE_CONFIG_DIR maps to, and
which installs get scanned. Run it directly — `python3 tests/test_claude_installs.py`.

The hash is the load-bearing part: get it wrong and a second subscription is
simply invisible, with no error anywhere to show for it.
"""
import importlib.util
import os
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_loader(
    "dipstick", importlib.machinery.SourceFileLoader("dipstick", os.path.join(ROOT, "tools/dipstick")))
dip = importlib.util.module_from_spec(spec)
sys.modules["dipstick"] = dip
spec.loader.exec_module(dip)

# Measured against a real login: `security dump-keychain` on a machine whose
# default install is /Users/blkpark/.claude carries "Claude Code-credentials-94848a0c".
assert dip.claude_keychain_service("/Users/blkpark/.claude") == "Claude Code-credentials-94848a0c"
# Trailing slashes and relative paths must land on the same entry.
assert dip.claude_keychain_service("/tmp/../tmp/x") == dip.claude_keychain_service("/tmp/x")

with tempfile.TemporaryDirectory() as tmp:
    home = os.path.join(tmp, "second")
    os.mkdir(home)
    dip.CLAUDE_HOMES = [home]
    installs = dict(dip.claude_installs())
    default = os.path.expanduser("~/.claude")
    assert default in installs, "default install must always be scanned"
    assert dip.CLAUDE_KEYCHAINS[0] in installs[default], "default keeps its wrapper fallbacks"
    assert installs[home] == [dip.claude_keychain_service(home)], installs[home]

    dip.CLAUDE_HOMES = [os.path.join(tmp, "missing")]
    assert os.path.join(tmp, "missing") not in dict(dip.claude_installs()), \
        "a configured directory that does not exist is skipped, not guessed at"

# A second install must be named in the launch prefix; the default one must not
# be, or every existing launch command changes shape for no reason.
dip.CLAUDE_HOME_BY_SUB.clear()
assert "CLAUDE_CONFIG_DIR" not in dip.launch_prefix("Claude Max")[0]
dip.CLAUDE_HOME_BY_SUB["Claude Max · work"] = "/tmp/claude-work"
prefix = dip.launch_prefix("Claude Max · work")[0]
assert 'CLAUDE_CONFIG_DIR="/tmp/claude-work"' in prefix, prefix
assert "command claude" in prefix, prefix

print("ok")
