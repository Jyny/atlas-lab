# https://github.com/Jyny/atlas-lab/releases/tag/0.1.0
# https://atlasgo.io/atlas-schema/projects

variable "dev_url" {
  # https://atlasgo.io/concepts/dev-database
  type    = string
  default = "docker://postgres/18/dev?search_path=public"
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

variable "local_url" {
  # target database for local development
  type    = string
  default = "postgres://user:passwd@localhost:5432/default?search_path=public&sslmode=disable"
}

variable "staging_url" {
  # target database for a deployment other than local. kept out of the file so
  # credentials are not committed: `STAGING_URL=... make migrate.status ATLAS_ENV=staging`
  type    = string
  default = getenv("STAGING_URL")
}

variable "revisions_schema" {
  # keep the revisions table out of "public", otherwise declarative
  # `schema apply` sees it as drift and plans to drop it
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
  dev = var.dev_url
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
  dev = var.dev_url
  url = var.migration_dir

  format {
    schema {
      inspect = var.sql_indent
    }
  }
}

# main working env for both declarative and versioned commands
env "local" {
  dev = var.dev_url

  # desired state: --to for `schema apply` / `migrate diff`, --from for `schema diff`
  src = var.schema_src

  # target database: --url for `schema apply` / `migrate apply`
  url = var.local_url

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
# `STAGING_URL=... make migrate.status ATLAS_ENV=staging`.
# no `src`: applying a declarative desired state straight to a deployed
# database is exactly what versioned mode exists to avoid.
env "staging" {
  dev = var.dev_url
  url = var.staging_url

  migration {
    dir              = var.migration_dir
    revisions_schema = var.revisions_schema
  }
}
