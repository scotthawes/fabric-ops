#!/usr/bin/env bash
# Illustrative. Pack: 2026-11-26.1 (2026-11-26). Not runnable from fabric-ops (ADR 0001);
# the corporate work repo runs it against its own copy. Exit non-zero on the first class of
# failure it finds, printing every offending path. Read-only: it edits nothing.
#
#   bash checks/check-pack.sh
#
# Rules, in the order the contract names them (spec/0002-contract.md §9):
#   1. VERSION exists and its pack version matches every file header
#   2. every file header carries "Pack: 2026-11-26.1"
#   3. no *.tf exists anywhere in the pack
#   4. every GUID is the all-zero placeholder
#   5. no secret-shaped string, unless the file defines or detects it
#   6. every relative Markdown link resolves
#   7. every file is indexed in README.md
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

EXPECTED="2026-11-26.1"
ZERO_GUID="00000000-0000-0000-0000-000000000000"
fail=0

ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s — %s\n' "$1" "$2"; fail=1; }

files() {
  find . -type f ! -path './.git/*' | sed 's|^\./||' | sort
}

echo "version"
if [ ! -f VERSION ]; then
  bad "VERSION" "missing"
else
  declared=$(sed -n 's/^[Pp]ack:[[:space:]]*//p' VERSION | head -1 | tr -d '[:space:]')
  if [ "$declared" = "$EXPECTED" ]; then
    ok "VERSION declares $EXPECTED"
  else
    bad "VERSION" "declares '${declared:-nothing}', expected '$EXPECTED'"
  fi
fi

echo "headers"
header_hits=0
while IFS= read -r f; do
  [ "$f" = "VERSION" ] && continue
  if head -n 8 "$f" | grep -Fq "Pack: $EXPECTED"; then
    :
  else
    bad "$f" "header lacks 'Pack: $EXPECTED' (first 8 lines)"
    header_hits=1
  fi
done < <(files)
[ "$header_hits" -eq 0 ] && ok "every file header carries Pack: $EXPECTED"

echo "terraform"
tf=$(find . -type f -name '*.tf' ! -path './.git/*' | sed 's|^\./||' | sort)
if [ -n "$tf" ]; then
  while IFS= read -r f; do bad "$f" "a real .tf exists; only *.tf.tmpl belongs here"; done < <(printf '%s\n' "$tf")
else
  ok "no *.tf in the pack"
fi

echo "guids"
bad_guids=""
while IFS= read -r f; do
  while IFS= read -r g; do
    [ -z "$g" ] && continue
    [ "$g" = "$ZERO_GUID" ] && continue
    case " $bad_guids " in
      *" $g "*) ;;
      *) bad_guids="$bad_guids $g"; bad "$f" "non-placeholder GUID $g" ;;
    esac
  done < <(grep -Eo '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' "$f" | sort -u)
done < <(files)
[ -z "$bad_guids" ] && ok "every GUID is $ZERO_GUID"

echo "secrets"
# forbid.md names the forbidden strings; this script detects them. Both are exempt.
secret_hits=0
while IFS= read -r f; do
  case "$f" in
    forbid.md|checks/check-pack.sh) continue ;;
  esac
  if grep -nE 'client_secret|AccountKey|(^|[^A-Za-z])PAT([^A-Za-z]|$)|password=' "$f" >/dev/null 2>&1; then
    bad "$f" "secret-shaped string (client secret / account key / PAT / password=)"
    secret_hits=1
  fi
  case "$f" in
    .env|.env.*|*.pem|*.key|id_rsa*)
      bad "$f" "credential-shaped file"
      secret_hits=1
      ;;
  esac
done < <(files)
[ "$secret_hits" -eq 0 ] && ok "no secret-shaped strings or credential files"

echo "links"
bad_links=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  while IFS= read -r raw; do
    [ -z "$raw" ] && continue
    target=${raw#']('}
    target=${target%')'}
    case "$target" in
      http*|https*|mailto:*|'#'*|'') continue ;;
    esac
    target=${target%%#*}
    [ -z "$target" ] && continue
    if [ ! -e "$dir/$target" ]; then
      bad "$f" "broken relative link -> $target"
      bad_links=1
    fi
  done < <(grep -Eo '\]\([^)]*\)' "$f")
done < <(find . -type f -name '*.md' ! -path './.git/*' | sed 's|^\./||' | sort)
[ "$bad_links" -eq 0 ] && ok "every relative Markdown link resolves"

echo "index"
unindexed=0
while IFS= read -r f; do
  [ "$f" = "README.md" ] && continue
  if ! grep -Fq "$f" README.md; then
    bad "$f" "not indexed in README.md"
    unindexed=1
  fi
done < <(files)
[ "$unindexed" -eq 0 ] && ok "every file is indexed in README.md"

echo
if [ "$fail" -ne 0 ]; then
  echo "pack check FAILED — fix the paths above"
  exit 1
fi
echo "pack check passed ($EXPECTED)"
exit 0
