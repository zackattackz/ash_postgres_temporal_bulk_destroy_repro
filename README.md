# Temporal resources: an atomic bulk destroy that returns records fails with `column f.valid_at does not exist`

Minimal reproduction for an AshPostgres bug. On a temporal resource, an atomic
bulk destroy of a query fails with an SQL error whenever it has to return the
destroyed records: with `notify?: true`, or `return_records?: true`. Signal
listeners that destroy run exactly this, since Ash runs every listener's bulk
action with `notify?: true`.

- ash 3.36.1, ash_postgres 2.14.5, PostgreSQL 18
- Elixir 1.20.4, Erlang/OTP 29 (`.tool-versions`)
- One temporal resource, `Repro.Blog.Post`, with a `title` and default actions.

## Run

It needs PostgreSQL 18. The default `DATABASE_URL` points at port **54321**,
not 5432, so it doesn't use a Postgres you already run. A throwaway server:

```sh
docker run --rm -p 54321:5432 -e POSTGRES_PASSWORD=postgres postgres:18
```

Then:

```sh
mix deps.get
mix test
```

To use another server, set `DATABASE_URL`, for example
`postgres://user:pass@localhost:5432/ash_postgres_temporal_bulk_destroy_repro`.

### What it does to the database

`mix test` runs `mix ash.setup` first, which creates and migrates. It never
drops anything. On the server `DATABASE_URL` names, it:

- creates the database `ash_postgres_temporal_bulk_destroy_repro` if it
  doesn't exist;
- installs `btree_gist` and Ash's `ash_*` SQL functions in that database
  only;
- creates a `posts` table.

Each test runs in a transaction that is rolled back, so no rows are left. No
other database is read or changed. To remove what it created:

```sh
mix ecto.drop   # or stop the docker container above (--rm discards it)
```

## What the test does

`test/bulk_destroy_test.exs` creates a post and destroys it with
`Ash.bulk_destroy/4` on a query for it (`strategy: [:atomic]`,
`return_errors?: true` so the error is shown):

| Bulk action | Result |
|---|---|
| atomic bulk destroy, `notify?: true` | **fails**: `ERROR 42703 (undefined_column) column f.valid_at does not exist` |
| atomic bulk destroy, `return_records?: true` | **fails**: the same error |
| atomic bulk destroy, returning nothing | works |
| streamed bulk destroy, `notify?: true` | works |
| atomic bulk update, `notify?: true` and `return_records?: true` | works |
| `Ash.destroy!/1` on the record | works |

The failing statement, shortened:

```sql
WITH ...,
"__fpo" AS (DELETE FROM "posts" AS p0 WHERE ... RETURNING p0."id", p0."title", old AS "__old"),
"__leftovers" AS (INSERT INTO "posts" ... FROM "__fpo" f, ...)
(SELECT DISTINCT ON (f."id") f."id", f."title", 'ok' AS "__status"
   FROM "__fpo" f ORDER BY f."id", lower(f."valid_at"))
UNION ALL ...
```

`"__fpo"` doesn't return `valid_at`, but the final `ORDER BY` reads
`f."valid_at"`. The atomic bulk update that works returns
`p0."id", p0."title", p0."valid_at", old AS "__old"`.

Without `return_errors?: true`, the error shows only as "Something went wrong
with bulk update, but no errors were produced due to `return_errors?` being set
to `false`."
