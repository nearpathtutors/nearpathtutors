-- NearPath Tutors — database schema for Supabase
-- Run this once in your Supabase project's SQL Editor (see README.md).

-- 1) profiles: one row per signed-up user (student, teacher, or admin)
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('student','teacher','admin')),
  full_name text not null,
  grade text,  -- a student's own grade/class (e.g. "Grade 8"), set from their dashboard; unused for teachers/admins
  stream text,  -- for grade 11/12 students only (e.g. "Science (PCM)", "Commerce"); null otherwise
  created_at timestamptz not null default now(),
  last_seen_at timestamptz  -- stamped by the client every so often while the app is open; used to show "Online" (via Realtime Presence) or "Last seen …" in chat
);

-- 2) teacher_profiles: the public listing data for a teacher
create table teacher_profiles (
  profile_id uuid primary key references profiles(id) on delete cascade,
  initials text,
  color text default '#6C5CE7',
  category text default 'academics',
  subjects text[] default '{}',
  location text default '',
  lat double precision,
  lng double precision,
  maps_link text default '',
  fee_start int default 0,
  fee_unit text default '/month',
  experience text default '',
  bio text default '',
  rating numeric default 0,
  reviews int default 0
);

-- 3) schedule_slots: a teacher's weekly timing slots
create table schedule_slots (
  id bigserial primary key,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  day text not null,
  time text not null,
  subj text not null
);

-- 4) enquiries: messages a student sends to a teacher
create table enquiries (
  id bigserial primary key,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now()
);

-- 5) enrollments: a student enrolled with a teacher for a subject
create table enrollments (
  id bigserial primary key,
  student_id uuid not null references profiles(id) on delete cascade,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  subject text not null,
  schedule text default '',
  fee int default 0,
  status text not null default 'due' check (status in ('due','overdue','paid')),
  due_date date,
  grade text,
  created_at timestamptz not null default now(),
  unique(student_id, teacher_id, subject)  -- a student can only enroll once per subject with a given teacher
);

-- 6) payments: a record each time fees are marked paid
create table payments (
  id bigserial primary key,
  enrollment_id bigint references enrollments(id) on delete set null,
  student_id uuid not null references profiles(id) on delete cascade,
  amount int not null,
  method text default 'UPI',
  paid_at timestamptz not null default now()
);

-- 7) reviews: a parent's star rating + comment for a teacher, tied to a
-- specific enrollment (one review per enrollment). teacher_profiles.rating
-- and .reviews are kept in sync automatically by the trigger below.
create table reviews (
  id bigserial primary key,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  enrollment_id bigint unique references enrollments(id) on delete set null,
  rating int not null check (rating between 1 and 5),
  comment text default '',
  created_at timestamptz not null default now()
);

-- 8) messages: a realtime back-and-forth chat between one student and
-- one teacher. Unlike `enquiries` (a single first-contact note shown in
-- the teacher's dashboard), this is an ongoing thread — every row is one
-- message, and the app subscribes to new rows via Supabase Realtime so
-- both sides see replies appear instantly, with no refresh needed.
-- reply_to lets a message quote an earlier one in the same thread.
-- read_at is stamped once the recipient has actually read the message —
-- see mark_messages_read() below, the only thing allowed to set it —
-- and is what drives the persisted "Seen" marker (survives a refresh,
-- unlike an in-memory-only read receipt would).
create table messages (
  id bigserial primary key,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  sender_id uuid not null references profiles(id) on delete cascade,
  body text not null,
  reply_to bigint references messages(id) on delete set null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- 9) batches: a teacher's structured, recurring class — grade, subject,
-- days of the week, a time slot, an optional capacity, and a description.
-- This is the structured counterpart to the free-text "weekly schedule"
-- a teacher can also set on their profile (schedule_slots): batches are
-- what a teacher actually assigns students to (via batch_students) and
-- what students see and can request a trial class for on a teacher's
-- public profile.
create table batches (
  id bigserial primary key,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  name text not null,
  grade text default '',
  stream text default '',  -- only meaningful when grade is 11/12 (e.g. "Science (PCM)")
  subject text not null,
  days text[] not null default '{}',
  time text default '',
  description text default '',
  capacity int,
  status text not null default 'active' check (status in ('active','inactive')),
  current_topic text default '',   -- "which chapter is going on" — shown to students on their Batches tab
  next_class_date date,            -- shown to students on their Batches tab
  created_at timestamptz not null default now()
);

-- 10) batch_students: which students a teacher has placed into which batch.
create table batch_students (
  id bigserial primary key,
  batch_id bigint not null references batches(id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  added_at timestamptz not null default now(),
  unique(batch_id, student_id)
);

-- 11) trial_requests: a student's request for a spot in a trial class for
-- a specific batch. Created by the student (pending), then approved or
-- declined by the teacher from their dashboard — both sides see the
-- status change live via Realtime. response_message is whatever the
-- teacher typed when responding (e.g. "See you Monday at 4!"), surfaced
-- to the student as a notification.
create table trial_requests (
  id bigserial primary key,
  batch_id bigint not null references batches(id) on delete cascade,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  note text default '',
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  response_message text default '',
  created_at timestamptz not null default now(),
  responded_at timestamptz
);

-- 12) attendance: one row per student per batch per date. A teacher marks
-- it from a batch's detail view; a student can see their own record.
create table attendance (
  id bigserial primary key,
  batch_id bigint not null references batches(id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  date date not null default current_date,
  status text not null default 'present' check (status in ('present','absent','late')),
  marked_at timestamptz not null default now(),
  unique(batch_id, student_id, date)
);

-- 13) notifications: things a teacher sends a student — a trial class
-- being approved/declined (with their message attached), a heads-up about
-- a batch's timing changing or a class being cancelled, a fee-payment
-- reminder, or new assessment marks being published. Streamed live via
-- Realtime so a student's Notifications tab updates instantly.
create table notifications (
  id bigserial primary key,
  student_id uuid not null references profiles(id) on delete cascade,
  -- nullable so an admin can broadcast to a student without it being tied
  -- to any one teacher (see the 'admin_broadcast' type below)
  teacher_id uuid references teacher_profiles(profile_id) on delete cascade,
  batch_id bigint references batches(id) on delete set null,
  type text not null default 'general' check (type in ('trial_approved','trial_declined','batch_update','batch_cancelled','fee_reminder','assessment','admin_broadcast','general')),
  title text not null,
  message text default '',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- 13c) teacher_notifications: the mirror image of `notifications`, but
-- flowing student→teacher (or admin→teacher) instead of teacher→student —
-- a student enrolling, a student sending an enquiry, a student marking
-- their own fee as paid, or an admin's site-wide announcement. Streamed
-- live via Realtime so a teacher's notification bell updates instantly,
-- exactly like the student-facing one.
create table teacher_notifications (
  id bigserial primary key,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  student_id uuid references profiles(id) on delete set null,
  enrollment_id bigint references enrollments(id) on delete set null,
  type text not null default 'general' check (type in ('new_enrollment','new_enquiry','fee_paid','admin_broadcast','general')),
  title text not null,
  message text default '',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- 13b) assessments: a test/quiz a teacher records against a batch, and
-- assessment_marks: each student's score for it. A teacher sends marks to
-- a whole batch at once from the batch detail view; each student sees
-- only their own marks (and a notification when new ones are published).
create table assessments (
  id bigserial primary key,
  batch_id bigint not null references batches(id) on delete cascade,
  teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
  subject text not null,
  title text not null,
  max_marks int not null default 100,
  created_at timestamptz not null default now()
);

create table assessment_marks (
  id bigserial primary key,
  assessment_id bigint not null references assessments(id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  marks numeric not null,
  remarks text default '',
  created_at timestamptz not null default now(),
  unique(assessment_id, student_id)
);

-- 14) site_settings: a small key/value store for site-wide toggles.
-- Currently holds one row (key='maintenance', value={"enabled":bool}) that
-- every visitor's page checks before rendering anything else. Publicly
-- readable (any visitor needs to check it) but only an admin can change
-- it — see the "admins can change site settings" policy below.
create table site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
insert into site_settings (key, value) values ('maintenance', jsonb_build_object('enabled', false))
  on conflict (key) do nothing;

-- 15) site_logs: a client-reported error log — every time a
-- student/teacher/admin dashboard fails to load its data, the browser
-- writes a row here (in addition to logging it to its own console) so an
-- admin can see the reason from the admin panel's Diagnostics tab
-- without having to ask the person to open dev tools. Anyone can insert
-- one (it needs to work even for a half-signed-in user), but only an
-- admin can read or clear the log.
create table site_logs (
  id bigserial primary key,
  level text not null default 'error' check (level in ('error','warn','info')),
  context text not null,       -- e.g. "Student dashboard", "Teacher dashboard"
  message text not null,
  code text,
  details text,
  hint text,
  user_id uuid references profiles(id) on delete set null,
  user_role text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------
-- Row Level Security: lock every table down, then open specific,
-- narrow policies. Without this, the anon key can read/write anything.
-- ---------------------------------------------------------------
alter table profiles enable row level security;
alter table site_settings enable row level security;
alter table teacher_profiles enable row level security;
alter table schedule_slots enable row level security;
alter table enquiries enable row level security;
alter table enrollments enable row level security;
alter table payments enable row level security;
alter table reviews enable row level security;
alter table messages enable row level security;
alter table batches enable row level security;
alter table batch_students enable row level security;
alter table trial_requests enable row level security;
alter table attendance enable row level security;
alter table notifications enable row level security;
alter table teacher_notifications enable row level security;
alter table assessments enable row level security;
alter table assessment_marks enable row level security;
alter table site_logs enable row level security;

-- profiles: names are shown publicly (e.g. "with Ritu Sharma"), but only
-- the owner can create/change their own row.
create policy "profiles are publicly readable" on profiles for select using (true);
create policy "users can insert their own profile" on profiles for insert with check (auth.uid() = id);
create policy "users can update their own profile" on profiles for update using (auth.uid() = id);

-- ---------------------------------------------------------------
-- Admin: is_admin() checks whether the currently-authenticated user's own
-- profile row has role='admin'. It's security definer so it can read
-- profiles.role for that check regardless of which policy is currently
-- being evaluated. Only a user who is genuinely signed in via Supabase
-- auth AND already marked role='admin' (see README "Part 7" for how to
-- create that account) passes this — the admin login screen's password
-- box is what Supabase actually checks; this function is what the
-- database checks before allowing a delete.
-- ---------------------------------------------------------------
create or replace function is_admin() returns boolean as $$
  select exists(select 1 from profiles where id = auth.uid() and role = 'admin');
$$ language sql security definer stable;

-- Lets an admin remove any teacher or student's profile from the admin
-- panel. Deleting a profiles row cascades (via each table's "on delete
-- cascade") to that person's teacher_profiles/schedule_slots, enquiries,
-- enrollments, payments, and reviews automatically.
create policy "admins can delete any profile" on profiles for delete using (is_admin());

-- Lets the admin panel's Analytics tab total up enrollments, payments, and
-- enquiries across every user (each of those tables is otherwise only
-- visible to the two people involved — see their policies further down).
create policy "admins can view all enrollments" on enrollments for select using (is_admin());
create policy "admins can view all payments" on payments for select using (is_admin());
create policy "admins can view all enquiries" on enquiries for select using (is_admin());

-- Lets the admin panel's review-moderation table remove an inappropriate
-- review. reviews are already publicly readable (see their own policy),
-- so this only adds the delete permission. The rating trigger further
-- down recalculates the teacher's average automatically afterwards.
create policy "admins can delete any review" on reviews for delete using (is_admin());

-- site_settings: publicly readable (every visitor's page checks the
-- maintenance flag before rendering), but only an admin can change it —
-- this is the actual lock behind the admin panel's maintenance toggle.
create policy "site settings are publicly readable" on site_settings for select using (true);
create policy "admins can change site settings" on site_settings for all using (is_admin()) with check (is_admin());

-- site_logs: anyone (even a not-fully-signed-in user) can write an error
-- report about their own session; only an admin can read or clear them.
create policy "anyone can report an error" on site_logs for insert with check (true);
create policy "admins can view logs" on site_logs for select using (is_admin());
create policy "admins can clear logs" on site_logs for delete using (is_admin());

-- ---------------------------------------------------------------
-- Realtime: stream site_settings changes to every open tab, so someone
-- already browsing sees the maintenance page appear/disappear live the
-- moment an admin toggles it, without needing to refresh.
-- ---------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'site_settings'
  ) then
    alter publication supabase_realtime add table site_settings;
  end if;
end $$;

-- teacher_profiles: the whole point is to be a public directory.
create policy "teacher profiles are publicly readable" on teacher_profiles for select using (true);
create policy "teachers can insert their own listing" on teacher_profiles for insert with check (auth.uid() = profile_id);
create policy "teachers can update their own listing" on teacher_profiles for update using (auth.uid() = profile_id);

-- schedule_slots: public to read (shown on profile pages), owner-only to edit.
create policy "schedule is publicly readable" on schedule_slots for select using (true);
create policy "teachers manage their own schedule" on schedule_slots for all using (auth.uid() = teacher_id) with check (auth.uid() = teacher_id);

-- enquiries: only visible to the two people involved.
create policy "enquiry visible to sender or recipient" on enquiries for select using (auth.uid() = teacher_id or auth.uid() = student_id);
create policy "students can send enquiries" on enquiries for insert with check (auth.uid() = student_id);

-- enrollments: only visible to the student and their teacher.
create policy "enrollment visible to student or teacher" on enrollments for select using (auth.uid() = student_id or auth.uid() = teacher_id);
create policy "students can enroll themselves" on enrollments for insert with check (auth.uid() = student_id);
create policy "student or teacher can update an enrollment" on enrollments for update using (auth.uid() = student_id or auth.uid() = teacher_id);

-- payments: only the paying student can see or create their own payment records.
create policy "payments visible to the paying student" on payments for select using (auth.uid() = student_id);
create policy "students can record their own payments" on payments for insert with check (auth.uid() = student_id);

-- reviews: shown publicly on a teacher's profile, but only the reviewing
-- student can create or edit their own review.
create policy "reviews are publicly readable" on reviews for select using (true);
create policy "students can leave a review" on reviews for insert with check (auth.uid() = student_id);
create policy "students can edit their own review" on reviews for update using (auth.uid() = student_id);

-- messages: only the two people in a conversation can read it, and you
-- can only ever send as yourself, and only into a conversation you're
-- actually part of (as its teacher or its student).
create policy "messages visible to the two participants" on messages for select using (auth.uid() = teacher_id or auth.uid() = student_id);
create policy "participants can send messages" on messages for insert with check (
  auth.uid() = sender_id and (auth.uid() = teacher_id or auth.uid() = student_id)
);

-- ---------------------------------------------------------------
-- Realtime: stream new `messages` rows to subscribed clients the instant
-- they're inserted, so both sides see a reply appear without refreshing.
-- Wrapped in an existence check so this file stays safe to re-run (adding
-- a table that's already in the publication would otherwise error).
-- ---------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table messages;
  end if;
end $$;

-- batches: the whole point is to be visible on a teacher's public
-- profile, but only the owning teacher can create/edit/delete their own.
create policy "batches are publicly readable" on batches for select using (true);
create policy "teachers manage their own batches" on batches for all using (auth.uid() = teacher_id) with check (auth.uid() = teacher_id);

-- batch_students: visible to the teacher who owns the batch and to the
-- student placed in it; only the owning teacher can add or remove a student.
create policy "batch roster visible to teacher or student" on batch_students for select using (
  student_id = auth.uid() or exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
);
create policy "teachers add students to their own batches" on batch_students for insert with check (
  exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
);
create policy "teachers remove students from their own batches" on batch_students for delete using (
  exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
);
-- lets a student see who else (their classmates) is in a batch they're
-- themselves a member of — needed for the student-side Batches tab.
-- Routed through a SECURITY DEFINER function rather than a plain
-- subquery: a policy on batch_students that queries batch_students
-- directly re-triggers the same policy for every row it looks at,
-- causing infinite recursion (Postgres error 42P17). Running the check
-- as the function's owner bypasses RLS for just that inner lookup and
-- breaks the loop.
create or replace function public.is_batchmate(target_batch_id bigint)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists(
    select 1 from batch_students
    where batch_id = target_batch_id and student_id = auth.uid()
  );
$$;
create policy "students can view classmates in their own batches" on batch_students for select using (
  is_batchmate(batch_id)
);

-- trial_requests: visible to the student who asked and the teacher who
-- received it. A student can only ever create a request as themselves;
-- only the teacher on the request can update its status (approve/decline).
create policy "trial request visible to student or teacher" on trial_requests for select using (auth.uid() = student_id or auth.uid() = teacher_id);
create policy "students can request a trial" on trial_requests for insert with check (auth.uid() = student_id);
create policy "teacher can respond to a trial request" on trial_requests for update using (auth.uid() = teacher_id);

-- attendance: visible to the teacher who owns the batch and to the
-- student it's about; only the owning teacher can mark or change it.
create policy "attendance visible to teacher or student" on attendance for select using (
  student_id = auth.uid() or exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
);
create policy "teachers mark attendance for their own batches" on attendance for insert with check (
  exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
);
create policy "teachers update attendance for their own batches" on attendance for update using (
  exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
);

-- notifications: a student only ever sees their own; only the teacher on
-- the notification can create it; a student can update it themselves
-- (used to mark it read).
create policy "notifications visible to the student" on notifications for select using (auth.uid() = student_id);
create policy "teachers can notify their own students" on notifications for insert with check (auth.uid() = teacher_id);
-- lets the admin panel's Broadcast tab send an announcement straight to
-- any student, without it belonging to any particular teacher.
create policy "admins can notify any student" on notifications for insert with check (is_admin());
create policy "students can mark their notifications read" on notifications for update using (auth.uid() = student_id) with check (auth.uid() = student_id);

-- teacher_notifications: a teacher only ever sees their own; a student can
-- create one about themselves (new enrollment, new enquiry, fee marked
-- paid), an admin can create one for a broadcast, and the teacher can mark
-- their own notifications read.
create policy "teacher_notifications visible to the teacher" on teacher_notifications for select using (auth.uid() = teacher_id);
create policy "students can notify their own teacher" on teacher_notifications for insert with check (auth.uid() = student_id);
create policy "admins can notify any teacher" on teacher_notifications for insert with check (is_admin());
create policy "teachers can mark their notifications read" on teacher_notifications for update using (auth.uid() = teacher_id) with check (auth.uid() = teacher_id);

-- assessments: visible to the owning teacher and to any student in that
-- batch; only the owning teacher can create one.
create policy "assessment visible to teacher or batch students" on assessments for select using (
  auth.uid() = teacher_id or exists(select 1 from batch_students bs where bs.batch_id = assessments.batch_id and bs.student_id = auth.uid())
);
create policy "teachers create assessments for their own batches" on assessments for insert with check (
  auth.uid() = teacher_id and exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
);

-- assessment_marks: a student sees only their own row; the owning teacher
-- sees every row for their own assessments; only that teacher can insert.
create policy "marks visible to teacher or the student" on assessment_marks for select using (
  student_id = auth.uid() or exists(select 1 from assessments a where a.id = assessment_id and a.teacher_id = auth.uid())
);
create policy "teachers record marks for their own assessments" on assessment_marks for insert with check (
  exists(select 1 from assessments a where a.id = assessment_id and a.teacher_id = auth.uid())
);

-- ---------------------------------------------------------------
-- Realtime: stream new/updated `trial_requests` rows, so a teacher sees a
-- new trial request appear the instant a student sends one, and a student
-- sees the approve/decline the instant their teacher responds — both
-- without refreshing. Also stream new `notifications` rows, so a
-- student's Notifications tab (and its unread badge) updates the instant
-- a teacher approves/declines a trial or sends a batch announcement.
-- ---------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trial_requests'
  ) then
    alter publication supabase_realtime add table trial_requests;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table notifications;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'teacher_notifications'
  ) then
    alter publication supabase_realtime add table teacher_notifications;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'assessment_marks'
  ) then
    alter publication supabase_realtime add table assessment_marks;
  end if;
end $$;

-- ---------------------------------------------------------------
-- Keep teacher_profiles.rating / .reviews as a live average instead of a
-- fixed default, so every teacher starts with no rating shown until real
-- reviews come in, and the number updates the moment a review is added,
-- changed, or removed.
-- ---------------------------------------------------------------
create or replace function update_teacher_rating() returns trigger as $$
declare
  affected_teacher uuid := coalesce(new.teacher_id, old.teacher_id);
begin
  update teacher_profiles
  set rating = coalesce((select round(avg(rating)::numeric, 1) from reviews where teacher_id = affected_teacher), 0),
      reviews = (select count(*) from reviews where teacher_id = affected_teacher)
  where profile_id = affected_teacher;
  return null;
end;
$$ language plpgsql security definer;

create trigger reviews_after_change
after insert or update or delete on reviews
for each row execute function update_teacher_rating();

-- ---------------------------------------------------------------
-- Persists the "Seen" marker in chat: marks every not-yet-read message
-- FROM other_id TO the caller as read. security definer so it can write
-- read_at without a broad UPDATE policy on messages — this function is
-- the *only* way read_at ever gets set, and it only ever marks the
-- *other* participant's messages as read, never the caller's own, so
-- neither side can fake a "Seen" that didn't happen. The app calls this
-- the moment a thread is opened, and again the instant a new message
-- arrives while it's already open.
-- ---------------------------------------------------------------
create or replace function mark_messages_read(other_id uuid) returns void as $$
  update messages
  set read_at = now()
  where read_at is null
    and sender_id = other_id
    and (
      (teacher_id = auth.uid() and student_id = other_id)
      or (student_id = auth.uid() and teacher_id = other_id)
    );
$$ language sql security definer;

grant execute on function mark_messages_read(uuid) to authenticated;

-- ---------------------------------------------------------------
-- MIGRATION for projects that already ran the old version of this file
-- (fixes teachers who show 5★ by default with 0 reviews, and adds the
-- new maps_link column + reviews table). Safe to re-run.
-- ---------------------------------------------------------------
-- alter table teacher_profiles add column if not exists maps_link text default '';
-- alter table teacher_profiles alter column rating set default 0;
-- update teacher_profiles set rating = 0 where reviews = 0;

-- ---------------------------------------------------------------
-- MIGRATION: replaces the old manual "distance" text field with real
-- coordinates, so a student's own location can be used to calculate an
-- automatic, live distance to each teacher instead of a note the teacher
-- typed in by hand. Safe to re-run.
-- ---------------------------------------------------------------
-- alter table teacher_profiles add column if not exists lat double precision;
-- alter table teacher_profiles add column if not exists lng double precision;
-- alter table teacher_profiles drop column if exists distance;

-- ---------------------------------------------------------------
-- MIGRATION: adds the 'admin' role and the ability for an admin to delete
-- any teacher/student profile (for the admin panel). Safe to re-run.
-- ---------------------------------------------------------------
-- alter table profiles drop constraint if exists profiles_role_check;
-- alter table profiles add constraint profiles_role_check check (role in ('student','teacher','admin'));
--
-- create or replace function is_admin() returns boolean as $$
--   select exists(select 1 from profiles where id = auth.uid() and role = 'admin');
-- $$ language sql security definer stable;
--
-- drop policy if exists "admins can delete any profile" on profiles;
-- create policy "admins can delete any profile" on profiles for delete using (is_admin());

-- ---------------------------------------------------------------
-- MIGRATION: adds realtime chat between a student and a teacher (the
-- `messages` table, its RLS policies, and turning on Realtime for it).
-- Safe to re-run.
-- ---------------------------------------------------------------
-- create table if not exists messages (
--   id bigserial primary key,
--   teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
--   student_id uuid not null references profiles(id) on delete cascade,
--   sender_id uuid not null references profiles(id) on delete cascade,
--   body text not null,
--   created_at timestamptz not null default now()
-- );
-- alter table messages enable row level security;
-- drop policy if exists "messages visible to the two participants" on messages;
-- create policy "messages visible to the two participants" on messages for select using (auth.uid() = teacher_id or auth.uid() = student_id);
-- drop policy if exists "participants can send messages" on messages;
-- create policy "participants can send messages" on messages for insert with check (
--   auth.uid() = sender_id and (auth.uid() = teacher_id or auth.uid() = student_id)
-- );
-- do $$
-- begin
--   if not exists (
--     select 1 from pg_publication_tables
--     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'
--   ) then
--     alter publication supabase_realtime add table messages;
--   end if;
-- end $$;

-- ---------------------------------------------------------------
-- MIGRATION: adds typing indicators and online/last-seen status to chat
-- (just one column — "online" itself is Realtime Presence, which needs
-- no schema; typing indicators are Realtime Broadcast, which needs no
-- schema either). Safe to re-run.
-- ---------------------------------------------------------------
-- alter table profiles add column if not exists last_seen_at timestamptz;

-- ---------------------------------------------------------------
-- MIGRATION: lets a chat message quote an earlier one in the same
-- thread. messages.id is a bigint (auto-incrementing), not a uuid, so
-- the reference column has to match. Safe to re-run.
-- ---------------------------------------------------------------
-- alter table messages add column if not exists reply_to bigint references messages(id) on delete set null;

-- ---------------------------------------------------------------
-- MIGRATION: persists the chat "Seen" marker so it survives a refresh,
-- instead of the old Broadcast-only ping that forgot everything the
-- moment either side reloaded. Safe to re-run.
-- ---------------------------------------------------------------
-- alter table messages add column if not exists read_at timestamptz;
--
-- create or replace function mark_messages_read(other_id uuid) returns void as $$
--   update messages
--   set read_at = now()
--   where read_at is null
--     and sender_id = other_id
--     and (
--       (teacher_id = auth.uid() and student_id = other_id)
--       or (student_id = auth.uid() and teacher_id = other_id)
--     );
-- $$ language sql security definer;
--
-- grant execute on function mark_messages_read(uuid) to authenticated;

-- ---------------------------------------------------------------
-- MIGRATION: adds site-wide maintenance mode (the site_settings table,
-- its RLS policies, and turning on Realtime for it) plus the admin
-- policies the Analytics tab needs to total up enrollments, payments,
-- enquiries, and to moderate (delete) reviews. Safe to re-run.
-- ---------------------------------------------------------------
-- create table if not exists site_settings (
--   key text primary key,
--   value jsonb not null default '{}'::jsonb,
--   updated_at timestamptz not null default now()
-- );
-- insert into site_settings (key, value) values ('maintenance', jsonb_build_object('enabled', false))
--   on conflict (key) do nothing;
-- alter table site_settings enable row level security;
-- drop policy if exists "site settings are publicly readable" on site_settings;
-- create policy "site settings are publicly readable" on site_settings for select using (true);
-- drop policy if exists "admins can change site settings" on site_settings;
-- create policy "admins can change site settings" on site_settings for all using (is_admin()) with check (is_admin());
-- do $$
-- begin
--   if not exists (
--     select 1 from pg_publication_tables
--     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'site_settings'
--   ) then
--     alter publication supabase_realtime add table site_settings;
--   end if;
-- end $$;
--
-- drop policy if exists "admins can view all enrollments" on enrollments;
-- create policy "admins can view all enrollments" on enrollments for select using (is_admin());
-- drop policy if exists "admins can view all payments" on payments;
-- create policy "admins can view all payments" on payments for select using (is_admin());
-- drop policy if exists "admins can view all enquiries" on enquiries;
-- create policy "admins can view all enquiries" on enquiries for select using (is_admin());
-- drop policy if exists "admins can delete any review" on reviews;
-- create policy "admins can delete any review" on reviews for delete using (is_admin());

-- ---------------------------------------------------------------
-- MIGRATION: adds student grades, proper batches (grade/subject/days/time/
-- description, with a student roster), and the trial-class request system
-- (a student requests a spot, the teacher approves/declines, both sides
-- see it live). Safe to re-run.
-- ---------------------------------------------------------------
-- alter table profiles add column if not exists grade text;
--
-- create table if not exists batches (
--   id bigserial primary key,
--   teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
--   name text not null,
--   grade text default '',
--   subject text not null,
--   days text[] not null default '{}',
--   time text default '',
--   description text default '',
--   capacity int,
--   status text not null default 'active' check (status in ('active','inactive')),
--   created_at timestamptz not null default now()
-- );
-- alter table batches enable row level security;
-- drop policy if exists "batches are publicly readable" on batches;
-- create policy "batches are publicly readable" on batches for select using (true);
-- drop policy if exists "teachers manage their own batches" on batches;
-- create policy "teachers manage their own batches" on batches for all using (auth.uid() = teacher_id) with check (auth.uid() = teacher_id);
--
-- create table if not exists batch_students (
--   id bigserial primary key,
--   batch_id bigint not null references batches(id) on delete cascade,
--   student_id uuid not null references profiles(id) on delete cascade,
--   added_at timestamptz not null default now(),
--   unique(batch_id, student_id)
-- );
-- alter table batch_students enable row level security;
-- drop policy if exists "batch roster visible to teacher or student" on batch_students;
-- create policy "batch roster visible to teacher or student" on batch_students for select using (
--   student_id = auth.uid() or exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
-- );
-- drop policy if exists "teachers add students to their own batches" on batch_students;
-- create policy "teachers add students to their own batches" on batch_students for insert with check (
--   exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
-- );
-- drop policy if exists "teachers remove students from their own batches" on batch_students;
-- create policy "teachers remove students from their own batches" on batch_students for delete using (
--   exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
-- );
--
-- create table if not exists trial_requests (
--   id bigserial primary key,
--   batch_id bigint not null references batches(id) on delete cascade,
--   teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
--   student_id uuid not null references profiles(id) on delete cascade,
--   note text default '',
--   status text not null default 'pending' check (status in ('pending','approved','declined')),
--   created_at timestamptz not null default now(),
--   responded_at timestamptz
-- );
-- alter table trial_requests enable row level security;
-- drop policy if exists "trial request visible to student or teacher" on trial_requests;
-- create policy "trial request visible to student or teacher" on trial_requests for select using (auth.uid() = student_id or auth.uid() = teacher_id);
-- drop policy if exists "students can request a trial" on trial_requests;
-- create policy "students can request a trial" on trial_requests for insert with check (auth.uid() = student_id);
-- drop policy if exists "teacher can respond to a trial request" on trial_requests;
-- create policy "teacher can respond to a trial request" on trial_requests for update using (auth.uid() = teacher_id);
-- do $$
-- begin
--   if not exists (
--     select 1 from pg_publication_tables
--     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'trial_requests'
--   ) then
--     alter publication supabase_realtime add table trial_requests;
--   end if;
-- end $$;

-- ---------------------------------------------------------------
-- MIGRATION: adds student stream (for grade 11/12), a teacher's response
-- message on a trial request, per-batch attendance, and a notifications
-- system (trial approved/declined with the teacher's message, plus batch
-- timing-change/cancellation announcements) — streamed live via
-- Realtime. Safe to re-run.
-- ---------------------------------------------------------------
-- alter table profiles add column if not exists stream text;
-- alter table batches add column if not exists stream text default '';
-- alter table trial_requests add column if not exists response_message text default '';
--
-- create table if not exists attendance (
--   id bigserial primary key,
--   batch_id bigint not null references batches(id) on delete cascade,
--   student_id uuid not null references profiles(id) on delete cascade,
--   date date not null default current_date,
--   status text not null default 'present' check (status in ('present','absent','late')),
--   marked_at timestamptz not null default now(),
--   unique(batch_id, student_id, date)
-- );
-- alter table attendance enable row level security;
-- drop policy if exists "attendance visible to teacher or student" on attendance;
-- create policy "attendance visible to teacher or student" on attendance for select using (
--   student_id = auth.uid() or exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
-- );
-- drop policy if exists "teachers mark attendance for their own batches" on attendance;
-- create policy "teachers mark attendance for their own batches" on attendance for insert with check (
--   exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
-- );
-- drop policy if exists "teachers update attendance for their own batches" on attendance;
-- create policy "teachers update attendance for their own batches" on attendance for update using (
--   exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
-- );
--
-- create table if not exists notifications (
--   id bigserial primary key,
--   student_id uuid not null references profiles(id) on delete cascade,
--   teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
--   batch_id bigint references batches(id) on delete set null,
--   type text not null default 'general' check (type in ('trial_approved','trial_declined','batch_update','batch_cancelled','general')),
--   title text not null,
--   message text default '',
--   read_at timestamptz,
--   created_at timestamptz not null default now()
-- );
-- alter table notifications enable row level security;
-- drop policy if exists "notifications visible to the student" on notifications;
-- create policy "notifications visible to the student" on notifications for select using (auth.uid() = student_id);
-- drop policy if exists "teachers can notify their own students" on notifications;
-- create policy "teachers can notify their own students" on notifications for insert with check (auth.uid() = teacher_id);
-- drop policy if exists "students can mark their notifications read" on notifications;
-- create policy "students can mark their notifications read" on notifications for update using (auth.uid() = student_id) with check (auth.uid() = student_id);
-- do $$
-- begin
--   if not exists (
--     select 1 from pg_publication_tables
--     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'notifications'
--   ) then
--     alter publication supabase_realtime add table notifications;
--   end if;
-- end $$;

-- ---------------------------------------------------------------
-- MIGRATION (Part 15): assessments + per-student marks, a batch's current
-- topic/next class date, classmates visibility in batch_students, two
-- more notification types (fee_reminder, assessment), and a unique
-- constraint on enrollments so a student can't enroll twice in the same
-- subject with the same teacher. Safe to re-run EXCEPT the unique
-- constraint line, which will fail if you already have duplicate
-- enrollments — see the note right above it for how to clean those up
-- first.
-- ---------------------------------------------------------------
-- alter table batches add column if not exists current_topic text default '';
-- alter table batches add column if not exists next_class_date date;
--
-- alter table notifications drop constraint if exists notifications_type_check;
-- alter table notifications add constraint notifications_type_check
--   check (type in ('trial_approved','trial_declined','batch_update','batch_cancelled','fee_reminder','assessment','general'));
--
-- -- Run this SELECT first if you're not sure whether you have duplicates:
-- --   select student_id, teacher_id, subject, count(*) from enrollments
-- --   group by 1,2,3 having count(*) > 1;
-- -- If it returns rows, delete the extra ones (keeping whichever id you
-- -- want to keep per group) before running the next line.
-- do $$
-- begin
--   if not exists (select 1 from pg_constraint where conname = 'enrollments_student_teacher_subject_unique') then
--     alter table enrollments add constraint enrollments_student_teacher_subject_unique
--       unique (student_id, teacher_id, subject);
--   end if;
-- end $$;
--
-- create table if not exists assessments (
--   id bigserial primary key,
--   batch_id bigint not null references batches(id) on delete cascade,
--   teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
--   subject text not null,
--   title text not null,
--   max_marks int not null default 100,
--   created_at timestamptz not null default now()
-- );
-- alter table assessments enable row level security;
-- drop policy if exists "assessment visible to teacher or batch students" on assessments;
-- create policy "assessment visible to teacher or batch students" on assessments for select using (
--   auth.uid() = teacher_id or exists(select 1 from batch_students bs where bs.batch_id = assessments.batch_id and bs.student_id = auth.uid())
-- );
-- drop policy if exists "teachers create assessments for their own batches" on assessments;
-- create policy "teachers create assessments for their own batches" on assessments for insert with check (
--   auth.uid() = teacher_id and exists(select 1 from batches b where b.id = batch_id and b.teacher_id = auth.uid())
-- );
--
-- create table if not exists assessment_marks (
--   id bigserial primary key,
--   assessment_id bigint not null references assessments(id) on delete cascade,
--   student_id uuid not null references profiles(id) on delete cascade,
--   marks numeric not null,
--   remarks text default '',
--   created_at timestamptz not null default now(),
--   unique(assessment_id, student_id)
-- );
-- alter table assessment_marks enable row level security;
-- drop policy if exists "marks visible to teacher or the student" on assessment_marks;
-- create policy "marks visible to teacher or the student" on assessment_marks for select using (
--   student_id = auth.uid() or exists(select 1 from assessments a where a.id = assessment_id and a.teacher_id = auth.uid())
-- );
-- drop policy if exists "teachers record marks for their own assessments" on assessment_marks;
-- create policy "teachers record marks for their own assessments" on assessment_marks for insert with check (
--   exists(select 1 from assessments a where a.id = assessment_id and a.teacher_id = auth.uid())
-- );
--
-- drop policy if exists "students can view classmates in their own batches" on batch_students;
-- create or replace function public.is_batchmate(target_batch_id bigint)
-- returns boolean
-- language sql
-- security definer
-- set search_path = public
-- stable
-- as $$
--   select exists(
--     select 1 from batch_students
--     where batch_id = target_batch_id and student_id = auth.uid()
--   );
-- $$;
-- create policy "students can view classmates in their own batches" on batch_students for select using (
--   is_batchmate(batch_id)
-- );
--
-- do $$
-- begin
--   if not exists (
--     select 1 from pg_publication_tables
--     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'assessment_marks'
--   ) then
--     alter publication supabase_realtime add table assessment_marks;
--   end if;
-- end $$;

-- ---------------------------------------------------------------
-- MIGRATION (Part 16): site_logs, a persistent error log an admin can
-- read from the Diagnostics tab. Safe to re-run.
-- ---------------------------------------------------------------
-- create table if not exists site_logs (
--   id bigserial primary key,
--   level text not null default 'error' check (level in ('error','warn','info')),
--   context text not null,
--   message text not null,
--   code text,
--   details text,
--   hint text,
--   user_id uuid references profiles(id) on delete set null,
--   user_role text,
--   created_at timestamptz not null default now()
-- );
-- alter table site_logs enable row level security;
-- drop policy if exists "anyone can report an error" on site_logs;
-- create policy "anyone can report an error" on site_logs for insert with check (true);
-- drop policy if exists "admins can view logs" on site_logs;
-- create policy "admins can view logs" on site_logs for select using (is_admin());
-- drop policy if exists "admins can clear logs" on site_logs;
-- create policy "admins can clear logs" on site_logs for delete using (is_admin());

-- ---------------------------------------------------------------
-- MIGRATION (Part 17): teacher-side notifications (fee received, new
-- enrollment, new enquiry), admin site-wide broadcasts, and recording the
-- enrollment date. Safe to re-run.
-- ---------------------------------------------------------------
-- alter table notifications alter column teacher_id drop not null;
-- alter table notifications drop constraint if exists notifications_type_check;
-- alter table notifications add constraint notifications_type_check
--   check (type in ('trial_approved','trial_declined','batch_update','batch_cancelled','fee_reminder','assessment','admin_broadcast','general'));
--
-- create table if not exists teacher_notifications (
--   id bigserial primary key,
--   teacher_id uuid not null references teacher_profiles(profile_id) on delete cascade,
--   student_id uuid references profiles(id) on delete set null,
--   enrollment_id bigint references enrollments(id) on delete set null,
--   type text not null default 'general' check (type in ('new_enrollment','new_enquiry','fee_paid','admin_broadcast','general')),
--   title text not null,
--   message text default '',
--   read_at timestamptz,
--   created_at timestamptz not null default now()
-- );
-- alter table teacher_notifications enable row level security;
-- drop policy if exists "teacher_notifications visible to the teacher" on teacher_notifications;
-- create policy "teacher_notifications visible to the teacher" on teacher_notifications for select using (auth.uid() = teacher_id);
-- drop policy if exists "students can notify their own teacher" on teacher_notifications;
-- create policy "students can notify their own teacher" on teacher_notifications for insert with check (auth.uid() = student_id);
-- drop policy if exists "admins can notify any teacher" on teacher_notifications;
-- create policy "admins can notify any teacher" on teacher_notifications for insert with check (is_admin());
-- drop policy if exists "teachers can mark their notifications read" on teacher_notifications;
-- create policy "teachers can mark their notifications read" on teacher_notifications for update using (auth.uid() = teacher_id) with check (auth.uid() = teacher_id);
--
-- drop policy if exists "admins can notify any student" on notifications;
-- create policy "admins can notify any student" on notifications for insert with check (is_admin());
--
-- do $$
-- begin
--   if not exists (
--     select 1 from pg_publication_tables
--     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'teacher_notifications'
--   ) then
--     alter publication supabase_realtime add table teacher_notifications;
--   end if;
-- end $$;
--
-- (enrollments.created_at already exists from the original schema — every
-- enrollment has always had its date recorded; this update just surfaces
-- it in the UI, so no column change is needed for that part.)

-- ---------------------------------------------------------------
-- email_exists: lets the "Forgot password" screen tell someone whether
-- an email is registered *before* trying to send a reset code, so it can
-- show "no account found — sign up" instead of silently sending nothing.
--
-- NOTE ON TRADE-OFF: Supabase's own auth methods deliberately don't
-- reveal whether an email is registered (this prevents "user
-- enumeration" — someone scripting a list of emails against your app to
-- find out who has an account). This function intentionally gives that
-- protection up in exchange for a clearer "forgot password" experience.
-- It only ever returns true/false, never any of the account's actual
-- data, which limits — but doesn't eliminate — that exposure.
--
-- security definer: runs as the function's owner rather than the
-- calling user, which is what lets it read auth.users — a table the
-- anon/authenticated keys can never query directly on their own.
-- Safe to re-run.
-- ---------------------------------------------------------------
create or replace function email_exists(check_email text) returns boolean as $$
  select exists(select 1 from auth.users where lower(email) = lower(check_email));
$$ language sql security definer stable;

grant execute on function email_exists(text) to anon, authenticated;
