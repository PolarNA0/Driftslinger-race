# Pending deploy — endless tracker

**This file exists because the change is on `main` but not live.** If you have
Supabase project access, do the steps below and then delete this file. If you do
not have access, stop and tell the human — do not mark it done.

Project ref: `pleotpbgzeohxbuxffiq`.

## What is waiting

| Item | Where | Why it is not live |
|---|---|---|
| Migration `0007_endless_tracker.sql` | `supabase/migrations/` | Migrations are applied by a human or agent with project access. CI does not run `db push`. |
| The `run` Edge Function (endless announcements) | `supabase/functions/run/index.ts` | `.github/workflows/deploy-functions.yml` fails with "Access token not provided": the `SUPABASE_ACCESS_TOKEN` repository secret is empty. It has failed on every push since 2026-11-17, so the deployed `run` may be older than `main` for earlier changes too. |

Until both are done, an endless run is stored normally but no Discord message is
posted: the function's `tracker_config` select names columns the database does
not have yet, so `announceEndless` returns early. Nothing else breaks.

## Do this

1. **Apply the migration.** The simplest path is the dashboard: open the SQL
   editor for project `pleotpbgzeohxbuxffiq` and run the whole of
   `supabase/migrations/0007_endless_tracker.sql`. It is additive and safe to
   re-run (`if not exists`, `create or replace`, `drop function if exists`).

   From the CLI, with a token that can reach the project:

   ```bash
   export SUPABASE_ACCESS_TOKEN=...   # supabase.com/dashboard/account/tokens
   supabase db push --project-ref pleotpbgzeohxbuxffiq
   ```

   (This repo has no `supabase/config.toml`, so use `--project-ref` rather than
   relying on a linked project.)

2. **Deploy both functions.**

   ```bash
   supabase functions deploy board --remote=pleotpbgzeohxbuxffiq --yes
   supabase functions deploy run   --remote=pleotpbgzeohxbuxffiq --yes
   ```

3. **Fix the deploy workflow so this does not happen again.** Add the token as a
   repository secret, then re-run the failed workflow:

   ```bash
   gh secret set SUPABASE_ACCESS_TOKEN --repo PolarNA0/Driftslinger-race
   gh workflow run deploy-functions.yml --repo PolarNA0/Driftslinger-race
   ```

   The token is the same one from <https://supabase.com/dashboard/account/tokens>.

## Verify

```sql
-- Must return the two defaults from the migration.
select endless_record_message, endless_message
from public.tracker_config where id = 1;
```

Expected:

- `{player} took the endless lead with {metres}m`
- `{player} reached {metres}m on the endless board (rank {rank} of {total})`

Then play one endless run on a signed-in account. The first run (or a further
distance) should post one message to the configured Discord channel. A 0m entry
posts nothing. Check the function log if it stays quiet:

```bash
supabase functions logs run --project-ref pleotpbgzeohxbuxffiq
```

Confirm the deployed function is the current commit:

```bash
supabase functions list --project-ref pleotpbgzeohxbuxffiq
```

## When it is done

Delete this file, remove the "Pending deploy" notes at the top of `AGENTS.md` and
`ROADMAP.md`, and commit + push. That is the signal to everyone else that the
server matches `main`.
