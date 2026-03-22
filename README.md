# EgoFlow Workspace

This workspace contains the main EgoFlow projects:

- `ego-flow-app`: client/mobile or glasses-side application
- `ego-flow-server`: backend APIs, dashboard, worker, and supporting infrastructure

## Repository Layout

```text
ego-flow/
├── ego-flow-app/
└── ego-flow-server/
```

## Quick Start

The backend stack is the easiest entry point for local evaluation.

```bash
cd ego-flow-server
./scripts/dev.sh up
```

Useful follow-up commands:

```bash
./scripts/dev.sh logs
./scripts/dev.sh ps
./scripts/dev.sh down
```

`./scripts/dev.sh up` now starts the backend stack and dashboard together.

With the current dashboard implementation you can:

- log in to the dashboard
- browse processed videos
- open video detail and delete videos
- monitor active live HLS streams
- manage users and target-directory settings as admin

## Where To Start

- Server setup and local Docker workflow: `ego-flow-server/README.md`
- Server implementation details: `ego-flow-server/guide/EgoFlow_IMPLEMENTATION_GUIDE.md`
- Server roadmap: `ego-flow-server/guide/EgoFlow_TASK_ROADMAP.md`
