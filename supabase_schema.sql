-- =============================================
-- SLP Compliance Audit - Database Schema
-- =============================================

-- Profiles table (extends Supabase auth)
create table profiles (
  id uuid references auth.users on delete cascade primary key,
  full_name text not null default '',
  role text not null default 'teacher' check (role in ('admin', 'teacher')),
  created_at timestamptz default now()
);

-- Audits table (one row per completed audit)
create table audits (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references profiles(id) not null,
  audit_type text not null check (audit_type in ('admin_facility', 'licensing', 'ahs', 'kitchen', 'pedagogy', 'daily_compliance')),
  audit_date date not null,
  room text not null,
  inspector text not null,
  teacher1 text not null,
  teacher2 text default '',
  total_achieved integer default 0,
  total_max integer default 0,
  total_pct numeric(5,1) default 0,
  created_at timestamptz default now()
);

-- Audit answers (one row per question answered)
create table audit_answers (
  id uuid default gen_random_uuid() primary key,
  audit_id uuid references audits(id) on delete cascade not null,
  item_id text not null,
  section_name text not null,
  answer text check (answer in ('compliant', 'non-compliant', 'na', '')),
  weight integer not null default 1,
  points integer default 0,
  max_points integer default 0,
  comment text default '',
  created_at timestamptz default now()
);

-- =============================================
-- Row Level Security
-- =============================================
alter table profiles enable row level security;
alter table audits enable row level security;
alter table audit_answers enable row level security;

-- Profiles policies
create policy "Users can view own profile"
  on profiles for select using (auth.uid() = id);

create policy "Admins can view all profiles"
  on profiles for select using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );

create policy "Users can update own profile"
  on profiles for update using (auth.uid() = id);

-- Audits policies
create policy "Users can insert own audits"
  on audits for insert with check (auth.uid() = user_id);

create policy "Users can view own audits"
  on audits for select using (auth.uid() = user_id);

create policy "Admins can view all audits"
  on audits for select using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );

-- Audit answers policies
create policy "Users can insert answers for own audits"
  on audit_answers for insert with check (
    (select user_id from audits where id = audit_id) = auth.uid()
  );

create policy "Users can view answers for own audits"
  on audit_answers for select using (
    (select user_id from audits where id = audit_id) = auth.uid()
  );

create policy "Admins can view all answers"
  on audit_answers for select using (
    (select role from profiles where id = auth.uid()) = 'admin'
  );

-- =============================================
-- Auto-create profile on signup
-- =============================================
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    coalesce(new.raw_user_meta_data->>'role', 'teacher')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
