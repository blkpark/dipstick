# dipstick

*[한국어 README](README_KOR.md)*

How much is left on your AI coding subscriptions, and which one you're using right now.

Claude Code, Codex and Antigravity each meter you on rolling windows, each shows
it somewhere different, and none of them tells you the thing you actually want to
know before starting a long job: *is there enough left, and if not, when does it
come back?* dipstick reads all three, in one place, in a menu bar.

```
Claude Max                         MAIN   you@example.com
    5-hour window   76%   resets in 2h 47m
    7-day window    28%   resets in 2h 29m   ◂ binds
Codex Pro                                 you@example.com
    7-day window    82%   resets in 4d 22h
```

**It never sends a prompt to a model.** Asking a model "how much do I have left"
would open a fresh rate-limit window — the opposite of what a gauge should do. So
every reading is either a passive file read or a metering endpoint that costs no
quota.

## What it reads

| Subscription | Source | Cost |
|---|---|---|
| Codex | `rate_limits` recorded in session rollout files | none — local files |
| Claude Code | `GET /api/oauth/usage`, the endpoint the CLI itself uses | none — metering only |
| Antigravity (`agy`) | `RetrieveUserQuotaSummary` on the running agent's local RPC | none — localhost |

Codex rollouts can run to several GB, so parses are cached by inode; after the
first run a refresh takes about a second.

## Install

Requires macOS 13+ and Python 3.9+ (the system one is fine). No packages.

```sh
git clone https://github.com/blkpark/dipstick.git && cd dipstick
install -m 755 tools/dipstick ~/.local/bin/dipstick     # CLI
./scripts/bundle.sh && cp -R build/Dipstick.app /Applications/   # menu bar app
./scripts/install-login.sh    # optional: start at login (--remove to undo)
```

Reading the Claude figure needs its OAuth token, which lives in your login
keychain, so the first run raises a macOS access prompt. The token is used to
call Anthropic's own usage endpoint and is never stored or sent anywhere else.
dipstick only ever reads it — refreshing is Claude Code's job, and doing it here
would rotate the token out from under a running session. If the reading says
*logged out*, `claude auth login` restores it.

## Use

```sh
dipstick                    # text report
dipstick --serve            # web UI on 127.0.0.1:8787, click to set main
dipstick --html out.html    # self-contained page, no server
dipstick --json             # machine-readable snapshot
dipstick --set-main claude-max   # or any key from --json, or "auto"
dipstick --main-cmd         # launch prefix for whatever is main right now
dipstick --lang ko|en       # Korean or English (the web UI has a switch)
```

`--main-cmd` is the point of the "main" setting. Pick a subscription once, then
let your launch command ask which one to use instead of hardcoding it:

```sh
$(dipstick --main-cmd) "$(cat prompt.txt)"
# -> env CODEX_HOME="…/codex-accounts/…/home" codex "$(cat prompt.txt)"
```

## How it decides what's a problem

**Time-to-recovery, not the raw percentage.** 30% left on a 5-hour window and 30%
on a 7-day window are different problems: the first clears over lunch, the second
holds for days. Windows resetting within the hour are labelled *recovering* and
stop driving the verdict; whichever window actually constrains new work is
labelled *binds*.

Levels are `GO` (60%+), `TIGHT` (30–60%), `LOW` (under 30%) and `BLOCKED`. These
are starting points, not physics — a run's cost varies enormously by codebase and
task. dipstick records every reading, so once you have a day or two of history the
burn rate it shows is a better guide than the defaults.

## Config

Everything below is optional — `~/.config/dipstick/config.json`:

```json
{
  "reserve": { "Claude": 30 },
  "policy": {
    "Codex Pro": ["2nd", "when the smaller plan runs short"]
  },
  "imminent_minutes": 60
}
```

**`reserve`** keeps a percentage of a subscription for your own use. If you chat
with Claude on the same plan your agents run on, a floor stops background jobs
from eating the conversation you're having. Below the floor a subscription is held
back — unless you name it as main, which is an explicit override that burns
through it and says so on the page.

**`policy`** is your own note per subscription (a rank, a rule, whatever order you
work by). dipstick only displays it; it does not act on it.

## Pace, and how the launch target is chosen

Every reading also shows its **pace surplus**: how far it sits from where a
perfectly even spend would have it (`94% (+4)` — the window just reset, so 94%
is level pace, not headroom; 40% the day before a reset is plenty). Verdicts are
graded against this surplus, not against fixed percentages.

`--main-cmd` picks the subscription a new launch should burn, in one of two modes
(`--main-mode`, or the toggle in the web header):

- **weighted** (default) — best pace among subscriptions that are free to burn,
  with the main getting 10%p of stickiness so a marginal difference never flips
  the account mid-day. Pools with a `reserve` floor are *kept for their own use*
  and never enter the pick unless you named one as main — that is the opt-in.
- **pinned** — absolute for dispatch. The main takes every anonymous pick,
  overriding the pace calculation and the reserve floor: concentrating spend is
  the whole point of the mode. A typed `--vendor` is the one thing it does not
  cross — the human already chose the tool, and answering with another vendor's
  CLI would replace the command, not concentrate spend.

Either way it only answers "which one, right now". It still launches nothing.

`--vendor codex` pins the **tool** while the account still follows the pick.
If the main is pinned to a different vendor, the pick stays inside the vendor
you asked for — what you typed wins. That makes bare `codex` / `claude`
routable through a shell function:

```sh
_dipstick_run() {
  local want="$1"; shift
  local pre
  if pre="$(command dipstick --main-cmd --vendor "$want" 2>/dev/null)" \
     && [[ "$pre" == *"$want"* ]]; then
    eval "$pre" '"$@"'
  else
    command "$want" "$@"    # wrong vendor, or no dipstick — never break the command
  fi
}
codex()  { _dipstick_run codex  "$@" }
claude() { _dipstick_run claude "$@" }
```

The `$pre == *$want*` check is defence in depth: the CLI already keeps a typed
vendor, so the guard only matters if an older dipstick answers — the prefix is
used only when it names the vendor you asked for, and the plain binary runs
otherwise.

A typed vendor also bypasses the reserve-floor exclusion: the floor exists to
protect your own use of that tool from background jobs, and you typing the
command *is* that protected use. The anonymous pick (no `--vendor`) still keeps
reserved pools out unless one is the main.

## What it doesn't do

It doesn't launch anything, queue anything, or switch subscriptions for you. It
reports and it remembers which one you picked. Deciding is yours, and anything
that dispatches work should stay whatever you already use.

## License

MIT — see [LICENSE](LICENSE).
