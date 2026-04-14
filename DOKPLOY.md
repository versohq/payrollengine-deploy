---
name: dokploy
description: Dokploy server management, deployments, and maintenance. Use this skill for any Dokploy-related task including deploying applications, managing projects, checking service status, configuring domains, troubleshooting deployments, or general server operations. Triggers on /dokploy, "deploy on dokploy", "dokploy status", "check deployment", "configure domain", "manage project", or any mention of Dokploy infrastructure management.
---

# Dokploy Management

Operational context for managing a Dokploy platform.

## Prerequisites

Environment variables `DOKPLOY_STUDIO_API_KEY` and `DOKPLOY_SERVER_IP` must be set in your environment. See `dokploy-config.example.env` for the required variables.

## Infrastructure

- **Server IP**: in env as `DOKPLOY_SERVER_IP`
- **OS**: Ubuntu 24.04
- **Dokploy**: v0.28.2 (Docker Swarm)
- **Panel**: `https://dokploy.<your-domain>`
- **Traefik**: v3.6.7 (reverse proxy, auto SSL via Let's Encrypt)

## Access

- **API Key**: `$DOKPLOY_STUDIO_API_KEY`
- **Server IP**: `$DOKPLOY_SERVER_IP` (SSH: `root@$DOKPLOY_SERVER_IP`)
- **Base URL**: `https://dokploy.<your-domain>`
- **tRPC API**: `https://dokploy.<your-domain>/api/trpc/{endpoint}`
- **Swagger**: `https://dokploy.<your-domain>/swagger`
- **Auth header**: `x-api-key: $DOKPLOY_STUDIO_API_KEY`

## tRPC API Patterns

Use the tRPC API directly via `curl` for all operations. Do not use Playwright. Refer to the Swagger docs to discover endpoints and their required parameters.

```bash
# Read (GET)
curl -s -H "x-api-key: $DOKPLOY_STUDIO_API_KEY" \
  "https://dokploy.<your-domain>/api/trpc/project.all"

# Mutation (POST)
curl -s -X POST -H "x-api-key: $DOKPLOY_STUDIO_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"json":{...}}' \
  "https://dokploy.<your-domain>/api/trpc/application.deploy"
```

tRPC responses are wrapped: `{"result":{"data":{"json": ... }}}`.

## Sensitive Operations

Always ask the user for confirmation before:
- Deleting a project, application, or database
- Modifying production environment variables
- Changing domain or SSL configuration
- Stopping or restarting a production service
- Any destructive or irreversible operation

## Deployment Report

After every deployment, provide a summary report that maps each element to the Dokploy UI:

```
## Deployment Report

| Field               | Value                                     | Where in Dokploy UI                       |
|---------------------|-------------------------------------------|-------------------------------------------|
| Project             | Project name                              | Dashboard > Projects > [name]             |
| Environment         | production                                | Project > environment tab                 |
| Application         | app-name (appName: xxx)                   | Environment > service card                |
| Source              | GitHub owner/repo (branch)                | App > General > Provider                  |
| Build Type          | dockerfile / nixpacks / ...               | App > General > Build Type                |
| Domain              | domain.example.com (HTTPS, Let's Encrypt) | App > Domains                             |
| Container Port      | 8080                                      | App > Domains > Container Port            |
| Env Variables       | X variables configured                    | App > Environment                         |
| Build Args          | X build args configured                   | App > Environment > Build-time Arguments  |
| Status              | done / error / running                    | App > Deployments                         |
| URL                 | https://domain.example.com                | -                                         |
```

Include any errors encountered and the solutions applied.

## Known Pitfalls

### Organizations
Dokploy is multi-org. The `DOKPLOY_STUDIO_API_KEY` token is bound to a specific org. A token can only read/write resources within its own org. If an operation returns "UNAUTHORIZED" on a resource that exists, it is likely an org mismatch.

### GitHub Provider
Each Dokploy org has its own GitHub App. To connect a private repo, use the `githubId` from the matching org (not from another org). List providers with `gitProvider.getAll`.

### tRPC Required Fields
The tRPC API enforces strict required fields via Zod validation. On a 400 error, read `zodError.fieldErrors` to identify missing fields. Common examples:
- `application.saveEnvironment` requires `buildSecrets` and `createEnvFile`
- `application.saveGithubProvider` requires `watchPaths` (array, can be empty `[]`)
- `application.saveBuildType` requires `herokuVersion` and `railpackVersion`

As a workaround, use `application.update` which accepts partial updates.

### Private Repos
For private GitHub repos, always use the GitHub provider (with the org's GitHub App). Do not use the "Git" provider with an HTTPS URL (the clone will fail without credentials).

### Dokploy CLI (`@dokploy/cli v0.2.8`)
The CLI has a bug with `inquirer`: interactive commands crash in non-interactive mode (piped stdin). Only `project list` and `verify` work reliably. Prefer the tRPC API directly.
