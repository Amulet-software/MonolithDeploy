# Release Manager bootstrap integration

This repository can be prepared and deployed from the built-in Monolith Release Manager without manually pasting GitHub PATs onto the server.

## Scope

Only `dev` is deployable. `test` and `production` remain reserved and blocked.

Current DEV target:

- Site: `http://192.168.1.32`
- Hub: `http://192.168.1.32:8080`
- Swagger: `http://192.168.1.32:8080/docs`
- readiness: `http://192.168.1.32:8080/health/ready`
- PostgreSQL: Docker-private only

## Automated first-host flow

Release Manager performs the following sequence:

1. Authenticates the operator locally with GitHub CLI web login.
2. Transfers the current `MonolithDeploy` bootstrap definition to the server over SSH.
3. Runs `bootstrap.sh dev --prepare-only`.
4. Generates three independent Ed25519 deploy keys with `deploy-key-setup.sh dev generate`.
5. Registers the public keys as read-only deploy keys in:
   - `Amulet-software/MonolithDeploy`
   - `Amulet-software/HubMonolith`
   - `Amulet-software/SiteMonolit`
6. Runs `deploy-key-setup.sh dev verify` and switches Hub/Site repository URLs to SSH aliases.
7. Requests a short-lived repository runner registration token through the operator's local GitHub CLI session.
8. Pipes that token through stdin to `install-runner.sh dev --token-stdin`.
9. Verifies the host with `deployment-status.sh dev`.

No Site/Hub containers are started by the prepare-only bootstrap. The first real deployment remains a separate `Deploy DEV` GitHub Actions workflow dispatch.

## Managed SSH layout

The deploy user defaults to `monolith`.

Keys:

```text
~monolith/.ssh/monolith/monolithdeploy_ed25519
~monolith/.ssh/monolith/hubmonolith_ed25519
~monolith/.ssh/monolith/sitemonolit_ed25519
```

SSH aliases are written into a managed block in `~monolith/.ssh/config`:

```text
github-monolith-deploy
github-hub-monolith
github-site-monolit
```

Hub/Site repository URLs in `.env.dev` become:

```text
HUB_REPOSITORY=git@github-hub-monolith:Amulet-software/HubMonolith.git
SITE_REPOSITORY=git@github-site-monolit:Amulet-software/SiteMonolit.git
```

`GITHUB_TOKEN_FILE` is cleared after successful deploy-key verification.

## Runner

`install-runner.sh`:

- supports DEV only;
- runs as root but configures the runner identity as the `monolith` user;
- resolves the latest official `actions/runner` release;
- verifies the release SHA-256 when GitHub exposes an asset digest;
- registers the runner only for `Amulet-software/MonolithDeploy`;
- applies label `monolith-dev`;
- reads the one-time registration token from stdin rather than a command-line argument.

The deployment workflow itself still checks both the runner user and the DEV IP before syncing `/opt/monolith` and running `deploy.sh dev`.

## Manual equivalents

If Release Manager is unavailable, the same server-side sequence is:

```bash
sudo bash ./bootstrap.sh dev --prepare-only
sudo bash ./deploy-key-setup.sh dev generate
# register printed keys in the matching GitHub repositories
sudo bash ./deploy-key-setup.sh dev verify
printf '%s\n' '<one-time-runner-token>' | sudo bash ./install-runner.sh dev --token-stdin
sudo bash ./deployment-status.sh dev
```

The runner token is intentionally not stored in `.env.dev` or any repository file.
