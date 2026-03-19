# EgoFlow Workspace

`~/ego-flow` is the parent workspace that contains two separate projects:

- `ego-flow-app`: mobile/glasses communication app repository
- `ego-flow-server`: backend/infrastructure repository

Current note:

- dashboard/frontend work is expected under `ego-flow-server/frontend`
- there is no separate dashboard submodule in this workspace baseline

## Directory Structure

```text
~/ego-flow/
├── ego-flow-app/
└── ego-flow-server/
```

## Quick Entry Points

Compose-based backend start:

```bash
cd ~/ego-flow/ego-flow-server
./scripts/dev.sh start
./scripts/dev.sh worker
```

Optional local bootstrap only:

```bash
cd ~/ego-flow/ego-flow-server
./scripts/dev.sh setup
```

Direct Compose entry:

```bash
cd ~/ego-flow/ego-flow-server
docker compose up -d
```

Notes:

- `./scripts/dev.sh start` and `./scripts/dev.sh worker` now both use `docker compose up -d --build ...`
- `./scripts/dev.sh setup` only prepares local `.env`, local npm dependencies, and local Prisma client generation

More details:

- Server README: `~/ego-flow/ego-flow-server/README.md`
- Implementation guide: `~/ego-flow/ego-flow-server/guide/EgoFlow_IMPLEMENTATION_GUIDE.md`
- Task roadmap: `~/ego-flow/ego-flow-server/guide/EgoFlow_TASK_ROADMAP.md`
