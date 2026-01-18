# Atlas Schema Migration Lab

A playground for [Atlas](https://atlasgo.io/) schema migration workflows.

## Prerequisites

Install the following CLI tools:

- [Docker](https://docs.docker.com/get-docker/) - Container runtime
- [Atlas](https://atlasgo.io/getting-started#installation) - Database schema management

## Quick Start

```bash
# Start local database
make infra.up

# Apply schema changes (declarative mode)
make schema.apply

# Stop local database
make infra.down

# Restart local database
make infra.restart
```

## Workflow: Hybrid Schema Migration

This workflow combines **declarative** development with **versioned** migration for production.

### Local Development (Declarative Mode)

Edit `schema/schema.sql` directly, then:

```bash
# Format/normalize schema file
make schema.format

# Update schema.sql from migrations (replay migrations)
make schema.update

# Apply schema to local database
make schema.apply

# Clean all objects in local database
make schema.clean
```

### Production Deployment (Versioned Mode)

Generate migration files from schema changes:

```bash
# Generate migration diff
make migrate.diff <migration_name>

# Create empty migration file
make migrate.new <migration_name>

# Validate migrations
make migrate.validate

# Lint migrations against main branch
make migrate.lint

# Recalculate migration hash
make migrate.hash

# Apply migrations
make migrate.apply

# Check migration status
make migrate.status
```