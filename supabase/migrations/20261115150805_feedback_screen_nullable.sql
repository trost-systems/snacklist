-- Job 259: a note written from More's row is about no screen, so the app sends none. Old apps still
-- send one; the format check stays and passes for null.
-- squawk-ignore ban-drop-not-null -- old apps only insert (always with a screen) and never read the column; the service role's readers handle null
alter table public.feedback alter column screen drop not null;
comment on column public.feedback.screen is 'The screen the note is about, a fixed name (list, account, …); never a path, code or item. Null when the entry point attaches none (More''s row since job 259).';
