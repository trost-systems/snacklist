-- Job 267 review 0 (docs/FEEDBACK.md, "Screenshots"): screenshots arrive only through the
-- feedback-screenshots function. With a client insert policy, a signed upload URL
-- (POST /storage/v1/object/upload/sign/...) passed the policy once when signed and then stored
-- as the storage superuser, past both quotas. Without any client policy neither a direct upload
-- nor signing works for a client; the function checks the quotas here under a lock and stores
-- with the secret key.

drop policy feedback_screenshots_insert_own on storage.objects;

-- The policy was its only caller; no client may ask whether the bucket is full.
revoke execute on function public.feedback_screenshot_quota_left(text) from authenticated;
comment on function public.feedback_screenshot_quota_left(text) is
  'Unused since 20261115200000 (job 267 review 0): public.feedback_screenshot_admit checks the quotas.';

-- Whether the function may store <p_user>/<p_id>.png: 'exists' when it is there already, 'quota'
-- when the user stored 10 in the last 24 hours or the bucket holds 250 images (2 MiB each at
-- most: 500 MiB of the free plan's 1 GB), else 'new'. Takes a transaction-scoped lock first, so
-- the caller keeps it while it stores through the Storage API and commits after: parallel uploads
-- see each other's objects and cannot overshoot.
create function public.feedback_screenshot_admit(p_user uuid, p_id uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_bucket constant text := 'feedback-screenshots';
  v_name constant text := p_user::text || '/' || p_id::text || '.png';
begin
  perform pg_advisory_xact_lock(hashtextextended('storage_buckets:' || v_bucket::text, 0));
  if exists (select from storage.objects o where o.bucket_id = v_bucket and o.name = v_name) then
    return 'exists';
  end if;
  if (select count(*) from storage.objects o
      where o.bucket_id = v_bucket
        and o.name like p_user::text || '/%'
        and o.created_at > now() - interval '24 hours') >= 10
    or (select count(*) from storage.objects o where o.bucket_id = v_bucket) >= 250
  then
    return 'quota';
  end if;
  return 'new';
end $$;

-- The function connects as the owner; neither clients nor the service key run it.
revoke execute on function public.feedback_screenshot_admit(uuid, uuid)
  from public, anon, authenticated, service_role;

-- A note may name an image that was never stored: only names with a stored image are queued, so
-- such notes cannot crowd real removals out of the sweep's batch.
create or replace function public.feedback_queue_screenshot_removal() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.feedback_screenshot_removals (name)
  select o.screenshot from old_notes o
  where o.screenshot is not null
    and exists (select from storage.objects s
                where s.bucket_id = 'feedback-screenshots' and s.name = o.screenshot)
  on conflict (name) do nothing;
  return null;
end $$;
