# payrollengine-deploy

One-click Payroll Engine stack for Dokploy:

- **MySQL 8.0** — auto-seeded schema from `stack/init/01-Create-Model.mysql.sql`
- **Backend** — ASP.NET Core REST API, built from [Payroll-Engine/PayrollEngine.Backend](https://github.com/Payroll-Engine/PayrollEngine.Backend) with `Dockerfile.backend` (patched for nuget.org, no GitHub Packages auth — see [upstream issue #8](https://github.com/Payroll-Engine/PayrollEngine.Backend/issues/8))
- **regulation-import** — one-shot init job, built from [Payroll-Engine/PayrollEngine.PayrollConsole](https://github.com/Payroll-Engine/PayrollEngine.PayrollConsole), clones a regulation repo (`REGULATION_REPO_URL`), waits for backend, runs `Setup.pecmd`

Both Dockerfiles clone upstream Payroll Engine source at build time — this repo stays small (~200 KB).

## Spawn on Dokploy

1. Create a new Docker Compose service pointing at this repo (`sourceType: git`, `composePath: ./docker-compose.yml`)
2. Set the env vars (see [`stack/.env.example`](stack/.env.example))
3. Deploy

Or clone the existing `payroll-template` project on Dokploy and override `STACK_NAME` / `STACK_HOST` / `REGULATION_REPO_URL`.

## Required env vars

| Var | Example | Purpose |
|---|---|---|
| `STACK_NAME` | `demo-fr` | Unique per-instance, used in Traefik router names |
| `STACK_HOST` | `demo-fr.catapulte.studio` | Public FQDN |
| `MYSQL_ROOT_PASSWORD` | random | DB root password |
| `PAYROLL_API_KEY` | random | API key the Backend accepts (`Api-Key` header) |
| `REGULATION_REPO_URL` | `https://github.com/versohq/Regulation.FR.DirigeantSasu` | Git repo cloned on first deploy |
| `REGULATION_REPO_TOKEN` | GitHub PAT | Required for private regulation repos |
| `REGULATION_ENTRY_FILE` | _(auto)_ | Override auto-detected entry point |
| `PE_VERSION` | `0.10.0-beta.4` | NuGet version the Dockerfiles pin |
| `PE_BACKEND_REF` | `v0.10.0-beta.4` | Git ref cloned by `Dockerfile.backend` |
| `PE_CONSOLE_REF` | `main` | Git ref cloned by `Dockerfile.console` |

## Local test

```bash
cp stack/.env.example .env
# edit .env
docker compose up -d --build
curl -H "Api-Key: $PAYROLL_API_KEY" http://localhost:8080/api/tenants
```

## Regulation entry detection

`regulation-import` looks for the entry point in this order:

1. `${REGULATION_ENTRY_FILE}` if explicitly set
2. First `Setup.pecmd` under `<repo>/<year>/` (filters out `Data.*` subdirs to get the main setup)
3. First `*.json` at repo root

`.pecmd` files are run with the PayrollConsole's command-file mode; `.json` files via `PayrollImport SourceFileName: /bulk`.

## Updating the MySQL seed

The schema ships in `stack/init/01-Create-Model.mysql.sql` (self-contained — tables, functions, stored procs). Regenerate from upstream:

```bash
curl -sL https://raw.githubusercontent.com/Payroll-Engine/PayrollEngine.Backend/v0.10.0-beta.4/Database/Create-Model.mysql.sql \
  > stack/init/01-Create-Model.mysql.sql
```

## Operational docs

See [`DOKPLOY.md`](DOKPLOY.md) for Dokploy-specific notes (tRPC API, org isolation, known pitfalls).
