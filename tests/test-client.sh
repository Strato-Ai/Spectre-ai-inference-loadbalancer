#!/bin/bash
# configs/client-test/test-client.sh
# Spectre automated test suite — 10 tests
# Usage: ./test-client.sh <LB_HOSTNAME> <API_KEY>
set -euo pipefail

HOST="${1:?Usage: $0 <hostname> <api_key>}"
KEY="${2:?Usage: $0 <hostname> <api_key>}"
BASE="https://${HOST}"
PASS=0
FAIL=0
TOTAL=10

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1 — $2"; FAIL=$((FAIL + 1)); }

echo "=== Spectre Test Suite ==="
echo "Target: $BASE"
echo ""

# Test 1: Health endpoint (no auth)
echo "[1/$TOTAL] Health endpoint"
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' "$BASE/health")
[[ "$HTTP" == "200" ]] && pass "GET /health → 200" || fail "GET /health → $HTTP" "expected 200"

# Test 2: Reject request without API key
echo "[2/$TOTAL] Auth rejection"
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' "$BASE/v1/models")
[[ "$HTTP" == "401" ]] && pass "GET /v1/models (no key) → 401" || fail "→ $HTTP" "expected 401"

# Test 3: Accept request with valid API key
echo "[3/$TOTAL] Auth acceptance"
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' -H "X-Api-Key: $KEY" "$BASE/v1/models")
[[ "$HTTP" == "200" ]] && pass "GET /v1/models (valid key) → 200" || fail "→ $HTTP" "expected 200"

# Test 4: List models
echo "[4/$TOTAL] List models"
MODELS=$(curl -sk -H "X-Api-Key: $KEY" "$BASE/v1/models" | jq -r '.data[].id' 2>/dev/null)
[[ -n "$MODELS" ]] && pass "Models found: $(echo $MODELS | tr '\n' ', ')" || fail "No models returned" "check backends"

# Test 5: Default route chat completion
echo "[5/$TOTAL] Default route chat"
RESP=$(curl -sk -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
    -d '{"model":"any","messages":[{"role":"user","content":"Say hello"}],"max_tokens":20}' \
    "$BASE/v1/chat/completions" 2>/dev/null)
CONTENT=$(echo "$RESP" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
[[ -n "$CONTENT" ]] && pass "Chat response received" || fail "No chat response" "check backend health"

# Test 6: Model-specific route (qwen)
echo "[6/$TOTAL] Route to qwen"
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
    "$BASE/route/qwen/v1/chat/completions")
[[ "$HTTP" == "200" ]] && pass "Route /route/qwen/ → 200" || fail "→ $HTTP" "qwen backend may be down"

# Test 7: Model-specific route (llama)
echo "[7/$TOTAL] Route to llama"
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
    "$BASE/route/llama/v1/chat/completions")
[[ "$HTTP" == "200" ]] && pass "Route /route/llama/ → 200" || fail "→ $HTTP" "llama backend may be down"

# Test 8: Model-specific route (deepseek)
echo "[8/$TOTAL] Route to deepseek"
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
    "$BASE/route/deepseek/v1/chat/completions")
[[ "$HTTP" == "200" ]] && pass "Route /route/deepseek/ → 200" || fail "→ $HTTP" "deepseek backend may be down"

# Test 9: Streaming response
echo "[9/$TOTAL] Streaming (SSE)"
STREAM=$(curl -sk -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Count to 3"}],"max_tokens":30,"stream":true}' \
    "$BASE/v1/chat/completions" --max-time 60 2>/dev/null | head -5)
if echo "$STREAM" | grep -q "data:"; then
    pass "SSE stream received"
else
    fail "No SSE data" "check proxy_buffering off"
fi

# Test 10: Invalid route returns error
echo "[10/$TOTAL] Invalid model route"
HTTP=$(curl -sk -o /dev/null -w '%{http_code}' -H "X-Api-Key: $KEY" -H "Content-Type: application/json" \
    -d '{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}' \
    "$BASE/route/nonexistent/v1/chat/completions")
# Should still proxy to default upstream (no 404 at NGINX level)
[[ "$HTTP" =~ ^(200|502)$ ]] && pass "Invalid model falls through to default" || fail "→ $HTTP" "unexpected status"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL/$TOTAL failed ==="
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
