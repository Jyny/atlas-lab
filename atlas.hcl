# https://github.com/Jyny/atlas-lab/releases/tag/0.1.0

variable "dev_db" {
  # https://atlasgo.io/concepts/dev-database
  type    = string
  default = "docker://postgres/18/dev?search_path=public"
}

variable "schema_file" {
  # declarative mode schema file path
  type    = string
  default = "file://schema/schema.sql"
}

variable "migration_dir" {
  # versioned mode migration directory path
  type    = string
  default = "file://migration"
}

variable "sql_fmt_2spc" {
  type    = string
  default = "{{ sql . \"  \" }}"
}

variable "local_db" {
  type    = string
  default = "postgres://user:passwd@localhost:5432/default?search_path=public&sslmode=disable"
}

# for make schema.format
env "schema" {
  dev = var.dev_db

  url = var.schema_file

  format {
    schema {
      inspect = var.sql_fmt_2spc
    }
  }
}

# for make schema.update
env "migrate" {
  dev = var.dev_db

  url = var.migration_dir

  format {
    schema {
      inspect = var.sql_fmt_2spc
    }
  }
}

env "local" {
  dev = var.dev_db

  // atlas migrate (versioned mode)
  migration {
    dir = var.migration_dir
  }

  // atlas migrate diff --to (desired state)
  schema {
    src = var.schema_file
  }

  // atlas migrate apply --url (target database)
  url = var.local_db

  format {
    migrate {
      diff  = var.sql_fmt_2spc
    }
  }
}
