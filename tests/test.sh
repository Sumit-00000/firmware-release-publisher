#!/bin/bash
# Orchestrates grading: start gateway, run pytest, emit reward 0/1.

mkdir -p /logs/verifier

rm -f /app/releases.duckdb
rm -f /app/distribution-gateway/data/*.json
pkill -f "distribution-gateway/server.js" 2>/dev/null || true
sleep 0.5

node /app/distribution-gateway/server.js &
GW=$!
sleep 2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd /app
python3 -m pytest -rA -p no:cacheprovider "$SCRIPT_DIR/test_outputs.py"
code=$?

kill "$GW" 2>/dev/null || true

if [ "$code" -eq 0 ]; then
  echo 1 > /logs/verifier/reward.txt
else
  echo 0 > /logs/verifier/reward.txt
fi
echo "reward: $(cat /logs/verifier/reward.txt)"