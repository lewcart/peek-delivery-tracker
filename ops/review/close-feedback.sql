-- Closes a reader's answer once it is routed or handled: sets reviewed_at and the review note.
-- The note says what was off and what became of it in other words than the reader's, since
-- their note can hold personal details. Prints the closed id, or nothing when the answer is
-- unknown or was closed before. See docs/OBSERVABILITY.md.
--
--   psql "$DATABASE_URL" -v id=<answer id> -v note='Routed to the adapters lane: ...' -f ops/review/close-feedback.sql
\set ON_ERROR_STOP on
\set QUIET on
\if :{?id}
\else
  \warn 'close-feedback.sql needs -v id=<answer id>'
  \quit
\endif
\if :{?note}
\else
  \warn 'close-feedback.sql needs -v note=<review note>'
  \quit
\endif

update public.parcel_feedback
set reviewed_at = now(), review_note = :'note'
where id = :'id' and reviewed_at is null
returning id, review_note;
