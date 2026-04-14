# Payroll Engine — one-click stack

Spawn a full Payroll Engine instance (Backend API + MySQL + regulation auto-import) on Dokploy in one command.

## What's in the stack

| Service | Image | Role |
|---|---|---|
| `mysql` | `mysql:8.0` | Database, auto-seeded from `stack/init/01-Create-Model.mysql.sql` on first boot |
| `backend` | built locally from `PayrollEngine.Backend/` via `Dockerfile.backend` | REST API, port 8080 |
| `regulation-import` | built locally from `PayrollEngine.PayrollConsole/` via `Dockerfile.console` | One-shot init job: clones `REGULATION_REPO_URL`, waits for backend, imports via `PayrollImport` |

Both images are built with `NUGET_SOURCE=nuget.org` only — no GitHub Packages auth needed. See [`Dockerfile.backend`](../Dockerfile.backend) and [`Dockerfile.console`](../Dockerfile.console) for the `.csproj` version patching.

## Environment variables

See [`.env.example`](./.env.example). Required:

- `STACK_NAME` — used for Traefik router names (must be unique per Dokploy project)
- `STACK_HOST` — public FQDN (e.g. `demo-es.catapulte.studio`)
- `MYSQL_ROOT_PASSWORD` — DB password
- `PAYROLL_API_KEY` — API key the Backend accepts (`Api-Key` header on all requests)
- `REGULATION_REPO_URL` — public git URL of the regulation to import on first boot

Optional:
- `REGULATION_ENTRY_FILE` — path to the main JSON inside the repo (default: first `*.json` at depth ≤ 2)
- `PE_VERSION` — PayrollEngine NuGet version to build against (default `0.10.0-beta.4`)

## Local test

```bash
cd verso-dokploy
cp stack/.env.example .env    # fill in values
docker compose up -d --build
curl http://localhost:8080/swagger/index.html
```

The `regulation-import` service exits 0 after a successful import — check its logs:
```bash
docker compose logs regulation-import
```

## Spawn on Dokploy

One-time template bootstrap (first run creates `payroll-template` project):
```bash
./stack/scripts/spawn-stack.sh bootstrap
```

Spawn a new instance by duplicating the template:
```bash
./stack/scripts/spawn-stack.sh spawn demo-es https://github.com/Payroll-Engine/Regulation.ES.Nomina
```

The script reads `.env` at the repo root for `DOKPLOY_URL` and `DOKPLOY_STUDIO_API_KEY` and calls the tRPC API (`project.duplicate` + `compose.update`).

After ~3 minutes the instance is live at `https://<stack>.catapulte.studio`.

## Regenerating the MySQL seed

If the Backend bumps its schema version, re-run:
```bash
./stack/scripts/sync-init.sh
```
This copies `PayrollEngine.Backend/Database/Create-Model.mysql.sql` to `stack/init/01-Create-Model.mysql.sql` (the file is self-contained — it already bundles all tables, functions, and stored procedures).
