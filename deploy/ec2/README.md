# EC2 Deployment

This deployment path is designed for GitHub Actions:

1. Build backend/dashboard images
2. Push them to GHCR
3. SSH into EC2
4. Upload `deploy/ec2/.env.prod`
5. Run `deploy/ec2/deploy.sh`

## Required GitHub Secrets

- `EC2_HOST`
- `EC2_USER`
- `EC2_SSH_KEY`
- `GHCR_USERNAME`
- `GHCR_READ_TOKEN`
- `POSTGRES_PASSWORD`
- `JWT_SECRET`
- `ADMIN_DEFAULT_PASSWORD`

## Required GitHub Variables

- `VITE_API_BASE_URL`
- `VITE_BACKEND_ORIGIN`
- `CORS_ORIGIN`
- `PUBLIC_RTMP_BASE_URL`
- `PUBLIC_HLS_BASE_URL`

## First-Time EC2 Notes

- The deploy user must be able to run Docker.
- `/opt/egoflow/repo` must already contain this repository clone.
- `/opt/egoflow/data` is used for persistent PostgreSQL, Redis, raw media, and datasets.
