#!/bin/bash
# Refresh the Fabric GitHub sweep behind repos.tsv and github-index.md.
# Run from this directory: bash refresh.sh
#
# Needs `gh` authenticated (the search API is rate-limited to 30 queries/minute when
# authenticated, 10 when anonymous and the anonymous quota is unusable for this).
# Writes all.tsv (every match) and repos.tsv (filtered to genuinely Fabric-related repos).
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
  gh api -X GET search/repositories -f q="$q" -f per_page=100 -f sort=stars >> raw.jsonl 2>/dev/null \
    || echo "FAILED: $q" >&2
  echo >> raw.jsonl
done

# Normalise, dedupe by full name, newest first by stars.
jq -rs '
  map(.items) | add | unique_by(.full_name)
  | map({stars: .stargazers_count,
         pushed: (.pushed_at | split("T")[0]),
         arch: (.archived | tostring),
         lic: (.license.spdx_id // "none"),
         name: .full_name,
         topics: ((.topics // []) | join(",")),
         desc: (.description // "" | gsub("[\t\n]"; " ") | .[0:200])})
  | .[] | [.stars, .pushed, .arch, .lic, .name, .topics, .desc] | @tsv
' raw.jsonl | sort -t$'\t' -k1,1nr > all.tsv

# Drop the unrelated projects that share the word "fabric" (Minecraft, Service Fabric,
# Hyperledger, design systems), then require a real Microsoft Fabric signal.
awk -F'\t' '
{
  t = tolower($1" "$5" "$6" "$7);
  if (t ~ /service.fabric|hyperledger|fabricmc|minecraft|fabric\.js|fabricjs|react.native|ui.fabric|design.system|blockchain|cisco|hyprland|tsumiki|mod loader|neoforge|quilt|spigot|bukkit/) next;
  if (t ~ /microsoft.fabric|ms.fabric|onelake|fabric.cicd|fabric lakehouse|fabric warehouse|fabric workspace|fabric capacit|semantic.link|fabcon|dp-600|dp-700|fabric.pipeline|fabric item|fabric.data/) print;
}' all.tsv > filtered.tsv

{ printf 'stars\tpushed\tarchived\tlicence\tfull_name\ttopics\tdescription\n'; cat filtered.tsv; } > repos.tsv

echo "all:      $(wc -l < all.tsv)"
echo "filtered: $(wc -l < filtered.tsv)"
echo
echo "Review before trusting: repos with a recent creation date, >100 stars and near-zero forks"
echo "are usually promotion artefacts — check created_at and forks_count before citing one."
