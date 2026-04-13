#!/usr/bin/env bash
set -euo pipefail

if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Log =====
LOG="/tmp/yosh_$(date +%s).log"
touch "$LOG"
die(){ echo "❌ Failed at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG" >&2; exit 1; }
trap die ERR

# ===== Colors =====
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  R=$'\e[0m' B=$'\e[1m' D=$'\e[2m'
  CY=$'\e[38;5;51m' CG=$'\e[38;5;82m' CP=$'\e[38;5;135m'
  CO=$'\e[38;5;208m' CR=$'\e[38;5;196m' CW=$'\e[38;5;255m'
  CG2=$'\e[38;5;244m' CB=$'\e[38;5;27m'
else
  R= B= D= CY= CG= CP= CO= CR= CW= CG2= CB=
fi

line(){ printf "${CG2}%s${R}\n" "▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬"; }
tag(){
  printf "\n${CP}${B} ◈ %s ${R}\n" "$1"
  line
}
ok(){  printf "  ${CG}●${R} %s\n" "$1"; }
err(){ printf "  ${CR}●${R} %s\n" "$1"; }
inf(){ printf "  ${CY}◆${R} %s\n" "$1"; }
kv(){  printf "  ${CG2}%-14s${R}${CW}%s${R}\n" "$1" "$2"; }

# ===== Spinner =====
spin(){
  local label="$1"; shift
  ("$@") >>"$LOG" 2>&1 &
  local pid=$! pct=3
  local frames=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
  local i=0
  [[ -t 1 ]] && printf "\e[?25l"
  while kill -0 "$pid" 2>/dev/null; do
    pct=$(( pct + (RANDOM % 8) + 1 ))
    (( pct > 94 )) && pct=94
    printf "\r  ${CP}%s${R} ${CW}%s${R} ${CG2}%d%%${R}" "${frames[$((i % 10))]}" "$label" "$pct"
    i=$(( i + 1 ))
    sleep 0.1
  done
  wait "$pid"; local rc=$?
  printf "\r  ${CG}✓${R} ${CW}%s${R} ${CG}[100%%]${R}\n" "$label"
  [[ -t 1 ]] && printf "\e[?25h"
  return $rc
}

# ===== Banner =====
clear
printf "\n"
printf "${CP}${B}  ╔═══════════════════════════════════════╗${R}\n"
printf "${CP}${B}  ║${R}                                       ${CP}${B}║${R}\n"
printf "${CP}${B}  ║${R}   ${CY}${B}🌐  Y O S H   V I P   D E P L O Y${R}   ${CP}${B}║${R}\n"
printf "${CP}${B}  ║${R}   ${CG2}GCP Cloud Run — Proxy Deployment${R}      ${CP}${B}║${R}\n"
printf "${CP}${B}  ║${R}                                       ${CP}${B}║${R}\n"
printf "${CP}${B}  ╚═══════════════════════════════════════╝${R}\n"
printf "\n"

# ===== GCP Project =====
tag "GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No GCP project found. Run: gcloud config set project <ID>"
  exit 1
fi
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
ok "Project  : ${PROJECT}"
ok "Number   : ${PROJECT_NUMBER}"

# ===== Protocol =====
tag "Select Protocol"
printf "  ${CY}1${R} › VLESS WS\n"
printf "  ${CY}2${R} › Trojan WS\n"
printf "  ${CY}3${R} › VMess WS\n"
printf "\n"
read -rp "  $(printf "${CW}Protocol${R} [1-3, default 1]: ")" _p || true
case "${_p:-1}" in
  2) PROTO="trojan-ws" ; IMAGE="docker.io/yoshyyy/yoshvip:latest" ;;
  3) PROTO="vmess-ws"  ; IMAGE="docker.io/yoshyyy/yoshvip:latest" ;;
  *) PROTO="vless-ws"  ; IMAGE="docker.io/yoshyyy/yoshvip:latest" ;;
esac
ok "Protocol : ${PROTO^^}"

# ===== Region =====
tag "Select Region"
printf "  ${CY}1${R} › 🇺🇸  United States  — us-central1\n"
printf "  ${CY}2${R} › 🇸🇬  Singapore      — asia-southeast1\n"
printf "  ${CY}3${R} › 🇯🇵  Japan          — asia-northeast1\n"
printf "  ${CY}4${R} › 🇮🇩  Indonesia      — asia-southeast2\n"
printf "  ${CY}5${R} › 🇪🇺  Europe         — europe-west1\n"
printf "\n"
read -rp "  $(printf "${CW}Region${R} [1-5, default 1]: ")" _r || true
case "${_r:-1}" in
  2) REGION="asia-southeast1" ;;
  3) REGION="asia-northeast1" ;;
  4) REGION="asia-southeast2" ;;
  5) REGION="europe-west1"    ;;
  *) REGION="us-central1"     ;;
esac
ok "Region   : ${REGION}"

# ===== Resources =====
tag "Resources"
printf "  ${CG2}CPU   →${R} 1 / 2 / 4 / 6 / 8\n"
printf "  ${CG2}RAM   →${R} 512Mi / 1Gi / 2Gi / 4Gi / 6Gi / 8Gi\n\n"
read -rp "  $(printf "${CW}CPU${R} [default 1]: ")" _cpu || true
CPU="${_cpu:-1}"
read -rp "  $(printf "${CW}Memory${R} [default 512Mi]: ")" _mem || true
MEMORY="${_mem:-512Mi}"
ok "CPU      : ${CPU} vCPU"
ok "Memory   : ${MEMORY}"

# ===== Service Name =====
tag "Service"
read -rp "  $(printf "${CW}Service name${R} [default: yoshvip]: ")" _svc || true
SERVICE="${_svc:-yoshvip}"
TIMEOUT=3600
case "$PROTO" in
  trojan-ws) PORT=8081 ;;
  vmess-ws)  PORT=8082 ;;
  *)         PORT=8080 ;;
esac
ok "Service  : ${SERVICE}"
ok "Port     : ${PORT}"

# ===== Time =====
export TZ="Asia/Singapore"
S_EPOCH="$(date +%s)"
E_EPOCH="$(( S_EPOCH + 5*3600 ))"
fmt(){ date -d @"$1" "+%d %b %Y  %I:%M %p"; }
START="$(fmt "$S_EPOCH")"
EXPIRY="$(fmt "$E_EPOCH")"

# ===== Deploy =====
tag "Enabling APIs"
spin "Cloud Run + Cloud Build" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

tag "Deploying to Cloud Run"
spin "Deploying ${SERVICE}" \
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
HOST="${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"
URL="https://${HOST}"

# ===== Build URI =====
TROJAN_PASS="yosh"
UUID="8024e6ab-5da4-473c-9008-2b3c51f8d697"

case "$PROTO" in
  trojan-ws)
    URI="trojan://${TROJAN_PASS}@firebase-settings.crashlytics.com:443?path=%2FYosh&security=tls&host=${HOST}&type=ws&sni=www.mayabank.ph&headerType=none#Yosh-Trojan-WS"
    ;;
  vless-ws)
    URI="vless://${UUID}@firebase-settings.crashlytics.com:443?path=%2FYosh&security=tls&encryption=none&host=${HOST}&type=ws&sni=www.mayabank.ph&headerType=none#Yosh-VLESS-WS"
    ;;
  vmess-ws)
    JSON="{\"v\":\"2\",\"ps\":\"Yosh-VMess\",\"add\":\"firebase-settings.crashlytics.com\",\"port\":\"443\",\"id\":\"${UUID}\",\"aid\":\"0\",\"scy\":\"zero\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"${HOST}\",\"path\":\"/Yosh\",\"tls\":\"tls\",\"sni\":\"www.mayabank.ph\",\"alpn\":\"http/1.1\",\"fp\":\"randomized\"}"
    URI="vmess://$(printf '%s' "$JSON" | base64 | tr -d '\n')"
    ;;
esac

# ===== Summary =====
printf "\n"
printf "${CG}${B}  ╔═══════════════════════════════════════╗${R}\n"
printf "${CG}${B}  ║${R}         ${CG}${B}✓  DEPLOY SUCCESSFUL${R}          ${CG}${B}║${R}\n"
printf "${CG}${B}  ╚═══════════════════════════════════════╝${R}\n\n"

kv "Service :"  "${SERVICE}"
kv "Region :"   "${REGION}"
kv "Protocol :" "${PROTO^^}"
kv "URL :"       "${CY}${URL}${R}"
kv "Start :"    "${START}"
kv "Expire :"   "${EXPIRY}"

printf "\n  ${CP}${B}🔑 Access Key:${R}\n"
printf "\n  ${CW}%s${R}\n\n" "${URI}"
printf "${CG2}  📄 Log: ${LOG}${R}\n\n"

