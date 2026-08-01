# NearPath Tutors

A directory site for local tutors, coaches, and skill teachers — with real
accounts, real login, and real data for both parents/students and teachers.

## How it's structured

- `index.html` — the whole site: layout, styling, and app logic.
- `schema.sql` — the database structure to run once in Supabase.
- No other files. Teacher listings, student accounts, enrollments, and
  payments all live in your Supabase database, not in this repo.

The site is 100% static (just HTML/CSS/JS), so it can be hosted for free on
GitHub Pages. GitHub Pages can't run a server or a database itself — that's
what Supabase is for. Supabase gives you a hosted Postgres database plus a
login/signup system, and the site talks to it directly from the browser.

---

## Part 1 — Create your Supabase project

1. Go to **[supabase.com](https://supabase.com)** and sign up (free — GitHub
   login is the fastest option).
2. Click **New Project**. Pick any name and a database password (save that
   password somewhere — you likely won't need it again, but keep it).
   Choose the region closest to your users.
3. Wait ~2 minutes for the project to finish provisioning.

## Part 2 — Create the database tables

1. In your project, open the **SQL Editor** (left sidebar).
2. Click **New query**.
3. Open `schema.sql` from this folder, copy its entire contents, paste it
   into the editor, and click **Run**.
4. You should see "Success. No rows returned." That created 8 tables:
   `profiles`, `teacher_profiles`, `schedule_slots`, `enquiries`,
   `enrollments`, `payments`, `reviews`, `messages` — plus security rules
   so users can only see and edit their own data, a trigger that
   automatically recalculates a teacher's average rating whenever a review
   is added, edited, or removed, and Realtime turned on for `messages` so
   chat replies appear instantly on both sides.

### Already ran an older version of schema.sql?

If your project was set up before this update, run this once in the SQL
Editor to add what's new (the `reviews` table, the `maps_link` column, and
a fix so new teachers no longer show a fake 5-star rating) without losing
any existing data:

```sql
alter table teacher_profiles add column if not exists maps_link text default '';
alter table teacher_profiles alter column rating set default 0;
update teacher_profiles set rating = 0 where reviews = 0;
```

Then re-run the rest of `schema.sql` from the `-- 7) reviews` section
onward (the `create table reviews`, its RLS policies, and the trigger) —
those use `create table`/`create policy` without `if not exists`, so only
paste that portion if you haven't already created it.

If your project predates the automatic-distance feature (teachers used to
type in a distance note by hand), also run:

```sql
alter table teacher_profiles add column if not exists lat double precision;
alter table teacher_profiles add column if not exists lng double precision;
alter table teacher_profiles drop column if exists distance;
```

If your project predates realtime chat, run the migration block near the
bottom of `schema.sql` (labelled "adds realtime chat between a student and
a teacher") — it's commented out by default, so paste just that section
into the SQL Editor. See Part 11 below for what this adds and how to
verify it's turned on.

## Part 3 — Turn off email confirmation (recommended while testing)

By default Supabase requires users to click a confirmation link before they
can log in. That's good for production, but slows down testing.

1. Go to **Authentication → Providers → Email** (or **Authentication →
   Settings**, depending on the Supabase version).
2. Turn **off** "Confirm email".
3. Save.

You can turn this back on later before you launch for real — just know that
if it's on, new users must click a link in their email before their first
login works.

## Part 4 — Connect the site to your project

1. In Supabase, go to **Project Settings → API**.
2. Copy the **Project URL** and the **anon public** key.
3. Open `index.html` in a text editor. Near the top, find:
   ```js
   const SUPABASE_URL = 'YOUR_SUPABASE_URL';
   const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
   ```
4. Replace both placeholder strings with the values you copied.

The anon key is not a secret — it's designed to sit in public frontend
code. What keeps your data safe is the row-level security policies in
`schema.sql`, which restrict who can read/write each row at the database
level, no matter who calls the API.

## Part 5 — Test it locally

Opening `index.html` by double-clicking it (`file://...`) will not work —
run a local server instead:

```
python3 -m http.server 8000
```

Then open `http://localhost:8000/index.html`. Try:
- Registering as a teacher, filling in your profile (Teacher portal →
  Dashboard → Profile).
- Switching to the Parents portal, registering as a student, browsing
  teachers, enrolling, and sending an enquiry.
- Refreshing the page — you should stay logged in (Supabase keeps the
  session in the browser).

## Part 6 — Host it on GitHub Pages

1. Create a new GitHub repo (e.g. `nearpath-tutors`), public.
2. Upload `index.html` (with your real Supabase URL/key already filled in)
   and this `README.md`.
3. Go to **Settings → Pages**.
4. Under "Build and deployment": **Source: Deploy from a branch**, branch
   `main`, folder `/ (root)`. Save.
5. After a minute you'll get a URL like
   `https://<your-username>.github.io/nearpath-tutors/` — that's your live,
   working site.

## Part 7 — Set up the admin account

The site has an admin panel (click the 🛡️ icon in the top nav) for viewing
and removing any teacher or student profile. It's protected by a real
Supabase login, not just a password check in the page's JavaScript — so it
needs a one-time setup:

1. In Supabase, go to **Authentication → Users → Add user**.
   - Email: `nearpathtutors@gmail.com` (this must match exactly — it's
     the fixed email hardcoded into `index.html` as `ADMIN_EMAIL`, near the
     top of the file next to `SUPABASE_URL`. You can change it to any email
     you like in both places, as long as they match.)
   - Password: `123456` (or whatever you'd prefer — this is the real
     password Supabase checks, so feel free to make it stronger).
   - Tick **Auto Confirm User** (or equivalent) so it doesn't need an email
     confirmation click.
2. Copy the new user's **UID** from the Users list.
3. In the **SQL Editor**, run (replacing `<uid>` with what you copied):
   ```sql
   insert into profiles (id, role, full_name) values ('<uid>', 'admin', 'Admin');
   ```
4. That's it. Go to the site, click the 🛡️ icon, and log in with username
   `admin` and the password you set in step 1.

If your project was set up before this feature existed, first run the new
migration block at the bottom of `schema.sql` (adds the `admin` role and
the delete permission it needs) — it's commented out by default, so paste
just that section into the SQL Editor and run it.

**Why a password field in the HTML isn't a real lock:** anyone can view the
source of a static site, so a password checked only in JavaScript could be
read straight out of the page and bypassed entirely — including the actual
delete calls, since the Supabase anon key is public by design (see Part 4).
To make deletion genuinely restricted to you, the admin login instead signs
in as a real Supabase account, and the database itself only allows deletes
from a signed-in user whose `profiles.role` is `'admin'` (see the
`is_admin()` policy in `schema.sql`). The username/password box is a
friendly front end for that; the actual security lives in Supabase and the
database, not in `index.html`.

## Part 8 — Deploy the "delete user" Edge Function

Removing someone from the admin panel used to only delete their `profiles`
row (and everything tied to it) — it left their actual login sitting in
Supabase's Auth system, unable to be used again on the site, but not
actually gone. This step makes "Remove" delete the login too.

This has to run on Supabase's servers, not in `index.html`, because it
needs the **service role key** — a secret that can bypass every security
rule in your database. That key must never be placed in frontend code
(unlike the anon key, which is safe to expose — see Part 4). A Supabase
Edge Function is a small piece of server-side code that keeps that key
private and only exposes one narrow action: "delete this one user, but
only if the person asking is a signed-in admin."

The function's code is in `supabase/functions/admin-delete-user/index.ts`
in this folder. It doesn't need `SUPABASE_URL`, the anon key, or the
service role key pasted into it — Supabase provides all three
automatically to every Edge Function.

**Easiest way — from the Supabase dashboard, no install needed:**

1. In your Supabase project, open **Edge Functions** in the left sidebar.
2. Click **Create a new function**, name it exactly `admin-delete-user`.
3. Delete the placeholder code it gives you, then open
   `supabase/functions/admin-delete-user/index.ts` from this folder, copy
   its entire contents, and paste them in.
4. Click **Deploy**.

**Alternative — Supabase CLI**, if you already have it installed:

```
supabase functions deploy admin-delete-user --project-ref <your-project-ref>
```

(Your project ref is the random string in your project's URL, e.g.
`abcdefghijklmnop` in `https://abcdefghijklmnop.supabase.co`.)

That's it — no other setup. Test it by removing a test account from the
admin panel, then checking **Authentication → Users** in Supabase to
confirm they're gone from there too, not just from the tables.

## Part 9 — Turn on "Forgot password"

The login screens now have a **Forgot password?** link. A parent/student or
teacher who forgets their password can enter their email, get a 6-digit
code by email, and type that code plus a new password into the site — no
extra page or email link to click through. If the email they enter isn't
registered at all, the site tells them so directly and offers a "Create an
account" link instead of sending anything. This needs two changes in your
Supabase project before it will work as described.

1. Go to **Authentication → Emails** (older Supabase versions: **Authentication
   → Email Templates**) in your project.
2. Open the **Reset Password** template.
3. By default this template only contains a `{{ .ConfirmationURL }}` link.
   Add `{{ .Token }}` somewhere in the body — that's the 6-digit code the
   site's "Enter your code" screen asks for. For example, add a line like:
   ```
   Your NearPath Tutors password reset code is: {{ .Token }}
   ```
   You can leave the existing link in place too, or remove it — the site
   only uses the code, not the link.
4. Save the template.
5. Make sure you've run the `email_exists()` function from `schema.sql`
   (it's near the bottom, in the same migration block style as the other
   `create or replace function` statements) — that's what the site uses
   to check whether an email is registered before sending a code.

That's it — no redirect URL or Site URL configuration is needed for this,
since the code-entry flow never sends anyone through a link.

**A note on the trade-off here:** most apps, including Supabase's own
`resetPasswordForEmail()` by default, deliberately *don't* reveal whether
an email is registered — always showing the same generic "if that email
has an account, a code is on its way" message. That's to stop someone
from scripting a list of emails against your site to find out exactly who
has an account (this is called "user/email enumeration"). This app gives
up that protection on purpose, in exchange for a clearer message when
someone genuinely just typed the wrong email. If you'd rather keep the
generic, more private message instead, that's a one-function change to
undo (skip calling `email_exists()` and go straight to
`resetPasswordForEmail()`).

**A note on email sending while testing:** Supabase's built-in email
sender (the one used automatically, with no setup) is fine for trying this
out, but it's rate-limited to a handful of emails per hour, which you'll
hit fast if you're testing repeatedly. For real use, go to **Project
Settings → Auth → SMTP Settings** and connect your own SMTP provider (e.g.
Gmail, Resend, SendGrid) — the same place you'd set this up for any other
Supabase auth email.

## Part 10 — Turn on "Continue with Google"

Both login/signup screens (Parent/Student portal and Teacher portal) now
have a **Continue with Google** button above the email/password fields.
Clicking it sends the person to Google's own sign-in screen, then back to
your site already logged in — no password to set or remember. This needs
one-time setup in two places: Google Cloud Console (to get credentials)
and Supabase (to use them).

### 10a — Create a Google OAuth Client

1. Go to **[console.cloud.google.com](https://console.cloud.google.com)**
   and sign in with any Google account.
2. Create a new project (top-left project dropdown → **New Project**) —
   any name is fine, e.g. "NearPath Tutors".
3. Go to **APIs & Services → OAuth consent screen**.
   - User type: **External**. Click **Create**.
   - Fill in an app name (e.g. "NearPath Tutors"), your email as the
     support email, and your email again under developer contact info.
     Save and continue through the Scopes and Test users steps without
     changing anything (defaults are fine) until you reach the summary.
   - While your app is in "Testing" mode, only email addresses you've
     added as test users can log in with it. Go to **Audience** in the left
     sidebar and click **Publish App** to make it work for anyone — for a
     directory site like this, that's what you want.
4. Go to **APIs & Services → Credentials**.
5. Click **Create Credentials → OAuth client ID**.
   - Application type: **Web application**.
   - Name: anything, e.g. "NearPath Tutors web".
   - **Authorized JavaScript origins**: add the URL(s) you'll run the site
     from — e.g. `http://localhost:8000` while testing, and
     `https://<your-username>.github.io` once it's on GitHub Pages.
   - **Authorized redirect URIs**: this one has to come from Supabase —
     open a second tab, go to your Supabase project's **Authentication →
     Providers**, find **Google** in the list, and copy the **Callback URL
     (for OAuth)** shown there (it looks like
     `https://<your-project-ref>.supabase.co/auth/v1/callback`). Paste
     that single URL into this field back in Google Cloud Console.
   - Click **Create**. Google shows you a **Client ID** and **Client
     secret** — copy both (you can also re-open this credential later to
     see them again).

### 10b — Connect it in Supabase

1. In your Supabase project, go to **Authentication → Providers**.
2. Find **Google** in the list and toggle it **on**.
3. Paste the **Client ID** and **Client secret** from step 10a into the
   matching fields.
4. Save.

That's it — no code changes needed, since `index.html` already calls
Supabase's Google sign-in for you. Test it locally (Part 5): click
**Continue with Google** on either portal's login screen, and you should
land back on the site signed in.

**A note on new accounts created this way:** since Google doesn't ask
"are you a parent/student or a teacher?", the site remembers which button
you clicked (Parent/Student portal vs Teacher portal) and creates the
matching kind of account the first time that Google account signs in —
after that, the same Google account always logs back into whichever kind
of account it already has. A brand-new teacher signing in with Google is
dropped into the same one-time profile-setup screen as one who signed up
with a password.

## Part 11 — Realtime chat with a teacher

Every logged-in parent/student and teacher now has a persistent **💬
message widget** docked in the bottom-right corner of the screen, on
every page — not a full-screen popup. Collapsed, it's just a round
bubble (with an unread badge when something new has come in); tapping it
opens an **inbox** listing every conversation, and tapping a conversation
opens that thread. Replies from either side appear instantly, with no
page refresh.

- **The inbox starts empty** — "No messages yet" — until the person has
  either sent/received an enquiry, been enrolled, or exchanged an actual
  message with someone.
- **Sending an enquiry immediately adds that teacher to the student's
  inbox**, even before either side has typed a single chat message — it
  shows "Say hello 👋" until someone does.
- **From a teacher's public profile**, a logged-in parent/student can also
  tap **💬 Chat now** to jump straight into a thread with that teacher
  (prompted to log in first if needed, same as "Send enquiry").
- **From the teacher dashboard**, a **💬 Chat** / **💬 Reply in chat**
  button next to each entry in the **Students** and **Enquiries** tabs
  opens that specific thread directly.
- **From the student dashboard**, a **💬 Chat** button next to each entry
  under **My enrollments** does the same.
- The bubble/badge stay visible and stay live (via one Realtime
  subscription per session) no matter what page the person is browsing —
  they don't have to have a thread open to know a new message came in.

This runs on `schema.sql`'s new `messages` table plus Supabase's Realtime
feature — the site subscribes to that table, so a new message from either
side shows up live, no polling involved.

**If you ran the full, current `schema.sql`, this is already turned on** —
the `alter publication supabase_realtime add table messages;` line at the
bottom of the `messages` section does it for you. To double check, the
most reliable way is directly in the SQL Editor:

```sql
select * from pg_publication_tables where pubname = 'supabase_realtime';
```
`messages` should be in the results. If the `supabase_realtime`
publication doesn't exist yet on your project (some do, some don't, and
the Database → Replication page in the dashboard doesn't show it
consistently across Supabase versions), create it and add the table:

```sql
create publication supabase_realtime;
alter publication supabase_realtime add table messages;
```

**Typing indicators, seen markers, ping notifications, and online /
last-seen status** ride along on the same widget, all live via Supabase
Realtime, and need no publication setup:

- **Typing indicators** use Realtime *Broadcast* on a channel tied to
  your own account, so they show up wherever you're looking — the
  **inbox list** ("typing…" in orange, in place of the message preview)
  as well as inside an open thread — not just when you happen to have
  that exact conversation open. Nothing is written to the database.
- **Seen markers** ("Seen" under your last sent message, once the other
  person has opened that thread) also ride on Broadcast — a ping fires
  the moment someone opens a thread, and again if a new message arrives
  while they already have it open. This is intentionally lightweight —
  it only works while both people have been online at some point after
  the message was sent, nothing is persisted — which keeps it simple and
  needs no extra table.
- **Ping notifications** — an incoming message plays a short, synthesized
  "ping" sound (no audio file, generated in-browser) and, if you're not
  currently looking at that exact thread, a toast notification too.
- **Online status** uses Realtime *Presence* — every logged-in
  teacher/student tracks themselves on a shared channel the instant they
  load the site, so anyone can tell who's currently connected, on any
  page, in real time. This also needs no setup.
- **Last seen** is the one part that touches the database: a new
  `last_seen_at` column on `profiles`, stamped by the browser every ~45
  seconds while the tab is open and again whenever it's hidden. Presence
  alone can't answer "when were they last here" — it forgets someone
  instantly the moment they disconnect — so this column is what "Last
  seen 12m ago" is reading from once someone's no longer online. If your
  project predates this, run the migration for it near the bottom of
  `schema.sql` (`alter table profiles add column if not exists
  last_seen_at timestamptz;`).
- **Reply to a specific message** — hovering (or tapping, on mobile) a
  message reveals a small ↩ button. Tapping it shows a "Replying to…"
  preview above the input; sending attaches that reference, and the sent
  message shows a small quoted snippet of the original above its text.
  Tapping that quote scrolls back to and briefly highlights the original.
  This needs one new column on `messages`. `messages.id` is a `bigint`
  (auto-incrementing), not a `uuid`, so the reference column has to match:
  ```sql
  alter table messages add column if not exists reply_to bigint references messages(id) on delete set null;
  ```
  Run that once in the SQL Editor if your project predates this feature
  (new projects running the current `schema.sql` should add this line to
  the `messages` table's `create table` block instead of running it as a
  migration).

Like the other tables, RLS keeps a thread private to its two
participants — no one else can read or post into it, no matter how the
request is made.

---

## What's real now, and what isn't

**Real, and persisted in your database:**
- Sign up / log in / log out for both parents and teachers, with sessions
  that survive a page refresh.
- Teacher profiles (subjects, fee, bio, schedule, Google Maps link) —
  editable by the teacher, visible to everyone.
- Students enrolling with a teacher.
- Enquiries sent from a student to a teacher.
- Fee status ("Mark as paid") and payment history.
- Written reviews — a parent can rate and leave a comment for a teacher
  from their dashboard; the teacher's average rating and review count
  update automatically everywhere it's shown. New teachers show "New"
  instead of a rating until their first review comes in.
- A Google Maps button — teachers paste a Maps share link into their
  profile editor, and it appears as a button on their public profile for
  students to tap.
- Automatic distance — teachers no longer type in a distance note by
  hand. Instead, a teacher taps "Use my current location" once in their
  profile editor to save their teaching spot's coordinates, and a
  parent/student taps "Use my location" while browsing. From then on,
  every teacher card and profile shows a live distance ("1.2 km away")
  calculated in the browser — no maps API key or paid geocoding service
  needed. Both sides can decline or skip this; the app falls back to
  showing the teacher's typed location text instead.
- An admin panel (🛡️ icon in the nav) — view every teacher and student
  profile and permanently remove one, including everything tied to it
  *and* their actual login in Supabase Auth (requires the Edge Function
  in Part 8 to be deployed — without it, removal deletes their data but
  leaves their login behind). Gated by a real Supabase login, not just a
  page-level password check — see Part 7.
- Forgot password — a parent/student or teacher who forgets their
  password can request a 6-digit email code from the login screen and use
  it to set a new password, without leaving the site. Requires the email
  template change in Part 9.
- Continue with Google — a one-click alternative to email/password on
  both login/signup screens. Requires the Google Cloud + Supabase setup in
  Part 10.
- Realtime chat — a persistent 💬 message widget in the corner of the
  screen for every logged-in teacher or student, with an inbox of every
  conversation and instant delivery on both sides. See Part 11.

**Still a placeholder, by design (per your last answer):**
- "Mark as paid" records that a payment happened — it does not move real
  money. Wiring up an actual payment gateway (e.g. Razorpay or Stripe) is a
  separate step for later, and needs a small server-side function (Supabase
  Edge Functions work well for this) since payment secrets can't live in
  frontend code.

**Not built yet, could be added later:**
- Fee reminder notifications (would need an email/SMS service).

Happy to build any of those out next — just say which one.
