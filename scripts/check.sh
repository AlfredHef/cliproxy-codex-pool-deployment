#!/usr/bin/env bash
set -euo pipefail

api_url="${CLIPROXY_API_URL:-http://127.0.0.1:8317}"
api_key="${CLIPROXY_API_KEY:-}"

echo "== systemd =="
systemctl is-active cliproxy-backend.service

echo "== listeners =="
ss -ltnp | grep -E ':(7890|8317|5173|1455)\b' || true

echo "== proxy =="
curl --connect-timeout 10 --max-time 20 -x http://127.0.0.1:7890 -I https://chatgpt.com/

if [[ -z "$api_key" ]]; then
  echo "CLIPROXY_API_KEY is not set; skipped authenticated API checks." >&2
  exit 0
fi

echo "== models =="
curl --fail --max-time 20 \
  -H "Authorization: Bearer ${api_key}" \
  "${api_url}/v1/models"

echo
echo "== real responses request =="
curl --fail --max-time 120 \
  -H "Authorization: Bearer ${api_key}" \
  -H 'Content-Type: application/json' \
  -d '{"model":"gpt-5.4","input":"Reply with exactly OK.","max_output_tokens":32,"stream":false}' \
  "${api_url}/v1/responses"
echo
