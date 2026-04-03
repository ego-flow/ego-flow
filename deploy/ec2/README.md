# EC2 Deployment

This deployment path is designed for GitHub Actions:

1. Build backend/dashboard images with immutable SHA tags
2. Push them to GHCR
3. SSH into EC2 and update `/opt/egoflow/repo`
4. Upload production `config.json`, `.env`, and `.env.compose` to `/opt/egoflow/config`
5. Run `deploy/ec2/deploy.sh deploy`
6. Run `deploy/ec2/deploy.sh smoke-test`

## Required GitHub Secrets

- `EC2_HOST`
- `EC2_USER`
- `EC2_SSH_KEY`
- `GHCR_USERNAME`
- `GHCR_READ_TOKEN`
- `POSTGRES_PASSWORD`
- `JWT_SECRET`
- `ADMIN_DEFAULT_PASSWORD`
- `HF_TOKEN`

## Required GitHub Variables

- `CORS_ORIGIN`
- `PUBLIC_HTTP_PORT`
- `RTMP_PORT`
- `HLS_PORT`
- `MEDIAMTX_API_PORT`
- `PUBLIC_RTMP_BASE_URL`
- `PUBLIC_HLS_BASE_URL`

## First-Time EC2 Notes

- The deploy user must be able to run Docker.
- `/opt/egoflow/repo` must already contain this repository clone.
- `/opt/egoflow/data` is used for persistent PostgreSQL, Redis, raw media, and datasets.
- `/opt/egoflow/config` stores production `config.json`, `.env`, and `.env.compose`.
- `/opt/egoflow/releases` stores deploy metadata plus per-release config snapshots for rollback/reference.
- Production compose is rendered from `ego-flow-server/compose.yml` and `ego-flow-server/compose.prod.yml`.
- `compose.yml` keeps the shared service contract, while `compose.prod.yml` supplies published ports, bind mounts, and production runtime files.
- `deploy/ec2/deploy.sh` reads the immutable image tags and `DATA_ROOT` from `/opt/egoflow/config/.env.compose`.
- `deploy/ec2/deploy.sh` prints the resolved compose config during deploy and dumps `docker compose ps`, service logs, and container health details automatically if deploy or smoke-test fails.
- Production data changes must follow the data-preservation runbook instead of `down -v` or data-directory deletion.
- `ego-flow-server/Caddyfile` is shared by the local and EC2 compose stacks and fronts both the dashboard and API on `PUBLIC_HTTP_PORT`.

## Runtime Files

- Example app env: [deploy/ec2/.env.example](/home/dennis0405/ego-flow/deploy/ec2/.env.example)
- Example compose env: [deploy/ec2/.env.compose.example](/home/dennis0405/ego-flow/deploy/ec2/.env.compose.example)
- Example config: [deploy/ec2/config.json.example](/home/dennis0405/ego-flow/deploy/ec2/config.json.example)
- Bootstrap guide: [deploy/ec2/bootstrap.md](/home/dennis0405/ego-flow/deploy/ec2/bootstrap.md)
- Data operations guide: [deploy/ec2/data-operations.md](/home/dennis0405/ego-flow/deploy/ec2/data-operations.md)
