#!/usr/bin/env python3
"""Metering stays display-only; missing plans and unreadable logs stay visible."""
import collections
import datetime
import importlib.machinery
import importlib.util
import io
import json
import pathlib
import sqlite3
import tempfile
import urllib.error
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_loader('dip', importlib.machinery.SourceFileLoader('dip', str(ROOT / 'tools/dipstick')))
dip = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dip)
db = sqlite3.connect(':memory:')
db.executescript(dip.SCHEMA)
dip.LANG = 'en'
dip.now = datetime.datetime(2026, 10, 27, 12)

with tempfile.TemporaryDirectory() as tmp:
    dip.OPENCODE_DIR = tmp
    assert dip.opencode_rows(db) == []
    auth = pathlib.Path(tmp, 'auth.json')
    auth.write_text(json.dumps({'openrouter': {'type': 'api', 'key': 'test-key'}}))
    logs = sqlite3.connect(str(pathlib.Path(tmp, 'opencode.db')))
    logs.execute('CREATE TABLE message(time_created INTEGER, data TEXT)')
    day = dip.now.replace(hour=0)
    def msg(when, provider='opencode', model='zen-free', tokens=None, role='assistant'):
        logs.execute('INSERT INTO message VALUES(?,?)', (when.timestamp() * 1000, json.dumps({
            'role': role, 'providerID': provider, 'modelID': model,
            'tokens': tokens or {'input': 10, 'output': 20, 'reasoning': 5, 'cache': {'read': 30, 'write': 40}}})))
    msg(day + datetime.timedelta(hours=1))
    msg(day - datetime.timedelta(hours=1))
    msg(day + datetime.timedelta(hours=1), model="big-pickle")
    msg(day - datetime.timedelta(days=8))
    msg(day + datetime.timedelta(hours=2), provider='openrouter')
    msg(day + datetime.timedelta(hours=2), model='paid')
    msg(day + datetime.timedelta(hours=2), role='user')
    logs.commit()
    payload = {'data': {'limit_remaining': None, 'usage_daily': 1.25, 'usage_weekly': 4.5, 'is_free_tier': True}}
    def response(req, timeout):
        assert req.full_url == 'https://openrouter.ai/api/v1/key'
        assert req.get_method() == 'GET'
        assert req.get_header('Authorization') == 'Bearer test-key'
        return io.BytesIO(json.dumps(payload).encode())
    with patch.object(dip.urllib.request, 'urlopen', side_effect=response) as get:
        row = dip.opencode_rows(db)[0]
        assert row['windows'] == []
        assert 'today 200' in row['note'] and 'this week 300' in row['note'], row
        cv = dip.credit_view(db, 'OpenCode', row['credit'])
        assert cv['remaining'] is None and cv['today'] == 1.25 and cv['week'] == 4.5
        assert 'key spending limit unset' in dip.credit_text(cv) and 'UTC' in cv['text']
        dip.record_credits(db, [row])  # direct server totals need no derived series
        dip.opencode_rows(db)
        assert get.call_count == 1, 'metering endpoint must be cached'
    # Account/key changes must not reuse a different key's cached reading.
    auth.write_text(json.dumps({'openrouter': {'key': 'different-key'}}))
    failure = urllib.error.HTTPError(dip.OPENROUTER_KEY_URL, 401, '', {}, None)
    with patch.object(dip.urllib.request, 'urlopen', side_effect=failure):
        row2 = dip.opencode_rows(db)[0]
        assert row2['credit'] is None and 'HTTP 401' in row2['note']
    # Failed polling retains its last value and explains its age.
    db.execute("UPDATE apicache SET fetched_at=fetched_at-360")
    auth.write_text(json.dumps({'openrouter': {'key': 'test-key'}}))
    with patch.object(dip.urllib.request, 'urlopen', side_effect=failure):
        stale = dip.opencode_rows(db)[0]
        assert stale['credit']['today'] == 1.25 and 'last reading' in stale['note']
    # Missing usage fields are unknown, not zero; malformed numeric values fail visibly.
    auth.write_text(json.dumps({'openrouter': {'key': 'third-key'}}))
    with patch.object(dip.urllib.request, 'urlopen', return_value=io.BytesIO(b'{"data":{"usage_daily":"bad"}}')):
        assert 'ValueError' in dip.opencode_rows(db)[0]['note']
    auth.write_text(json.dumps({'openrouter': {'key': 123}}))
    assert 'auth file unreadable' in dip.opencode_rows(db)[0]['note']
    auth.write_text('{}')
    logs.execute("UPDATE message SET data='not-json'")
    logs.commit()
    assert 'logs unreadable' in dip.opencode_rows(db)[0]['note']
    logs.close()
    # Display rows cannot influence weighted dispatch.
    dip.set_setting(db, 'main', 'Codex Pro')
    assert dip.pick_launch(db, [row])[0] != 'OpenCode'
    rendered = dip.render_html(db, [row], collections.Counter())
    assert 'OpenRouter' in rendered and 'key spending limit unset' in rendered
    assert 'set-main' not in rendered
    healthy = {'sub': 'Codex Pro', 'account': 'fixture', 'pool': None, 'note': '',
               'windows': [{'name': 'week', 'remaining': 100, 'minutes': 10080,
                            'resets': None, 'surplus': 20, 'verdict': ('GO', 'fixture')}]}
    with patch.object(dip, 'token_view', return_value=[]):
        html = dip.render_html(db, [healthy, row], collections.Counter())
    assert 'every subscription has headroom' in html
    mcp_spec = importlib.util.spec_from_loader('meter_mcp', importlib.machinery.SourceFileLoader('meter_mcp', str(ROOT / 'mcp/dipstick-mcp')))
    mcp = importlib.util.module_from_spec(mcp_spec)
    mcp_spec.loader.exec_module(mcp)
    with patch.object(mcp, 'snapshot', return_value={'subscriptions': [{'sub': 'OpenCode', 'displayOnly': True, 'windows': []}]}):
        assert mcp.tool_can_i_start({'minutes': 30})['verdicts'] == []

snap = {'provider': {'id': 'zai'}, 'authenticated': True, 'unavailableReason': 'no_plan'}
with patch.object(dip, '_zcode_snapshots', return_value={'zai': (snap, dip.now.timestamp() * 1000)}):
    rows = dip.zcode_rows()
    assert len(rows) == 1 and rows[0]['windows'] == [] and 'no plan' in rows[0]['note']
    snap['authenticated'] = False
    assert 'login required' in dip.zcode_rows()[0]['note']
print('ok')
