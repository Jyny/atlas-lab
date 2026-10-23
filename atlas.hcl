# https://github.com/Jyny/atlas-lab/releases/tag/0.3.0
# https://atlasgo.io/atlas-schema/projects

# settings come from the environment (.env via the Makefile, see .env.example)
# and fall back to the defaults below, so plain `atlas ... --env local` works too.
# override one-off with `--var db_engine=mysql`.

variable "db_engine" {
  # postgres | mysql
  type    = string
  default = getenv("DB_ENGINE") != "" ? getenv("DB_ENGINE") : "postgres"
}

variable "db_user" {
  # postgres only, mysql connects as root (see docker-compose.yaml)
  type    = string
  default = getenv("DB_USER") != "" ? getenv("DB_USER") : "user"
}

variable "db_password" {
  type    = string
  default = getenv("DB_PASSWORD") != "" ? getenv("DB_PASSWORD") : "passwd"
}

variable "db_name" {
  type    = string
  default = getenv("DB_NAME") != "" ? getenv("DB_NAME") : "default"
}

locals {
  # https://atlasgo.io/concepts/dev-database
  dev_url = {
    postgres = "docker://postgres/18/dev?search_path=public"
    mysql    = "docker://mysql/8/dev"
  }[var.db_engine]

  # target database for local development, matching docker-compose.yaml
  local_url = {
    postgres = "postgres://${var.db_user}:${var.db_password}@localhost:5432/${var.db_name}?search_path=public&sslmode=disable"
    mysql    = "mysql://root:${var.db_password}@localhost:3306/${var.db_name}"
  }[var.db_engine]
}

variable "schema_src" {
  # declarative mode: desired state ("schema as code")
  type    = string
  default = "file://schema/schema.sql"
}

variable "migration_dir" {
  # versioned mode: migration directory
  type    = string
  default = "file://migration"
}

variable "staging_url" {
  # target database for a deployment other than local. kept out of the file so
  # credentials are not committed: set it in .env, or
  # `STAGING_URL=... make migrate.status ATLAS_ENV=staging`
  type    = string
  default = getenv("STAGING_URL")
}

variable "revisions_schema" {
  # keep the revisions table out of the target schema ("public" / db_name),
  # otherwise declarative `schema apply` sees it as drift and plans to drop it
  type    = string
  default = "atlas"
}

variable "sql_indent" {
  # https://atlasgo.io/atlas-schema/projects#format
  type    = string
  default = "{{ sql . \"  \" }}"
}

# atlas schema inspect --env schema
# reads schema/schema.sql and prints it back normalized
env "schema" {
  dev = local.dev_url
  url = var.schema_src

  format {
    schema {
      inspect = var.sql_indent
    }
  }
}

# atlas schema inspect --env migrate
# replays the migration directory and prints the resulting schema
env "migrate" {
  dev = local.dev_url
  url = var.migration_dir

  format {
    schema {
      inspect = var.sql_indent
    }
  }
}

# main working env for both declarative and versioned commands
env "local" {
  dev = local.dev_url

  # desired state: --to for `schema apply` / `migrate diff`, --from for `schema diff`
  src = var.schema_src

  # target database: --url for `schema apply` / `migrate apply`
  url = local.local_url

  # https://atlasgo.io/versioned/intro
  migration {
    dir              = var.migration_dir
    revisions_schema = var.revisions_schema
  }

  # https://atlasgo.io/lint/analyzers
  # the scope to lint (--latest N vs --git-base) is a per-invocation choice and
  # has no HCL equivalent, so it lives in the Makefile as ATLAS_LINT_* instead.
  # a `git { base = ... }` block here would silently win over --latest and make
  # `migrate lint` a no-op for migration files that are not committed yet.

  format {
    schema {
      inspect = var.sql_indent
      diff    = var.sql_indent
    }
    migrate {
      diff = var.sql_indent
    }
  }
}

# deployment target for the versioned commands, e.g.
# `make migrate.status ATLAS_ENV=staging` with STAGING_URL set in .env.
# its engine must match db_engine, since migrations are written in that dialect.
# no `src`: applying a declarative desired state straight to a deployed
# database is exactly what versioned mode exists to avoid.
env "staging" {
  dev = local.dev_url
  url = var.staging_url

  migration {
    dir              = var.migration_dir
    revisions_schema = var.revisions_schema
  }
}
