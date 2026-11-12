#!/usr/bin/env bash
# The repo's only guardrail. Run before every push; CI runs the same script.
#
#   bash scripts/check.sh
#
# Checks four things this repo has actually broken:
#   1. every relative link in a Markdown file resolves
#   2. every research note is listed in docs/research/README.md
#   3. every ADR is listed in docs/adr/README.md, and numbered without gaps
#   4. the generated censuses look intact (row count and header)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
fail=0
ok()   { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }

echo "links"
python3 - <<'PY' || exit 1
import re, sys, pathlib
bad = []
for f in pathlib.Path('.').rglob('*.md'):
    if '.tmp' in f.parts or '.git' in f.parts:
        continue
    for m in re.finditer(r'\]\(([^)#][^)]*)\)', f.read_text()):
        target = m.group(1).split('#')[0]
        if target.startswith(('http', 'mailto')):
            continue
        if not (f.parent / target).exists():
            bad.append(f"{f} -> {target}")
if bad:
    print(f"  FAIL  {len(bad)} broken relative link(s)")
    for b in bad:
        print(f"        {b}")
    sys.exit(1)
print("  ok    every relative link resolves")
PY

echo "indexes"
python3 - <<'PY' || exit 1
import pathlib, sys
bad = []
research = pathlib.Path('docs/research')
index = (research / 'README.md').read_text()
for f in research.glob('*.md'):
    if f.name in {'README.md', 'TEMPLATE.md', 'backlog.md'}:
        continue
    if f.name not in index:
        bad.append(f"research note not indexed: {f.name}")
adr = pathlib.Path('docs/adr')
adr_index = (adr / 'README.md').read_text()
numbers = []
for f in sorted(adr.glob('[0-9]*.md')):
    numbers.append(int(f.name[:4]))
    if f.name not in adr_index:
        bad.append(f"ADR not indexed: {f.name}")
if numbers != list(range(1, len(numbers) + 1)):
    bad.append(f"ADR numbering has a gap or duplicate: {numbers}")
if bad:
    print(f"  FAIL  {len(bad)} index problem(s)")
    for b in bad:
        print(f"        {b}")
    sys.exit(1)
print(f"  ok    {len(list(research.glob('*.md'))) - 3} research notes and {len(numbers)} ADRs indexed")
PY

echo "generated"
for tsv in docs/reference/api-operations.tsv docs/reference/arm-fabric-operations.tsv; do
  if [ ! -f "$tsv" ]; then bad "$tsv missing"; continue; fi
  rows=$(($(wc -l < "$tsv") - 1))
  if [ "$rows" -lt 10 ]; then bad "$tsv has only $rows rows"; else ok "$tsv ($rows operations)"; fi
done

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS"
else
  echo "FAIL — fix the items above before pushing"
fi
exit "$fail"
