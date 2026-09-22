# Atlas Schema Migration Lab

A playground for [Atlas](https://atlasgo.io/) schema migration workflows.

Targets Atlas **v1.x**, whose command convention is:

```
atlas <group> <subcommand> --env <env> [flags] [args]
```

Everything else (URLs, dev database, migration directory, lint policy, output
format) lives in [`atlas.hcl`](./atlas.hcl) rather than on the command line.

## Prerequisites

Install the following CLI tools:

- [Docker](https://docs.docker.com/get-docker/) - Container runtime
- [Atlas](https://atlasgo.io/getting-started#installation) - Database schema management

> The community build covers everything in this lab. `schema plan`, `schema test`,
> `migrate test`, `migrate down` and the registry commands require the official
> build (`curl -sSf https://atlasgo.sh | sh`).
>
> Note that `make schema.plan` is *not* the official-only `atlas schema plan`;
> it is `schema apply --dry-run`, same as `make migrate.plan` is
> `migrate apply --dry-run`.

## Quick Start

```bash
# List every target and the variables you can override
make            # `make` with no target does this, it does not start anything

# Start local database
make infra.up

# Apply schema changes (declarative mode)
make schema.apply

# Stop local database (data is kept in a named volume)
make infra.down

# Restart local database
make infra.restart

# Stop local database and delete its data
make infra.reset
```

## Workflow: Hybrid Schema Migration

This workflow combines **declarative** development with **versioned** migration for production.

`schema/schema.sql` is the desired state; `migration/` is the versioned history
derived from it. Both are applied to the same database, so the revisions table is
kept in a separate `atlas` schema — otherwise declarative apply would see it as
drift and plan to drop it.

### Local Development (Declarative Mode)

Edit `schema/schema.sql` directly, then:

```bash
# Format/normalize schema file
make schema.format

# Update schema.sql from migrations (replay migrations)
make schema.update

# Show drift between migrations and schema.sql (no database needed)
make schema.diff

# Preview what schema.apply would do
make schema.plan

# Apply schema to local database
make schema.apply

# Clean all objects in local database
make schema.clean
```

`schema.apply` and `schema.clean` run with `--auto-approve` so they work in
pipelines and scripts. Set `ATLAS_APPROVE=` to get the confirmation prompt back:

```bash
make schema.clean ATLAS_APPROVE=
```

`schema.clean` only drops the schema in the connection's `search_path`
(`public`). The revision history in the `atlas` schema survives, so afterwards
`migrate.status` still reports every applied version as executed against what
is now an empty database — and `migrate.apply` will skip the migrations that
would recreate it. Use `make infra.reset` when you want a true zero state.

### Production Deployment (Versioned Mode)

Generate migration files from schema changes:

```bash
# Generate migration diff
make migrate.diff <migration_name>

# Create empty migration file
make migrate.new <migration_name>

# Validate migrations
make migrate.validate

# Lint the latest migration
make migrate.lint

# Lint the latest N migrations
make migrate.lint ATLAS_LINT_LATEST=3

# Lint every migration added since a git branch (for CI)
make migrate.lint ATLAS_LINT_BASE=main

# Recalculate migration hash
make migrate.hash

# Preview pending migrations
make migrate.plan

# Apply migrations
make migrate.apply

# Check migration status
make migrate.status
```

`ATLAS_LINT_BASE` compares against a git ref, so it only sees *committed*
migration files. On a branch with nothing new relative to the base it exits 0
without output — a pass, not a skip. `ATLAS_LINT_LATEST` is the one to use
before committing.

#### Targeting another database

`migrate.plan`, `migrate.apply`, `migrate.status` and `migrate.baseline` target
the `local` env by default. Point them at another env from `atlas.hcl` with
`ATLAS_ENV`. Besides `local`, this lab defines `staging`, whose URL comes from
the `STAGING_URL` environment variable so no credentials are committed:

```bash
STAGING_URL='postgres://user:passwd@staging-host:5432/app?sslmode=require' \
  make migrate.status ATLAS_ENV=staging
```

Leaving `STAGING_URL` unset makes the env resolve to an empty URL, which atlas
reports as `Error: sql/sqlclient: missing driver`.

The `schema.*` targets and `migrate.diff` / `new` / `lint` / `validate` /
`hash` are pinned to `local` on purpose and ignore `ATLAS_ENV` — they author
migrations against the dev database, they do not deploy them.

### Switching a declarative database to versioned mode

`migrate apply` refuses a database that already has objects but no revision
history — which is exactly what `schema.apply` leaves behind:

```
Error: sql/migrate: connected database is not clean: found table "users"
in schema "public". baseline version or allow-dirty is required
```

Record the existing migrations as applied without running them, then continue
normally:

```bash
# baseline at the latest migration file
make migrate.baseline

# or baseline at a specific version
make migrate.baseline 20260101120000
```

### Formatting the config

```bash
make atlas.fmt
```
