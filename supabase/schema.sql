-- FUTURON MVP: virtual, NON-REDEEMABLE points. Run once in Supabase SQL Editor.
-- No real-money transactions, deposits, withdrawals, or payouts.

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Player',
  favorite_sport text,
  created_at timestamptz not null default now(),
  constraint valid_display_name check (char_length(display_name) between 1 and 80)
);

create table if not exists public.wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  points integer not null default 2500 check (points >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.matches (
  id bigint generated always as identity primary key,
  sport text not null,
  league text not null,
  home_team text not null,
  away_team text not null,
  starts_at timestamptz not null,
  status text not null default 'upcoming' check (status in ('upcoming','live','final')),
  result text check (result in ('home','draw','away')),
  created_at timestamptz not null default now(),
  constraint final_has_result check (status <> 'final' or result is not null)
);

create table if not exists public.predictions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  match_id bigint not null references public.matches(id),
  selection text not null check (selection in ('home','draw','away')),
  stake integer not null check (stake in (50, 100, 250, 500)),
  status text not null default 'pending' check (status in ('pending','won','lost')),
  payout integer not null default 0 check (payout >= 0),
  created_at timestamptz not null default now(),
  unique(user_id, match_id)
);

create table if not exists public.point_transactions (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null,
  category text not null check (category in ('welcome','prediction','reward')),
  prediction_id bigint references public.predictions(id),
  created_at timestamptz not null default now()
);

create index if not exists predictions_user_created_idx on public.predictions(user_id, created_at desc);
create index if not exists transactions_user_created_idx on public.point_transactions(user_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.wallets enable row level security;
alter table public.matches enable row level security;
alter table public.predictions enable row level security;
alter table public.point_transactions enable row level security;

-- No client INSERT/UPDATE/DELETE policies on balances, predictions or ledger.
create policy "Read own profile" on public.profiles for select to authenticated using ((select auth.uid()) = id);
create policy "Update own profile" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
create policy "Read own wallet" on public.wallets for select to authenticated using ((select auth.uid()) = user_id);
create policy "Read matches" on public.matches for select to authenticated using (true);
create policy "Read own predictions" on public.predictions for select to authenticated using ((select auth.uid()) = user_id);
create policy "Read own ledger" on public.point_transactions for select to authenticated using ((select auth.uid()) = user_id);

-- Onboarding credit happens exactly once when auth.users row is created.
create or replace function public.new_futuron_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name) values (new.id, left(coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Player'), 80));
  insert into public.wallets(user_id, points) values (new.id, 2500);
  insert into public.point_transactions(user_id, amount, category) values (new.id, 2500, 'welcome');
  return new;
end;
$$;
drop trigger if exists on_futuron_user_created on auth.users;
create trigger on_futuron_user_created after insert on auth.users for each row execute function public.new_futuron_user();

-- Only an authenticated user can place one prediction per upcoming match.
-- Row locks and one DB transaction make balances safe from client-side tampering.
create or replace function public.place_prediction(p_match_id bigint, p_selection text, p_stake integer)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_match public.matches%rowtype;
  v_balance integer;
  v_id bigint;
begin
  if v_user is null then raise exception 'Authentication required'; end if;
  if p_selection not in ('home','draw','away') or p_selection is null then raise exception 'Invalid prediction'; end if;
  if p_stake not in (50, 100, 250, 500) or p_stake is null then raise exception 'Invalid point amount'; end if;

  select * into v_match from public.matches where id = p_match_id for share;
  if not found or v_match.status <> 'upcoming' or v_match.starts_at <= now() then
    raise exception 'This match is no longer open for predictions';
  end if;
  if exists (select 1 from public.predictions where user_id = v_user and match_id = p_match_id) then
    raise exception 'You have already predicted this match';
  end if;

  select points into v_balance from public.wallets where user_id = v_user for update;
  if v_balance is null or v_balance < p_stake then raise exception 'Not enough virtual points'; end if;

  insert into public.predictions(user_id, match_id, selection, stake)
    values (v_user, p_match_id, p_selection, p_stake) returning id into v_id;
  update public.wallets set points = points - p_stake, updated_at = now() where user_id = v_user;
  insert into public.point_transactions(user_id, amount, category, prediction_id)
    values (v_user, -p_stake, 'prediction', v_id);
  return v_id;
end;
$$;

-- Don't allow arbitrary users to execute privileged functions or mutate ledger directly.
revoke all on function public.new_futuron_user() from public, anon, authenticated;
revoke all on function public.place_prediction(bigint, text, integer) from public, anon;
grant execute on function public.place_prediction(bigint, text, integer) to authenticated;

-- Sample fictional match data (not real sporting events or odds).
insert into public.matches (sport, league, home_team, away_team, starts_at, status)
select v.sport, v.league, v.home_team, v.away_team, now() + v.days_ahead * interval '1 day', 'upcoming'
from (values
 ('Soccer', 'FUTURON DEMO LEAGUE', 'New York FC', 'London United', 30),
 ('Soccer', 'FUTURON DEMO LEAGUE', 'Madrid Stars', 'Paris Athletic', 31),
 ('Basketball', 'FUTURON DEMO LEAGUE', 'East City', 'West Harbor', 32),
 ('Tennis', 'FUTURON DEMO TOUR', 'Player A', 'Player B', 33)
) as v(sport,league,home_team,away_team,days_ahead)
where not exists (select 1 from public.matches limit 1);

-- MVP deliberately does NOT expose client-side settlement, point top-ups, payouts, or redemption.
-- Production settlement requires a separate auditable, server-only workflow.
