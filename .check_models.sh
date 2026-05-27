#!/bin/bash
# helper — outputs which .models entries are no longer free on OpenRouter
# Usage: bash .check_models.sh


FREE_IDS=$(curl -fsSL 'https://openrouter.ai/api/v1/models' \
  | python3 -c "
import json,sys
data=json.load(sys.stdin)
for m in data['data']:
    p=m.get('pricing',{})
    prompt=str(p.get('prompt','1'))
    comp=str(p.get('completion','1'))
    if prompt=='0' and comp=='0':
        print(m['id'])
")

echo "=== Currently FREE on OpenRouter ==="
echo "$FREE_IDS" | sort

echo ""
echo "=== Entries in .models NOT in current free list ==="
grep -Eo '^[a-z0-9._/-]+:free' .models | while read slug; do
    if ! echo "$FREE_IDS" | grep -qx "$slug"; then
        echo "REMOVE: $slug"
    fi
done

echo ""
echo "=== Free :free models on OpenRouter NOT in .models ==="
echo "$FREE_IDS" | grep ':free$' | while read slug; do
    if ! grep -q "^$slug" .models; then
        echo "ADD: $slug"
    fi
done

echo ""
echo "=== Done ==="
