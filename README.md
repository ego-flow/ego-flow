# EgoFlow Workspace

This workspace contains the main EgoFlow projects:

- `ego-flow-app`: client/mobile or glasses-side application
- `ego-flow-server`: backend APIs, dashboard, worker, and supporting infrastructure
- `ego-flow-py`: Python package scaffold for loading EgoFlow video datasets in research environments
- `scripts/server-up.sh`: parent-repo helper for refreshing a server checkout and restarting the stack

## Repository Layout

```text
ego-flow/
├── scripts/
├── ego-flow-app/
├── ego-flow-py/
└── ego-flow-server/
```

## Quick Start

The server stack is the main entry point for both local machines and remote Linux servers.

```bash
cd ego-flow-server
cp config.json.example config.json
cp .env.example .env
./scripts/run.sh doctor
./scripts/run.sh up
```

Useful follow-up commands:

```bash
./scripts/run.sh logs
./scripts/run.sh ps
./scripts/run.sh down
```

`./scripts/run.sh up` builds and starts the full stack: postgres, redis, backend, worker, dashboard, proxy, and MediaMTX.

With the current dashboard implementation you can:

- log in to the dashboard
- browse processed videos
- open video detail and delete videos
- monitor active live HLS streams
- manage users and target-directory settings as admin

## Server Refresh

When this parent repository is cloned on a remote server, the standard refresh path is:

```bash
./scripts/server-up.sh
```

The helper stops the current stack, pulls the latest parent repo commit, updates submodules, and then runs `ego-flow-server/scripts/run.sh up`.

## Where To Start

- Python dataset package: `ego-flow-py/README.md`
- Server setup and runtime workflow: `ego-flow-server/README.md`
- Server implementation details: `ego-flow-server/guide/EgoFlow_IMPLEMENTATION_GUIDE.md`
- Server roadmap: `ego-flow-server/guide/EgoFlow_TASK_ROADMAP.md`
