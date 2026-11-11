#!/bin/bash
set -u
queries=(
 "org:microsoft fabric in:name,description,topics"
 "topic:microsoft-fabric"
 "\"microsoft fabric\" in:description stars:>2"
 "fabric-cicd in:name,description"
 "fabric workspace in:description stars:>3"
 "fabric capacity in:description stars:>3"
 "fabric lakehouse in:description stars:>3"
 "fabric terraform in:description,readme"
)
: > raw.jsonl
for q in "${queries[@]}"; do
  gh api -X GET search/repositories -f q="$q" -f per_page=100 -f sort=stars 2>/dev/null >> raw.jsonl || echo "FAILED: $q" >&2
  echo >> raw.jsonl
done
wc -l raw.jsonl
