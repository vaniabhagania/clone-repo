#!/usr/bin/env bash
# One-command launcher for Dossier on your own computer.
#
#   ./run.sh            set everything up on the first run, then start Dossier
#   ./run.sh stop       stop it (your data is kept)
#   ./run.sh logs       follow the app's log
#   ./run.sh password   choose a new sign-in password
#
# Works on macOS, Linux, and WSL on Windows. The only thing you need installed
# is Docker (Docker Desktop on macOS/Windows, Docker Engine + Compose on Linux).
#
# On the first run it creates a private .env next to this script with the
# secrets Dossier needs, and asks you to choose a sign-in password. Only a hash
# of the password is stored, never the password itself.

set -euo pipefail
cd "$(dirname "$0")"

IMAGE="ghcr.io/aientech/dossier"
COMPOSE=(docker compose -f compose.production.yml)

say() { printf '%s\n' "$*"; }
die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

# --- Docker checks ------------------------------------------------------------

check_docker() {
  command -v docker >/dev/null 2>&1 \
    || die "Docker isn't installed. Install Docker Desktop (https://docs.docker.com/desktop/), start it, and run this again."
  docker info >/dev/null 2>&1 \
    || die "Docker isn't running. Start Docker Desktop (or the Docker service) and run this again."
  docker compose version >/dev/null 2>&1 \
    || die "Docker Compose isn't available. Update Docker Desktop, or install the Compose plugin on Linux."

  # The image is built for Intel/AMD processors; on ARM (Apple Silicon) Docker
  # runs it under emulation, which needs this override.
  case "$(uname -m)" in
    arm64|aarch64)
      if [ ! -f compose.override.yml ]; then
        printf 'services:\n  app:\n    platform: linux/amd64\n' > compose.override.yml
      fi
      COMPOSE=(docker compose -f compose.production.yml -f compose.override.yml)
      ;;
  esac
}

# --- .env helpers -------------------------------------------------------------

has_var() { [ -f .env ] && grep -q "^$1=." .env; }

random_hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 24
  else
    head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'
  fi
}

random_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 32
  else
    head -c 32 /dev/urandom | base64 | tr -d '\n'
  fi
}

ask_password_hash() {
  [ -t 0 ] || die "I need to ask you for a password, so run this in a terminal (not piped)."
  local pw1 pw2 attempt hash errfile
  # This runs inside $(...), so everything meant for the person goes to stderr;
  # only the hash itself goes to stdout.
  for attempt in 1 2 3; do
    printf 'Choose a password for signing in to Dossier (at least 8 characters): ' >&2
    IFS= read -r -s pw1; printf '\n' >&2
    printf 'Type it again: ' >&2
    IFS= read -r -s pw2; printf '\n' >&2
    if [ "${#pw1}" -lt 8 ]; then
      say "That's too short. Try again." >&2
    elif [ "$pw1" != "$pw2" ]; then
      say "Those don't match. Try again." >&2
    else
      break
    fi
    pw1=""
    [ "$attempt" -lt 3 ] || die "No password chosen. Run ./run.sh again to retry."
  done

  say "Downloading Dossier (about 1.7 GB the first time; this can take a few minutes)..." >&2
  docker pull --platform linux/amd64 "$IMAGE" >&2

  errfile="$(mktemp)"
  if ! hash="$(printf '%s\n' "$pw1" | docker run --rm -i --platform linux/amd64 "$IMAGE" hash-password 2>"$errfile" | tail -n 1)"; then
    cat "$errfile" >&2; rm -f "$errfile"
    die "Couldn't hash the password."
  fi
  rm -f "$errfile"
  case "$hash" in
    argon2id:*) printf '%s' "$hash" ;;
    *) die "Unexpected output while hashing the password." ;;
  esac
}

# Adds a KEY=value line to .env unless a non-empty one is already there. An
# existing POSTGRES_PASSWORD is never replaced: the database was created with it.
ensure_env() {
  umask 077
  [ -f .env ] || : > .env
  if ! has_var POSTGRES_PASSWORD; then
    printf 'POSTGRES_PASSWORD=%s\n' "$(random_hex)" >> .env
  fi
  if ! has_var DOSSIER_SECRET; then
    printf 'DOSSIER_SECRET=%s\n' "$(random_secret)" >> .env
  fi
  if ! has_var DOSSIER_PASSWORD; then
    local hash
    hash="$(ask_password_hash)"
    printf 'DOSSIER_PASSWORD=%s\n' "$hash" >> .env
  fi
}

# --- Commands -----------------------------------------------------------------

port() {
  local p=""
  [ -f .env ] && p="$(grep '^DOSSIER_PORT=' .env | tail -n 1 | cut -d= -f2 || true)"
  printf '%s' "${DOSSIER_PORT:-${p:-3000}}"
}

wait_until_ready() {
  command -v curl >/dev/null 2>&1 || return 0
  local url="http://localhost:$(port)/login" i
  say "Starting Dossier (the first start sets up the database)..."
  for i in $(seq 1 90); do
    if curl -fsS -o /dev/null -m 3 "$url" 2>/dev/null; then return 0; fi
    sleep 2
  done
  return 1
}

cmd_start() {
  check_docker
  ensure_env
  "${COMPOSE[@]}" up -d
  if wait_until_ready; then
    say ""
    say "Dossier is running. Open http://localhost:$(port) and sign in with your password."
  else
    say ""
    say "Dossier is still starting. Check progress with: ./run.sh logs"
    say "Then open http://localhost:$(port)"
  fi
  say "Stop it with ./run.sh stop (your data is kept)."
}

cmd_stop() {
  check_docker
  "${COMPOSE[@]}" stop
}

cmd_logs() {
  check_docker
  "${COMPOSE[@]}" logs -f app
}

cmd_password() {
  check_docker
  umask 077
  if [ -f .env ]; then
    grep -v '^DOSSIER_PASSWORD=' .env > .env.tmp || true
    mv .env.tmp .env
  fi
  ensure_env
  "${COMPOSE[@]}" up -d
  say "Password changed. Any browser that was signed in has been signed out."
}

case "${1:-start}" in
  start)    cmd_start ;;
  stop)     cmd_stop ;;
  logs)     cmd_logs ;;
  password) cmd_password ;;
  -h|--help|help)
    sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) die "Unknown command '$1'. Use: ./run.sh [start|stop|logs|password]" ;;
esac
