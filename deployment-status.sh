#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

profile=${1:-dev}
deploy_user=${MONOLITH_DEPLOY_USER:-monolith}
[[ "$profile" == "dev" ]] || { echo "Only dev is supported." >&2; exit 2; }

home_dir=$(getent passwd "$deploy_user" 2>/dev/null | cut -d: -f6 || true)
runner_root=${MONOLITH_RUNNER_ROOT:-${home_dir:-/home/$deploy_user}/actions-runner}

truth() { if "$@" >/dev/null 2>&1; then echo true; else echo false; fi; }

printf 'PROFILE=%s\n' "$profile"
printf 'DEPLOY_USER_EXISTS=%s\n' "$(truth id "$deploy_user")"
printf 'DOCKER_INSTALLED=%s\n' "$(truth command -v docker)"
if id "$deploy_user" >/dev/null 2>&1 && command -v docker >/dev/null 2>&1; then
  if runuser -u "$deploy_user" -- docker info >/dev/null 2>&1; then
    echo 'DOCKER_ACCESS=true'
  else
    echo 'DOCKER_ACCESS=false'
  fi
else
  echo 'DOCKER_ACCESS=false'
fi
printf 'ENV_PRESENT=%s\n' "$([[ -f .env.dev ]] && echo true || echo false)"
printf 'MONOLITHDEPLOY_KEY=%s\n' "$([[ -f "${home_dir:-/home/$deploy_user}/.ssh/monolith/monolithdeploy_ed25519" ]] && echo true || echo false)"
printf 'HUBMONOLITH_KEY=%s\n' "$([[ -f "${home_dir:-/home/$deploy_user}/.ssh/monolith/hubmonolith_ed25519" ]] && echo true || echo false)"
printf 'SITEMONOLIT_KEY=%s\n' "$([[ -f "${home_dir:-/home/$deploy_user}/.ssh/monolith/sitemonolit_ed25519" ]] && echo true || echo false)"
printf 'RUNNER_CONFIGURED=%s\n' "$([[ -f "$runner_root/.runner" ]] && echo true || echo false)"
if command -v systemctl >/dev/null 2>&1 && systemctl list-units --type=service --state=running --no-legend 'actions.runner.*' 2>/dev/null | grep -q 'actions.runner.'; then
  echo 'RUNNER_SERVICE=true'
else
  echo 'RUNNER_SERVICE=false'
fi

if command -v curl >/dev/null 2>&1; then
  if curl --fail --silent --show-error --max-time 3 http://192.168.1.32/ >/dev/null 2>&1; then
    echo 'SITE_HEALTH=true'
  else
    echo 'SITE_HEALTH=false'
  fi
  if curl --fail --silent --show-error --max-time 3 http://192.168.1.32:8080/health/ready >/dev/null 2>&1; then
    echo 'HUB_HEALTH=true'
  else
    echo 'HUB_HEALTH=false'
  fi
else
  echo 'SITE_HEALTH=false'
  echo 'HUB_HEALTH=false'
fi
