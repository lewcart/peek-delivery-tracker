-- A reader's note may run to 4000 characters. At 1000 the form cut a long note off where it
-- stopped taking keys, without saying so.
--
-- Apply this before deploying the server that accepts the longer notes. The server before it
-- keeps working on this schema: it still refuses a note over 1000 characters.

alter table public.parcel_feedback
  drop constraint parcel_feedback_note_check,
  add constraint parcel_feedback_note_check check (length(note) between 1 and 4000);

insert into public.applied_migrations (name) values ('20261024160000_longer_feedback_notes') on conflict do nothing;
