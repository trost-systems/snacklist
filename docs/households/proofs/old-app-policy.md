# Proof: old apps see one household after the multi-household migration

`old-app-policy.sql` builds a cut-down `households` / `household_members` schema with the
foundation's policy, applies the planned migration (drop `unique (user_id)`, `is_default`, the
default-only select policy for own rows, `household_members_of`), puts Peter in two more
households, adds the `after delete` trigger that hands the default on, and queries as a non-superuser role with `t.uid()` standing in for `auth.uid()`.

Run on 2026-11-07 (the trigger cases added after review 0, same day) in a throwaway `public.ecr.aws/supabase/postgres:17.11.0.006` container:

```
docker run -d --rm --name hh169-pg -e POSTGRES_PASSWORD=x public.ecr.aws/supabase/postgres:17.11.0.006
docker exec -i hh169-pg psql -U postgres -h localhost -d postgres -v ON_ERROR_STOP=1 -q < old-app-policy.sql
```

| Check | Result |
| --- | --- |
| Today's app query (own membership rows, `.maybeSingle()`) | 1 row, `Zuhause` (the default) |
| `is_household_member` for both households | true, true |
| Plain select of Sommerfest's members | hides Peter's own non-default row (why the new app needs `household_members_of`) |
| `household_members_of(Sommerfest)` as Peter | owner and Peter |
| `household_members_of(Sommerfest)` as Lea (not a member) | 0 rows |
| Lea's view of Zuhause's members | 2 rows, Peter included |
| Peter leaves Zuhause, his default (the `after delete` trigger promotes) | the old query returns 1 row, `Sommerfest`, his oldest remaining membership |
| Sommerfest is deleted as a whole (membership goes by cascade) | the old query returns 1 row, `Eltern` |
| Peter leaves his last household | 0 rows, no error (onboarding, as today) |
| Lea, who never left | still exactly one default |

Phase 2 turns this into pgTAP cases in `supabase/tests/`.

## Concurrent leaves (review 1)

`concurrent-leave.sh` runs `concurrent-leave-setup.sql` (a user in A (default), B and C, the
promotion trigger) in a throwaway container twice. Transaction 2 deletes B and holds 3 s, while
transaction 1 deletes A and its trigger picks B. The script prints the user's remaining membership:

```
subquery without a lock: 3 default=f
subquery with for update: 3 default=t
```

Without the lock the update hits B after it is gone and nothing becomes the default. With
`for update` the pick waits for B's lock, skips the deleted row and takes C. `old-app-policy.sql`
uses the locked subquery, and its output is unchanged.
