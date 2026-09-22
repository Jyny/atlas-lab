# https://github.com/Jyny/atlas-lab/releases/tag/0.1.0

# a bare `make` would otherwise run the first target (infra.up) and silently
# start docker
.DEFAULT_GOAL := help

# targets that take a positional argument, e.g. `make migrate.new add_users`
ARG_TARGETS = migrate.diff migrate.new migrate.baseline

# only harvest arguments when one of those is invoked, otherwise `make a b`
# would declare real target `b` a no-op and make would warn about the clash
ifneq ($(filter $(ARG_TARGETS),$(firstword $(MAKECMDGOALS))),)
# arguments (all words after the target)
ARGS ?= $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
# avoid args being treated as unknown make targets
$(foreach arg,$(ARGS),$(eval $(arg):;@:))
endif

# show this list
# each target is documented by the first line of the comment block above it,
# so the listing stays in sync without a hand-kept table
.PHONY: help
help:
	@echo "usage: make <target> [VAR=value]"
	@echo
	@awk '\
	/^#/        { if (doc == "") doc = substr($$0, 3); next } \
	/^\.PHONY:/ { name = $$2; next } \
	/^[a-zA-Z0-9._-]+:/ { \
		if (name != "") printf "  %-16s %s\n", name, doc; \
		name = ""; doc = ""; next } \
	            { name = ""; doc = "" } \
	' $(MAKEFILE_LIST)
	@echo
	@echo "  migrate.diff / migrate.new take a name: make migrate.new add_users"
	@echo "  migrate.baseline takes an optional version: make migrate.baseline 20260101120000"
	@echo
	@echo "variables (shown with their current value):"
	@printf "  %-30s %s\n" \
		"ATLAS_ENV=$(ATLAS_ENV)" "env for migrate.plan/apply/status/baseline" \
		"ATLAS_APPROVE=$(ATLAS_APPROVE)" "set empty to restore the confirmation prompt" \
		"ATLAS_LINT_LATEST=$(ATLAS_LINT_LATEST)" "number of recent migrations to lint" \
		"ATLAS_LINT_BASE=$(ATLAS_LINT_BASE)" "git base to lint against instead (CI)" \
		"DC=$(DC)" "docker compose cli" \
		"ATLAS=$(ATLAS)" "atlas cli"


# docker cli
DC ?= docker-compose

# infra

# start the database in the background
.PHONY: infra.up
infra.up:
	$(DC) up -d

# stop the database, keeping its volume (data survives)
.PHONY: infra.down
infra.down:
	$(DC) down

# stop and start the database (data survives)
.PHONY: infra.restart
infra.restart: infra.down infra.up

# stop the database AND delete its volume (data is lost)
.PHONY: infra.reset
infra.reset:
	$(DC) down -v


# atlas cli
# command convention: atlas <group> <subcommand> --env <env> [flags] [args]
ATLAS ?= atlas

# atlas variables (must match atlas.hcl)
ATLAS_ENV ?= local
ATLAS_ENV_LOCAL = local
ATLAS_ENV_SCHEMA = schema
ATLAS_ENV_MIGRATE = migrate
ATLAS_SCHEMA_SQL = schema/schema.sql
ATLAS_SCHEMA_URL = file://$(ATLAS_SCHEMA_SQL)
ATLAS_MIGRATION_DIR = migration
ATLAS_MIGRATION_URL = file://$(ATLAS_MIGRATION_DIR)
ATLAS_SCHEMA_TMP = $(ATLAS_SCHEMA_SQL).tmp

# `schema apply` / `schema clean` prompt for confirmation, which fails outside a
# TTY. set ATLAS_APPROVE= to restore the interactive prompt.
ATLAS_APPROVE ?= --auto-approve

# `migrate lint` scope: the latest N files by default, or every file added since
# ATLAS_LINT_BASE when set (e.g. `make migrate.lint ATLAS_LINT_BASE=main` in CI)
ATLAS_LINT_LATEST ?= 1
ATLAS_LINT_BASE ?=

# overwrite schema.sql with `schema inspect` output from env $(1), leaving the
# existing file untouched if atlas fails. `exit 1` keeps the failure visible:
# a bare `rm -f` always succeeds and would make the target report success.
define atlas.inspect.to.schema
$(ATLAS) schema inspect --env $(1) > $(ATLAS_SCHEMA_TMP) \
&& mv $(ATLAS_SCHEMA_TMP) $(ATLAS_SCHEMA_SQL) \
|| { rm -f $(ATLAS_SCHEMA_TMP); exit 1; }
endef

# require a name argument, e.g. `make migrate.new add_users`
define require.args
@test -n "$(strip $(ARGS))" || { echo "usage: make $@ <migration_name>"; exit 1; }
endef

# format atlas.hcl itself
.PHONY: atlas.fmt
atlas.fmt:
	$(ATLAS) schema fmt atlas.hcl

# format schema.sql from inspect itself (to normalize formatting)
.PHONY: schema.format
schema.format:
	$(call atlas.inspect.to.schema,$(ATLAS_ENV_SCHEMA))

# update schema.sql from migrations (replay migrations to get desired schema)
.PHONY: schema.update
schema.update:
	$(call atlas.inspect.to.schema,$(ATLAS_ENV_MIGRATE))

# show drift between migrations and schema.sql (no database needed)
.PHONY: schema.diff
schema.diff:
	$(ATLAS) schema diff --env $(ATLAS_ENV_LOCAL) \
	--from "$(ATLAS_MIGRATION_URL)" --to "$(ATLAS_SCHEMA_URL)"

# preview the plan for schema.apply without touching the database
.PHONY: schema.plan
schema.plan:
	$(ATLAS) schema apply --env $(ATLAS_ENV_LOCAL) --dry-run

# apply declarative schema.sql to local database ONLY
.PHONY: schema.apply
schema.apply:
	$(ATLAS) schema apply --env $(ATLAS_ENV_LOCAL) $(ATLAS_APPROVE)

# clean all objects in local database ONLY
# only drops the schema in the url's search_path ("public"), so the revisions
# in the "atlas" schema survive and `migrate.status` still counts those files
# as executed against what is now an empty database. use infra.reset for a
# true zero state.
.PHONY: schema.clean
schema.clean:
	$(ATLAS) schema clean --env $(ATLAS_ENV_LOCAL) $(ATLAS_APPROVE)

# gen migration file from migrations to schema
.PHONY: migrate.diff
migrate.diff:
	$(require.args)
	$(ATLAS) migrate diff --env $(ATLAS_ENV_LOCAL) $(ARGS)

# create new migration file
.PHONY: migrate.new
migrate.new:
	$(require.args)
	$(ATLAS) migrate new --env $(ATLAS_ENV_LOCAL) $(ARGS)

# lint migration files (scope is set by ATLAS_LINT_LATEST / ATLAS_LINT_BASE)
.PHONY: migrate.lint
migrate.lint:
	$(ATLAS) migrate lint --env $(ATLAS_ENV_LOCAL) \
	$(if $(ATLAS_LINT_BASE),--git-base $(ATLAS_LINT_BASE),--latest $(ATLAS_LINT_LATEST))

# validate migration files
.PHONY: migrate.validate
migrate.validate:
	$(ATLAS) migrate validate --env $(ATLAS_ENV_LOCAL)

# hash migration files
.PHONY: migrate.hash
migrate.hash:
	$(ATLAS) migrate hash --env $(ATLAS_ENV_LOCAL)

# preview pending migrations without applying them (default: local)
.PHONY: migrate.plan
migrate.plan:
	$(ATLAS) migrate apply --env $(ATLAS_ENV) --dry-run

# apply migrations to target database (default: local)
.PHONY: migrate.apply
migrate.apply:
	$(ATLAS) migrate apply --env $(ATLAS_ENV)

# show migration status for target database (default: local)
.PHONY: migrate.status
migrate.status:
	$(ATLAS) migrate status --env $(ATLAS_ENV)

# mark migrations as already applied WITHOUT running them (default: local)
# needed when switching a database built by `schema.apply` over to versioned
# mode: `migrate apply` refuses a non-empty database that has no revisions.
# pass a version to baseline at, or omit to baseline at the latest file.
.PHONY: migrate.baseline
migrate.baseline:
	@v="$(strip $(ARGS))"; \
	test -n "$$v" || v=$$(ls $(ATLAS_MIGRATION_DIR)/*.sql | sort | tail -1 \
		| xargs basename | sed 's/_.*//; s/\.sql$$//'); \
	echo "$(ATLAS) migrate set --env $(ATLAS_ENV) $$v"; \
	$(ATLAS) migrate set --env $(ATLAS_ENV) "$$v"
