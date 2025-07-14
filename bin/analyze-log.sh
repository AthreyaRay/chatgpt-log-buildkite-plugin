#!/bin/bash
set -euo pipefail

LOG_FILE="$1"
MODEL="gpt-4o"
MAX_TOKENS=1500

LOG_CHUNK=$(tail -n 600 "$LOG_FILE")

RESPONSE=$(curl -sS https://api.openai.com/v1/chat/completions \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL\",
    \"messages\": [
      {\"role\": \"system\", \"content\": \"You are a CI assistant. Analyze this Buildkite job log and explain what went wrong and how to fix it.\"},
      {\"role\": \"user\", \"content\": \"$LOG_CHUNK\"}
    ],
    \"temperature\": 0.3,
    \"max_tokens\": $MAX_TOKENS
  }")

echo "$RESPONSE" | jq -r '.choices[0].message.content'
