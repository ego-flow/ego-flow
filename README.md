# EgoFlow Workspace

`~/ego-flow` is the parent workspace that contains two separate projects:

- `ego-flow-app`: mobile/glasses communication app repository
- `ego-flow-server`: backend/infrastructure repository

## Directory Structure

```text
~/ego-flow/
├── ego-flow-app/
└── ego-flow-server/
```

## Quick Entry Points

Backend setup and run:

```bash
cd ~/ego-flow/ego-flow-server
./scripts/dev.sh setup
./scripts/dev.sh start
```

More details:

- Server boot guide: `~/ego-flow/ego-flow-server/guide/DEV_BOOTUP.md`
- Server tech stack: `~/ego-flow/ego-flow-server/guide/TECH_STACK_VERSIONS.md`
