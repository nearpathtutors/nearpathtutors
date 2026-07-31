-- NearPath Tutors — database schema for Supabase
-- Run this once in your Supabase project's SQL Editor (see README.md).

-- 1) profiles: one row per signed-up user (student, teacher, or admin)
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('student','teacher','admin')),
  full_name text not null,
  created_at timestamptz not null default now()
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
  created_at timestamptz not null default now()
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

-- ---------------------------------------------------------------
-- Row Level Security: lock every table down, then open specific,
-- narrow policies. Without this, the anon key can read/write anything.
-- ---------------------------------------------------------------
alter table profiles enable row level security;
alter table teacher_profiles enable row level security;
alter table schedule_slots enable row level security;
alter table enquiries enable row level security;
alter table enrollments enable row level security;
alter table payments enable row level security;
alter table reviews enable row level security;

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
