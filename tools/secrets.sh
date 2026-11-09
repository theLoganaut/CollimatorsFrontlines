#!/usr/bin/env bash
# Local secrets (tools/steam/config.local.sh: the Discord feedback webhook) travel in git
# encrypted, as tools/steam/secrets.enc, under a key that lives only on Logan's machines.
#
#   tools/secrets.sh lock          encrypt config.local.sh -> secrets.enc (then commit it)
#   tools/secrets.sh unlock        decrypt secrets.enc -> config.local.sh
#   tools/secrets.sh status        is the key here, and do the two files match?
#   tools/secrets.sh key           print this machine's key (to copy it to the other machine)
#   tools/secrets.sh key <key>     save a key copied from the other machine
#   tools/secrets.sh newkey        make a key (first machine only; re-lock afterwards)
#
# The key is at ~/.config/frontlines/secrets.key (Git Bash: the same under your Windows home).
# tools/steam/config.sh unlocks by itself when config.local.sh is missing, so a fresh pull
# on a machine with the key builds with the webhook. Needs openssl (macOS and Git Bash have it).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAIN="$ROOT/tools/steam/config.local.sh"
ENC="$ROOT/tools/steam/secrets.enc"
KEY="${FRONTLINES_SECRETS_KEY:-$HOME/.config/frontlines/secrets.key}"
CIPHER=(-aes-256-cbc -pbkdf2 -iter 200000 -a -A)

die() { echo "secrets: $*" >&2; exit 1; }
need_key() { [[ -s "$KEY" ]] || die "no key at $KEY. Copy it from the other machine: tools/secrets.sh key <key>"; }
decrypt() { openssl enc -d "${CIPHER[@]}" -pass "file:$KEY" -in "$ENC"; }

case "${1:-status}" in
	lock)
		need_key
		[[ -f "$PLAIN" ]] || die "nothing to lock: $PLAIN is missing"
		# Same contents = leave secrets.enc alone (every encryption differs, so it would churn).
		if [[ -f "$ENC" ]] && [[ "$(decrypt 2>/dev/null)" == "$(cat "$PLAIN")" ]]; then
			echo "secrets: secrets.enc is already up to date"; exit 0
		fi
		openssl enc -e "${CIPHER[@]}" -salt -pass "file:$KEY" -in "$PLAIN" -out "$ENC"
		echo >> "$ENC"
		echo "secrets: locked into tools/steam/secrets.enc; commit and push it"
		;;
	unlock)
		need_key
		[[ -f "$ENC" ]] || die "no tools/steam/secrets.enc to unlock"
		out="$(decrypt)" || die "couldn't decrypt: is this the same key as the other machine?"
		printf '%s\n' "$out" > "$PLAIN"
		chmod 600 "$PLAIN" 2>/dev/null || true
		echo "secrets: unlocked into tools/steam/config.local.sh"
		;;
	status)
		[[ -s "$KEY" ]] && echo "key:    $KEY" || echo "key:    missing ($KEY)"
		[[ -f "$ENC" ]] && echo "locked: tools/steam/secrets.enc" || echo "locked: none"
		[[ -f "$PLAIN" ]] && echo "plain:  tools/steam/config.local.sh" || echo "plain:  none"
		if [[ -s "$KEY" && -f "$ENC" && -f "$PLAIN" ]]; then
			if [[ "$(decrypt 2>/dev/null)" == "$(cat "$PLAIN")" ]]; then echo "match:  yes"
			else echo "match:  NO (tools/secrets.sh lock to save local changes, unlock to take the pulled ones)"; fi
		fi
		;;
	key)
		if [[ -n "${2:-}" ]]; then
			mkdir -p "$(dirname "$KEY")"
			printf '%s\n' "$2" > "$KEY"
			chmod 600 "$KEY" 2>/dev/null || true
			echo "secrets: key saved to $KEY"
			[[ -f "$ENC" && ! -f "$PLAIN" ]] && "$0" unlock || true
		else
			need_key; cat "$KEY"
		fi
		;;
	newkey)
		[[ -s "$KEY" ]] && die "a key already exists at $KEY (delete it first to replace it)"
		mkdir -p "$(dirname "$KEY")"
		openssl rand -base64 32 > "$KEY"
		chmod 600 "$KEY" 2>/dev/null || true
		echo "secrets: new key at $KEY; copy it to the other machine (tools/secrets.sh key)"
		;;
	*) sed -n '2,13p' "$0"; exit 1 ;;
esac
