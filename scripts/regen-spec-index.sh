#!/usr/bin/env bash
set -euo pipefail
out="spec/index.json"
echo '{"harp_version": "0.1", "sections": [' > "$out"
first=1
for f in spec/[0-9]*.md; do
  id=$(awk '/^id:/ {print $2; exit}' "$f")
  status=$(awk '/^status:/ {print $2; exit}' "$f")
  normative=$(awk '/^normative:/ {print $2; exit}' "$f")
  tier=$(awk '/^tier:/ {print $2; exit}' "$f")
  must=$(grep -c '\bMUST\b' "$f" || true)
  [[ "$tier" == "null" ]] && tier_json="null" || tier_json="\"$tier\""
  [[ $first -eq 0 ]] && echo "," >> "$out"
  first=0
  printf '  {"id": "%s", "file": "%s", "status": "%s", "normative": %s, "tier": %s, "must_count": %d}' \
    "$id" "${f#spec/}" "$status" "$normative" "$tier_json" "$must" >> "$out"
done
echo "" >> "$out"
echo ']}' >> "$out"
chmod 0644 "$out"
