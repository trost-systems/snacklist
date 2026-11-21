-- Job 349: the catalog changed in the two migrations before this one. A catalog change snapshots
-- the version it replaces, so the version they leave has no snapshot yet. Rebuilding the lexicon
-- unchanged takes it in a transaction of its own (catalog_delta reads it for devices on the
-- version before).
select public.refresh_classifier_lexicon();
