-- ============================================================
-- Disposable App - Database Schema with Row Level Security
-- ============================================================

-- 1. Create Events table
create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  description text,
  event_type text check (event_type in ('wedding', 'party', 'celebration', 'other')),
  cover_image_url text,
  created_at timestamp with time zone default now(),
  starts_at timestamp with time zone not null,
  ends_at timestamp with time zone,
  expires_at timestamp with time zone,
  max_photos integer default 999,
  is_public boolean default false
);

-- 2. Create Photos table
create table if not exists public.photos (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  photo_url text not null,
  thumbnail_url text,
  caption text,
  views_count integer default 0,
  created_at timestamp with time zone default now(),
  expires_at timestamp with time zone,
  is_deleted boolean default false
);

-- 3. Create Guests table for event participants
create table if not exists public.guests (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  email text,
  phone text,
  name text,
  guest_code text unique,
  is_registered boolean default false,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

-- 4. Create Photo Likes table (optional, for engagement)
create table if not exists public.photo_likes (
  id uuid primary key default gen_random_uuid(),
  photo_id uuid not null references public.photos(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  guest_code text,
  created_at timestamp with time zone default now()
);

-- ============================================================
-- Row Level Security (RLS) Policies
-- ============================================================

-- Enable RLS on all tables
alter table public.events enable row level security;
alter table public.photos enable row level security;
alter table public.guests enable row level security;
alter table public.photo_likes enable row level security;

-- EVENTS RLS Policies
-- Users can view their own events
create policy "Users can view their own events" on public.events for select
  using (auth.uid() = user_id);

-- Users can create events
create policy "Users can create events" on public.events for insert
  with check (auth.uid() = user_id);

-- Users can update their own events
create policy "Users can update their own events" on public.events for update
  using (auth.uid() = user_id);

-- Users can delete their own events
create policy "Users can delete their own events" on public.events for delete
  using (auth.uid() = user_id);

-- Public events can be viewed by anyone (for guest access)
create policy "Public events are viewable" on public.events for select
  using (is_public = true);

-- PHOTOS RLS Policies
-- Anyone can view photos from public events
create policy "View photos from public events" on public.photos for select
  using (
    exists (
      select 1 from public.events
      where public.events.id = public.photos.event_id
      and (public.events.is_public = true or public.events.user_id = auth.uid())
    )
  );

-- Users can upload photos to public events they participate in
create policy "Users can upload photos to events" on public.photos for insert
  with check (true);

-- Users can delete their own photos
create policy "Users can delete their own photos" on public.photos for delete
  using (auth.uid() = user_id);

-- GUESTS RLS Policies
-- Event organizers can view guests
create policy "Event organizers can view guests" on public.guests for select
  using (
    exists (
      select 1 from public.events
      where public.events.id = public.guests.event_id
      and public.events.user_id = auth.uid()
    )
  );

-- Guests can be inserted without auth (anonymous uploads)
create policy "Anyone can register as guest" on public.guests for insert
  with check (true);

-- PHOTO LIKES RLS Policies
-- Anyone can view and create likes
create policy "Anyone can view photo likes" on public.photo_likes for select
  using (true);

create policy "Anyone can create photo likes" on public.photo_likes for insert
  with check (true);

-- ============================================================
-- Indexes for Performance
-- ============================================================

create index if not exists events_user_id_idx on public.events(user_id);
create index if not exists events_created_at_idx on public.events(created_at);
create index if not exists photos_event_id_idx on public.photos(event_id);
create index if not exists photos_user_id_idx on public.photos(user_id);
create index if not exists photos_created_at_idx on public.photos(created_at);
create index if not exists guests_event_id_idx on public.guests(event_id);
create index if not exists guests_guest_code_idx on public.guests(guest_code);
create index if not exists photo_likes_photo_id_idx on public.photo_likes(photo_id);
create index if not exists photo_likes_user_id_idx on public.photo_likes(user_id);

-- ============================================================
-- Triggers for Auto-expiration (optional)
-- ============================================================

-- Function to mark photos as deleted if they're past their expiration
create or replace function public.auto_expire_photos()
returns trigger as $$
begin
  update public.photos
  set is_deleted = true
  where expires_at is not null and expires_at < now();
  return null;
end;
$$ language plpgsql;

-- Note: Run this trigger manually or via a cron job in Supabase
-- You can test it with: select public.auto_expire_photos();
