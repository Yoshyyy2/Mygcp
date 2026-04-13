#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads even when piped via curl =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Log & Error Handler =====
LOG_FILE="/tmp/yosh_deploy_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  echo "—— LOG (last 80 lines) ——" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  echo "📄 Log: $LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# ===== Color Setup =====
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_CYAN=$'\e[38;5;51m';  C_BLUE=$'\e[38;5;27m'
  C_GREEN=$'\e[38;5;46m'; C_YEL=$'\e[38;5;220m'
  C_ORG=$'\e[38;5;208m';  C_PINK=$'\e[38;5;200m'
  C_GREY=$'\e[38;5;244m'; C_RED=$'\e[38;5;196m'
  C_PURPLE=$'\e[38;5;135m'
else
  RESET= BOLD= DIM= C_CYAN= C_BLUE= C_GREEN= C_YEL= C_ORG= C_PINK= C_GREY= C_RED= C_PURPLE=
fi

hr(){     printf "${C_GREY}%s${RESET}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
banner(){
  local title="$1"
  printf "\n${C_PURPLE}${BOLD}┌──────────────────────────────────────────────────┐${RESET}\n"
  printf   "${C_PURPLE}${BOLD}│${RESET}  %s${RESET}\n" "$(printf "%-46s" "$title")"
  printf   "${C_PURPLE}${BOLD}└──────────────────────────────────────────────────┘${RESET}\n"
}
ok(){   printf "${C_GREEN}✔${RESET}  %s\n" "$1"; }
warn(){ printf "${C_YEL}⚠${RESET}  %s\n" "$1"; }
err(){  printf "${C_RED}✘${RESET}  %s\n" "$1"; }
kv(){   printf "   ${C_GREY}%-12s${RESET} %s\n" "$1" "$2"; }

# ===== Welcome Banner =====
printf "\n"
printf "${C_PURPLE}${BOLD}  ██╗   ██╗ ██████╗ ███████╗██╗  ██╗${RESET}\n"
printf "${C_PURPLE}${BOLD}  ╚██╗ ██╔╝██╔═══██╗██╔════╝██║  ██║${RESET}\n"
printf "${C_CYAN}${BOLD}   ╚████╔╝ ██║   ██║███████╗███████║${RESET}\n"
printf "${C_CYAN}${BOLD}    ╚██╔╝  ██║   ██║╚════██║██╔══██║${RESET}\n"
printf "${C_BLUE}${BOLD}     ██║   ╚██████╔╝███████║██║  ██║${RESET}\n"
printf "${C_BLUE}${BOLD}     ╚═╝    ╚═════╝ ╚══════╝╚═╝  ╚═╝${RESET}\n"
printf "\n"
printf "${C_CYAN}${BOLD}       🌐 Yosh VIP — GCP Cloud Run Deploy${RESET}\n"
printf "${C_GREY}        VLESS WS · VLESS gRPC · Trojan WS · VMess WS${RESET}\n"
hr

# ===== Progress Spinner =====
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local pct=5
  if [[ -t 1 ]]; then
    printf "\e[?25l"
    while kill -0 "$pid" 2>/dev/null; do
      local step=$(( (RANDOM % 9) + 2 ))
      pct=$(( pct + step ))
      (( pct > 95 )) && pct=95
      printf "\r${C_CYAN}⚡${RESET} %s... [%s%%]" "$label" "$pct"
      sleep "$(awk -v r=$RANDOM 'BEGIN{s=0.08+(r%7)/100; printf "%.2f", s}')"
    done
    wait "$pid"; local rc=$?
    printf "\r"
    if (( rc == 0 )); then
      printf "${C_GREEN}✔${RESET} %s... [100%%]\n" "$label"
    else
      printf "${C_RED}✘${RESET} %s failed — check %s\n" "$label" "$LOG_FILE"
      return $rc
    fi
    printf "\e[?25h"
  else
    wait "$pid"
  fi
}

# ===== Step 1: Telegram Setup =====
banner "📲 Step 1 — Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

if [[ ( -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ) && -f .env ]]; then
  set -a; source ./.env; set +a
fi

read -rp "🤖 Telegram Bot Token (leave blank to skip): " _tk || true
[[ -n "${_tk:-}" ]] && TELEGRAM_TOKEN="$_tk"
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  warn "No token — deploy will continue without Telegram notifications."
else
  ok "Bot token saved."
fi

read -rp "👤 Chat ID(s) — comma-separated for multiple: " _ids || true
[[ -n "${_ids:-}" ]] && TELEGRAM_CHAT_IDS="${_ids// /}"

DEFAULT_LABEL="Join Yosh VIP"
DEFAULT_URL="https://t.me/yoshvip"
BTN_LABELS=(); BTN_URLS=()

read -rp "➕ Add inline button(s) to message? [y/N]: " _addbtn || true
if [[ "${_addbtn:-}" =~ ^([yY]|yes)$ ]]; then
  i=0
  while true; do
    echo "—— Button $((i+1)) ——"
    read -rp "🔖 Label [default: ${DEFAULT_LABEL}]: " _lbl || true
    if [[ -z "${_lbl:-}" ]]; then
      BTN_LABELS+=("${DEFAULT_LABEL}")
      BTN_URLS+=("${DEFAULT_URL}")
      ok "Added: ${DEFAULT_LABEL} → ${DEFAULT_URL}"
    else
      read -rp "🔗 URL (http/https): " _url || true
      if [[ -n "${_url:-}" && "${_url}" =~ ^https?:// ]]; then
        BTN_LABELS+=("${_lbl}")
        BTN_URLS+=("${_url}")
        ok "Added: ${_lbl} → ${_url}"
      else
        warn "Skipped — invalid or empty URL."
      fi
    fi
    i=$(( i + 1 ))
    (( i >= 3 )) && break
    read -rp "➕ Another button? [y/N]: " _more || true
    [[ "${_more:-}" =~ ^([yY]|yes)$ ]] || break
  done
fi

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tg_send(){
  local text="$1" RM=""
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  if (( ${#BTN_LABELS[@]} > 0 )); then
    local L1 U1 L2 U2 L3 U3
    [[ -n "${BTN_LABELS[0]:-}" ]] && L1="$(json_escape "${BTN_LABELS[0]}")" && U1="$(json_escape "${BTN_URLS[0]}")"
    [[ -n "${BTN_LABELS[1]:-}" ]] && L2="$(json_escape "${BTN_LABELS[1]}")" && U2="$(json_escape "${BTN_URLS[1]}")"
    [[ -n "${BTN_LABELS[2]:-}" ]] && L3="$(json_escape "${BTN_LABELS[2]}")" && U3="$(json_escape "${BTN_URLS[2]}")"
    if (( ${#BTN_LABELS[@]} == 1 )); then
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}]]}"
    elif (( ${#BTN_LABELS[@]} == 2 )); then
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"}]]}"
    else
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"},{\"text\":\"${L3}\",\"url\":\"${U3}\"}]]}"
    fi
  fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" \
      ${RM:+--data-urlencode "reply_markup=${RM}"} >>"$LOG_FILE" 2>&1
    ok "Telegram sent → ${_cid}"
  done
}

# ===== Step 2: GCP Project =====
banner "☁️  Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active GCP project found."
  err "Run: gcloud config set project <YOUR_PROJECT_ID>"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
ok "Project: ${PROJECT}"
kv "Number:" "${PROJECT_NUMBER}"

# ===== Step 3: Protocol =====
banner "🔌 Step 3 — Select Protocol"
printf "   ${C_YEL}1)${RESET} VLESS WS\n"
printf "   ${C_YEL}2)${RESET} VLESS gRPC\n"
printf "   ${C_YEL}3)${RESET} Trojan WS\n"
printf "   ${C_YEL}4)${RESET} VMess WS\n"
read -rp "Choose [1-4, default 1]: " _opt || true
case "${_opt:-1}" in
  2) PROTO="vless-grpc" ; IMAGE="docker.io/yoshyyy/yoshvip:latest" ;;
  3) PROTO="trojan-ws"  ; IMAGE="docker.io/yoshyyy/yoshvip:latest" ;;
  4) PROTO="vmess-ws"   ; IMAGE="docker.io/yoshyyy/yoshvip:latest" ;;
  *) PROTO="vless-ws"   ; IMAGE="docker.io/yoshyyy/yoshvip:latest" ;;
esac
ok "Protocol: ${PROTO^^}"
echo "[Image] ${IMAGE}" >>"$LOG_FILE"

# ===== Step 4: Region =====
banner "🌏 Step 4 — Select Region"
printf "   ${C_CYAN}1)${RESET} 🇺🇸 United States (us-central1)    ← default\n"
printf "   ${C_CYAN}2)${RESET} 🇺🇸 US East       (us-east1)\n"
printf "   ${C_CYAN}3)${RESET} 🇸🇬 Singapore     (asia-southeast1)\n"
printf "   ${C_CYAN}4)${RESET} 🇯🇵 Japan         (asia-northeast1)\n"
read -rp "Choose [1-4, default 1]: " _r || true
case "${_r:-1}" in
  2) REGION="us-east1"         ;;
  3) REGION="asia-southeast1"  ;;
  4) REGION="asia-northeast1"  ;;
  *) REGION="us-central1"      ;;
esac
ok "Region: ${REGION}"

# ===== Step 5: Resources =====
banner "⚙️  Step 5 — Resources"
read -rp "CPU [1/2/4, default 1]: " _cpu || true
CPU="${_cpu:-1}"
read -rp "Memory [512Mi/1Gi/2Gi, default 512Mi]: " _mem || true
MEMORY="${_mem:-512Mi}"
ok "CPU: ${CPU} vCPU | Memory: ${MEMORY}"

# ===== Step 6: Service Name =====
banner "🪪 Step 6 — Service Name"
SERVICE="${SERVICE:-yoshvip}"
TIMEOUT="${TIMEOUT:-3600}"
case "$PROTO" in
  trojan-ws)  PORT=8081 ;;
  vmess-ws)   PORT=8082 ;;
  *)          PORT=8080 ;;
esac
read -rp "Service name [default: ${SERVICE}]: " _svc || true
SERVICE="${_svc:-$SERVICE}"
ok "Service: ${SERVICE}"

# ===== Step 7: Time Window =====
export TZ="Asia/Singapore"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
banner "🕒 Step 7 — Session Window"
kv "Start:"  "${START_LOCAL}"
kv "Expire:" "${END_LOCAL}"

# ===== Step 8: Enable APIs =====
banner "🔧 Step 8 — Enabling GCP APIs"
run_with_progress "Enabling Cloud Run & Cloud Build" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# ===== Step 9: Deploy =====
banner "🚀 Step 9 — Deploying to Cloud Run"
run_with_progress "Deploying ${SERVICE}" \
  gcloud run deploy "$SERVICE" \
    --image="$IMAGE" \
    --platform=managed \
    --region="$REGION" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --timeout="$TIMEOUT" \
    --allow-unauthenticated \
    --port="$PORT" \
    --min-instances=1 \
    --quiet

# ===== Result =====
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
CANONICAL_HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL_CANONICAL="https://${CANONICAL_HOST}"

banner "✅ Deploy Success"
ok "Service is live!"
kv "URL:"    "${C_CYAN}${BOLD}${URL_CANONICAL}${RESET}"
kv "Region:" "${REGION}"
kv "Proto:"  "${PROTO^^}"

# ===== Protocol URIs =====
TROJAN_PASS="yosh"
VLESS_UUID="8024e6ab-5da4-473c-9008-2b3c51f8d697"
VLESS_UUID_GRPC="8024e6ab-5da4-473c-9008-2b3c51f8d697"
VMESS_UUID="8024e6ab-5da4-473c-9008-2b3c51f8d697"

make_vmess_ws_uri(){
  local host="$1"
  local json="{\"v\":\"2\",\"ps\":\"Yosh-VMess-WS\",\"add\":\"vpn.googleapis.com\",\"port\":\"443\",\"id\":\"${VMESS_UUID}\",\"aid\":\"0\",\"scy\":\"zero\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${host}\",\"path\":\"/vmess\",\"tls\":\"tls\",\"sni\":\"vpn.googleapis.com\",\"alpn\":\"http/1.1\",\"fp\":\"randomized\"}"
  printf '%s' "$json" | base64 | tr -d '\n' | sed 's/^/vmess:\/\//'
}

case "$PROTO" in
  trojan-ws)  URI="trojan://${TROJAN_PASS}@vpn.googleapis.com:443?path=%2Ftrojan&security=tls&host=${CANONICAL_HOST}&type=ws#Yosh-Trojan-WS" ;;
  vless-ws)   URI="vless://${VLESS_UUID}@vpn.googleapis.com:443?path=%2Fvless&security=tls&encryption=none&host=${CANONICAL_HOST}&type=ws#Yosh-VLESS-WS" ;;
  vless-grpc) URI="vless://${VLESS_UUID_GRPC}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=yosh-grpc&sni=${CANONICAL_HOST}#Yosh-VLESS-gRPC" ;;
  vmess-ws)   URI="$(make_vmess_ws_uri "${CANONICAL_HOST}")" ;;
esac

printf "\n${C_YEL}${BOLD}🔑 Access Key:${RESET}\n"
printf "${C_GREY}%s${RESET}\n" "${URI}"

# ===== Step 10: Telegram Notify =====
banner "📣 Step 10 — Telegram Notify"

MSG=$(cat <<EOF
🌐 <b>Yosh VIP — Deploy Success</b>
━━━━━━━━━━━━━━━━━━━━
<blockquote>☁️ <b>Project:</b> ${PROJECT}
🌏 <b>Region:</b> ${REGION}
🔌 <b>Protocol:</b> ${PROTO^^}
🔗 <b>URL:</b> <a href="${URL_CANONICAL}">${URL_CANONICAL}</a></blockquote>

🔑 <b>Access Key:</b>
<pre><code>${URI}</code></pre>

<blockquote>🕒 <b>Start:</b> ${START_LOCAL}
⏳ <b>Expire:</b> ${END_LOCAL}</blockquote>
━━━━━━━━━━━━━━━━━━━━
EOF
)

tg_send "${MSG}"

printf "\n${C_PURPLE}${BOLD}  ✨ Yosh VIP — All done, bro! Warm instance running (min=1)${RESET}\n"
printf "${C_GREY}  📄 Log: ${LOG_FILE}${RESET}\n\n"
