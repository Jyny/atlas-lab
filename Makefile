# docker cli
DC ?= docker compose

# infra
.PHONY: infra.up
infra.up:
	$(DC) up -d

.PHONY: infra.down
infra.down:
	$(DC) down

.PHONY: infra.restart
infra.restart: infra.down infra.up


# atlas cli
ATLAS ?= atlas

# atlas envs (must match atlas.hcl)
ATLAS_ENV  ?= local
ATLAS_ENV_LOCAL  ?= local
ATLAS_ENV_SCHEMA = schema
ATLAS_SCHEMA_DIR = schema
ATLAS_SCHEMA_SQL ?= $(ATLAS_SCHEMA_DIR)/schema.sql
ATLAS_SCHEMA_TMP ?= $(ATLAS_SCHEMA_DIR)/schema.sql.tmp

# arguments
ARG1 := $(word 2,$(MAKECMDGOALS))

# inspect schema.sql to self (acts like formatting / normalization)
.PHONY:	schema.format
schema.format:
	$(ATLAS) schema --env $(ATLAS_ENV_SCHEMA) inspect > $(ATLAS_SCHEMA_TMP) \
	&& mv $(ATLAS_SCHEMA_TMP) $(ATLAS_SCHEMA_SQL) || rm -f $(ATLAS_SCHEMA_TMP)

# apply declarative schema.sql to local database ONLY
.PHONY: schema.apply
schema.apply:
	$(ATLAS) schema --env $(ATLAS_ENV_LOCAL) apply

# clean all objects in local database ONLY
.PHONY: schema.clean
schema.clean:
	$(ATLAS) schema --env $(ATLAS_ENV_LOCAL) clean

# gen diff diff from migrations to schema
.PHONY:	migrate.diff
migrate.diff:
	$(ATLAS) migrate --env $(ATLAS_ENV_LOCAL) diff $(ARG1)

.PHONY: migrate.new
migrate.new:
	$(ATLAS) migrate --env $(ATLAS_ENV_LOCAL) new $(ARG1)

.PHONY: migrate.lint
migrate.lint:
	$(ATLAS) migrate --env $(ATLAS_ENV_LOCAL) lint --git-base main

.PHONY: migrate.validate
migrate.validate:
	$(ATLAS) migrate --env $(ATLAS_ENV_LOCAL) validate

.PHONY: migrate.hash
migrate.hash:
	$(ATLAS) migrate --env $(ATLAS_ENV_LOCAL) hash

.PHONY: migrate.apply
migrate.apply:
	$(ATLAS) migrate --env $(ATLAS_ENV) apply

.PHONY: migrate.status
migrate.status:
	$(ATLAS) migrate --env $(ATLAS_ENV) status


%:
	@echo "unknown target: $@"
	@exit 1