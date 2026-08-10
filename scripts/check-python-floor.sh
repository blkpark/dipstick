#!/bin/sh
# The menu bar app is a GUI process: it does not inherit a shell PATH, so the
# CLI's `#!/usr/bin/env python3` resolves to the system Python, not whatever a
# pyenv shim put in front of it. Syntax newer than that floor parses fine in a
# terminal and dies only inside the app, where the failure is silent -- the
# status item simply shows nothing. So the floor is checked, not assumed.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
for py in /usr/bin/python3 python3.9 python3; do
  command -v "$py" >/dev/null 2>&1 || continue
  "$py" -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$root/tools/dipstick" || {
    echo "tools/dipstick does not parse under $("$py" -V 2>&1)" >&2; exit 1; }
  echo "parses under $("$py" -V 2>&1)"
  exit 0
done
echo "no python found to check against" >&2; exit 1
