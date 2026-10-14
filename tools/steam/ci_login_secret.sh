#!/usr/bin/env bash
# Copies SteamCMD's saved login to the clipboard, ready to paste into the
# GitHub secret STEAM_CONFIG_VDF (.github/workflows/steam.yml). Keeps only the
# parts SteamCMD needs (Accounts, ConnectCache) from the Mac's config.vdf, which
# is too big for a GitHub secret whole, and base64-encodes them. Prints nothing
# secret. If the login has expired, run tools/steam_release.sh --login first.
set -euo pipefail
SRC="$HOME/Library/Application Support/Steam/config/config.vdf"
[[ -f "$SRC" ]] || { echo "No SteamCMD login at $SRC. Run tools/steam_release.sh --login first." >&2; exit 1; }
python3 - "$SRC" <<'PY' | base64 | tr -d '\n' | pbcopy
import re, sys
toks = re.findall(r'"((?:[^"\\]|\\.)*)"|([{}])', open(sys.argv[1], encoding="utf-8", errors="replace").read())
i = 0
def parse():
    global i
    d = []
    while i < len(toks):
        s, b = toks[i]
        if b == "}":
            i += 1
            return d
        i += 1
        s2, b2 = toks[i]
        i += 1
        d.append((s, parse() if b2 == "{" else s2))
    return d
def get(d, k):
    return next(v for kk, v in d if kk == k)
steam = get(get(get(get(parse(), "InstallConfigStore"), "Software"), "Valve"), "Steam")
keep = [(k, v) for k, v in steam if k in ("Accounts", "ConnectCache")]
if not any(k == "ConnectCache" for k, _ in keep):
    sys.exit("No saved login (ConnectCache) in config.vdf. Run tools/steam_release.sh --login first.")
def dump(d, ind):
    out = ""
    for k, v in d:
        out += '%s"%s"\n%s{\n%s%s}\n' % (ind, k, ind, dump(v, ind + "\t"), ind) if isinstance(v, list) else '%s"%s"\t\t"%s"\n' % (ind, k, v)
    return out
sys.stdout.write(dump([("InstallConfigStore", [("Software", [("Valve", [("Steam", keep)])])])], ""))
PY
echo "Copied. Paste it into GitHub -> Settings -> Secrets and variables -> Actions -> STEAM_CONFIG_VDF."
