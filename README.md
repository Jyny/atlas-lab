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

## Configuration

Local settings live in `.env`, which is git-ignored. Create it from the tracked
[`.env.example`](./.env.example):

```bash
make env.init   # copies .env.example to .env, never overwrites
```

| Variable      | Default    | Used for                                          |
| ------------- | ---------- | ------------------------------------------------- |
| `DB_ENGINE`   | `postgres` | `postgres` or `mysql`: which database to run/target |
| `DB_USER`     | `user`     | local postgres user (mysql always uses `root`)    |
| `DB_PASSWORD` | `passwd`   | local database password                           |
| `DB_NAME`     | `default`  | local database name                               |
| `STAGING_URL` | *(empty)*  | target of the `staging` env                       |

The Makefile reads `.env` and exports these to docker compose and atlas, so
the three always agree. Without a `.env` every tool falls back to the defaults
above, and `atlas ... --env local` also works when run directly. Any of them can
be overridden per command, e.g. `make infra.up DB_ENGINE=mysql`, or from the
environment, e.g. `DB_ENGINE=mysql make infra.up`. Precedence is command line >
environment > `.env` > defaults, the same as docker compose.

Keep `.env` to plain `KEY=value` lines: make takes quotes and inline comments
literally.

The credentials only seed a *new* volume; after changing them run
`make infra.reset`.

### MySQL (optional)

PostgreSQL 18 is the default. Set `DB_ENGINE=mysql` to use MySQL 8 instead,
for both the local container and atlas' dev database:

```bash
echo DB_ENGINE=mysql >> .env   # or pass DB_ENGINE=mysql to each make call
make infra.up
make schema.apply
```

Each engine is a compose profile with its own volume, so only the selected one
starts and their data is kept apart. `schema/schema.sql` and `migration/` are
written in one SQL dialect, though: switching engines means starting them over
for the other dialect. `infra.reset` may remove both engines' volumes.

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

`schema.clean` only drops the schema the connection points at (`public` on
postgres, `DB_NAME` on mysql). The revision history in the `atlas` schema survives, so afterwards
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
`STAGING_URL` (in `.env` or the environment) so no credentials are committed:

```bash
# with STAGING_URL=postgres://user:passwd@staging-host:5432/app?sslmode=require in .env
make migrate.status ATLAS_ENV=staging

# or one-off
STAGING_URL='postgres://...' make migrate.status ATLAS_ENV=staging
```

The staging database must use the same engine as `DB_ENGINE`, since that is
the dialect the migrations are written and checked in.

Leaving `STAGING_URL` unset makes these targets stop before calling atlas with
`STAGING_URL is not set: add it to .env or pass STAGING_URL=...`. Run directly,
`atlas ... --env staging` resolves to an empty URL instead, which atlas reports
as `missing driver` or `required flag "url" not set` depending on the command.

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

`make migrate.baseline` runs `migrate apply --baseline <version>`: it records
that version and every earlier one as applied *without running them*, then
applies the files after it like a normal `migrate.apply`:

```bash
# baseline at the latest migration file (nothing is left to run)
make migrate.baseline

# or baseline at a specific version, then run the files after it
make migrate.baseline 20260101120000
```

Pick the version the database actually matches: the baselined files are never
executed, even on an empty database, and a mistyped version fails with
`baseline version "..." not found`. A database that already has revisions
ignores the baseline and just applies what is pending.

There is no side-effect-free preview. In atlas community v1.3.0,
`migrate apply --baseline <version> --dry-run` still writes the baseline row,
so `make migrate.plan` is not a dry run of this target. Check which files come
after the version with `ls migration/` before running it, especially with
`ATLAS_ENV=staging`.

### Formatting the config

```bash
make atlas.fmt
```
