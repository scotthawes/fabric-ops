#!/usr/bin/env bash
# Illustrative. Pack: 2026-11-26.2 (2026-11-26). Not runnable from fabric-ops (ADR 0001);
# the corporate work repo runs it against its own copy. Exit non-zero on the first class of
# failure it finds, printing every offending path. Read-only: it edits nothing.
#
#   bash checks/check-pack.sh
#
# Rules, in the order the contract names them (spec/0002-contract.md §9):
#   1. VERSION exists and its pack version matches every file header
#   2. every file header carries "Pack: 2026-11-26.2"
#   3. no *.tf exists anywhere in the pack
#   4. every GUID is the all-zero placeholder
#   5. no secret-shaped string, unless the file defines or detects it
#   6. every relative Markdown link resolves
#   7. every file is indexed in README.md
#   8. every OQ id in spec/0003 appears in spec/0004
#   9. every contract stage (§6) is named in runbook/troubleshooting.md
#  10. every skeletons/scripts/*.py.tmpl is wired into cicd.yml.tmpl or README.md
#
# Rules 8–10 are completeness, not formatting: a stage with no entry, a question with no
# absorption and a script nothing calls are all silent gaps the tenant cannot report back.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

EXPECTED=$(sed -n 's/^[Pp]ack:[[:space:]]*//p' VERSION 2>/dev/null | head -1 | tr -d '[:space:]')
[ -n "$EXPECTED" ] || { echo "FAIL  VERSION is missing or has no pack: line"; exit 1; }
ZERO_GUID="00000000-0000-0000-0000-000000000000"
fail=0

ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s — %s\n' "$1" "$2"; fail=1; }

files() {
  # __pycache__/*.pyc are local by-products, not pack content.
  find . -type f ! -path './.git/*' ! -path '*/__pycache__/*' ! -name '*.pyc' | sed 's|^\./||' | sort
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

echo "questions"
# Each open question is absorbed by an assumption row: an id named nowhere is an unhandled fact.
if [ ! -f spec/0003-open-questions.md ]; then
  bad "spec/0003-open-questions.md" "missing; cannot check that open questions are absorbed"
elif [ ! -f spec/0004-assumptions.md ]; then
  bad "spec/0004-assumptions.md" "missing; cannot absorb the open questions"
else
  oq_missing=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if ! grep -Fq "$id" spec/0004-assumptions.md; then
      bad "spec/0004-assumptions.md" "open question $id from spec/0003 is not absorbed"
      oq_missing=1
    fi
  done < <(grep -Eo 'OQ-[0-9]+' spec/0003-open-questions.md | sort -u)
  [ "$oq_missing" -eq 0 ] && ok "every open question is absorbed in spec/0004-assumptions.md"
fi

echo "stages"
# The stage names are the contract's (§6), matched as whole words. A runbook that calls a
# stage something else is reported, not accommodated: two names for one stage are two causes.
if [ ! -f runbook/troubleshooting.md ]; then
  bad "runbook/troubleshooting.md" "missing; every stage must be diagnosable"
else
  stage_missing=0
  for stage in Build Probe Platform Domains Nonprod PlanProd Prod; do
    if ! grep -qw "$stage" runbook/troubleshooting.md; then
      bad "runbook/troubleshooting.md" "contract stage '$stage' has no troubleshooting entry"
      stage_missing=1
    fi
  done
  [ "$stage_missing" -eq 0 ] && ok "every contract stage is diagnosable in runbook/troubleshooting.md"
fi

echo "scripts"
# A script nothing invokes is dead weight. The pipeline names the deployed file, README the template.
unwired=0
for script in skeletons/scripts/probe.py.tmpl \
              skeletons/scripts/assert_plan.py.tmpl \
              skeletons/scripts/preflight.py.tmpl \
              skeletons/scripts/deploy_items.py.tmpl; do
  name=${script##*/}
  deployed=${name%.tmpl}
  if grep -Fq "$name" skeletons/pipeline/cicd.yml.tmpl README.md 2>/dev/null ||
     grep -Fq "$deployed" skeletons/pipeline/cicd.yml.tmpl README.md 2>/dev/null; then
    :
  else
    bad "$script" "not referenced by skeletons/pipeline/cicd.yml.tmpl or README.md"
    unwired=1
  fi
done
[ "$unwired" -eq 0 ] && ok "every script is wired into the pipeline or README.md"

echo
if [ "$fail" -ne 0 ]; then
  echo "pack check FAILED — fix the paths above"
  exit 1
fi
echo "pack check passed ($EXPECTED)"
exit 0
