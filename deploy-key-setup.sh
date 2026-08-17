#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

profile=${1:-}
action=${2:-status}
deploy_user=${MONOLITH_DEPLOY_USER:-monolith}

[[ "$profile" == "dev" ]] || {
  echo "Usage: sudo bash ./deploy-key-setup.sh dev [generate|verify|status]" >&2
  echo "Profiles test and production are intentionally disabled." >&2
  exit 2
}
case "$action" in
  generate|verify|status) ;;
  *) echo "Usage: sudo bash ./deploy-key-setup.sh dev [generate|verify|status]" >&2; exit 2 ;;
esac
[[ ${EUID} -eq 0 ]] || { echo "Run as root with sudo." >&2; exit 1; }
id "$deploy_user" >/dev/null 2>&1 || { echo "Deploy user '$deploy_user' does not exist. Run bootstrap.sh dev --prepare-only first." >&2; exit 1; }

home_dir=$(getent passwd "$deploy_user" | cut -d: -f6)
ssh_dir="$home_dir/.ssh"
key_root="$ssh_dir/monolith"
env_file=".env.$profile"

roles=(monolithdeploy hubmonolith sitemonolit)
aliases=(github-monolith-deploy github-hub-monolith github-site-monolit)
repos=(Amulet-software/MonolithDeploy Amulet-software/HubMonolith Amulet-software/SiteMonolit)

ensure_layout() {
  install -d -m 700 -o "$deploy_user" -g "$deploy_user" "$ssh_dir" "$key_root"
  touch "$ssh_dir/known_hosts"
  chown "$deploy_user:$deploy_user" "$ssh_dir/known_hosts"
  chmod 600 "$ssh_dir/known_hosts"
}

key_path() {
  printf '%s/%s_ed25519' "$key_root" "$1"
}

write_ssh_config() {
  local config="$ssh_dir/config" temp
  temp=$(mktemp)
  if [[ -f "$config" ]]; then
    awk '
      /^# BEGIN MONOLITH DEPLOY KEYS$/ {skip=1; next}
      /^# END MONOLITH DEPLOY KEYS$/ {skip=0; next}
      !skip {print}
    ' "$config" > "$temp"
  fi
  {
    cat "$temp"
    echo "# BEGIN MONOLITH DEPLOY KEYS"
    local i role alias path
    for i in "${!roles[@]}"; do
      role=${roles[$i]}
      alias=${aliases[$i]}
      path=$(key_path "$role")
      cat <<EOF
Host $alias
  HostName github.com
  User git
  IdentityFile $path
  IdentitiesOnly yes
  StrictHostKeyChecking yes

EOF
    done
    echo "# END MONOLITH DEPLOY KEYS"
  } > "$config"
  rm -f "$temp"
  chown "$deploy_user:$deploy_user" "$config"
  chmod 600 "$config"
}

ensure_github_host_key() {
  if ! ssh-keygen -F github.com -f "$ssh_dir/known_hosts" >/dev/null 2>&1; then
    runuser -u "$deploy_user" -- bash -c 'ssh-keyscan -H github.com >> "$HOME/.ssh/known_hosts"'
  fi
}

generate_keys() {
  ensure_layout
  local i role path
  for i in "${!roles[@]}"; do
    role=${roles[$i]}
    path=$(key_path "$role")
    if [[ ! -f "$path" ]]; then
      runuser -u "$deploy_user" -- ssh-keygen -q -t ed25519 -N '' \
        -C "monolith-dev:${role}@$(hostname)" -f "$path"
    fi
    chown "$deploy_user:$deploy_user" "$path" "$path.pub"
    chmod 600 "$path"
    chmod 644 "$path.pub"
  done
  write_ssh_config
  ensure_github_host_key

  echo "Deploy keys generated. Register each public key in the matching GitHub repository as read-only:"
  echo "MONOLITHDEPLOY_PUBLIC_KEY=$(cat "$(key_path monolithdeploy).pub")"
  echo "HUBMONOLITH_PUBLIC_KEY=$(cat "$(key_path hubmonolith).pub")"
  echo "SITEMONOLIT_PUBLIC_KEY=$(cat "$(key_path sitemonolit).pub")"
}

update_env_repositories() {
  [[ -f "$env_file" ]] || { echo "Missing $env_file; run bootstrap first." >&2; exit 1; }
  sed -i -E 's|^HUB_REPOSITORY=.*$|HUB_REPOSITORY=git@github-hub-monolith:Amulet-software/HubMonolith.git|' "$env_file"
  sed -i -E 's|^SITE_REPOSITORY=.*$|SITE_REPOSITORY=git@github-site-monolit:Amulet-software/SiteMonolit.git|' "$env_file"
  sed -i -E 's|^GITHUB_TOKEN_FILE=.*$|GITHUB_TOKEN_FILE=|' "$env_file"
  chown "$deploy_user:$deploy_user" "$env_file"
  chmod 600 "$env_file"
}

verify_access() {
  ensure_layout
  write_ssh_config
  ensure_github_host_key
  local i alias repo url
  for i in "${!roles[@]}"; do
    alias=${aliases[$i]}
    repo=${repos[$i]}
    url="git@${alias}:${repo}.git"
    echo "Checking $repo via $alias"
    if ! runuser -u "$deploy_user" -- git ls-remote "$url" HEAD >/dev/null 2>&1; then
      echo "Deploy key access failed for $repo." >&2
      exit 1
    fi
  done

  update_env_repositories
  if [[ -d .git ]]; then
    git remote set-url origin git@github-monolith-deploy:Amulet-software/MonolithDeploy.git
  fi
  echo "All Monolith deploy keys are valid. HTTPS/PAT fallback is disabled in $env_file."
}

show_status() {
  ensure_layout
  local i role path state
  for i in "${!roles[@]}"; do
    role=${roles[$i]}
    path=$(key_path "$role")
    state=missing
    [[ -f "$path" && -f "$path.pub" ]] && state=present
    printf '%-16s %s\n' "$role" "$state"
  done
  [[ -f "$env_file" ]] && {
    echo "HUB_REPOSITORY=$(sed -n 's/^HUB_REPOSITORY=//p' "$env_file" | tail -n1)"
    echo "SITE_REPOSITORY=$(sed -n 's/^SITE_REPOSITORY=//p' "$env_file" | tail -n1)"
  }
}

case "$action" in
  generate) generate_keys ;;
  verify) verify_access ;;
  status) show_status ;;
esac
