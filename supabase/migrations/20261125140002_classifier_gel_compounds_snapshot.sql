-- Job 349: a catalog change snapshots the version it replaces, so the version the dictionary
-- migration before this one leaves has no snapshot yet. Rebuilding the lexicon unchanged takes it
-- in a transaction of its own (catalog_delta reads it).
select public.refresh_classifier_lexicon();
