-- Poubelle Tycoon : comptes pseudo + mot de passe et classement.
-- À coller une seule fois dans Supabase : SQL Editor > New query > Run.
-- Pense aussi à désactiver "Confirm email" (Authentication > Sign In / Providers > Email).

-- ============ Tables ============
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  pseudo text not null check (pseudo ~ '^[A-Za-z0-9_-]{3,16}$'),
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_pseudo_lower on public.profiles (lower(pseudo));

create table if not exists public.scores (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  score double precision not null default 0 check (score >= 0),
  updated_at timestamptz not null default now()
);
create index if not exists scores_score_desc on public.scores (score desc);

-- Personne n'écrit directement dans les tables : tout passe par les fonctions plus bas.
alter table public.profiles enable row level security;
alter table public.scores enable row level security;
drop policy if exists "profils lisibles" on public.profiles;
create policy "profils lisibles" on public.profiles for select using (true);
drop policy if exists "scores lisibles" on public.scores;
create policy "scores lisibles" on public.scores for select using (true);

-- ============ Création du profil à l'inscription ============
-- Le jeu envoie le pseudo dans les métadonnées ; un pseudo invalide ou déjà pris annule l'inscription.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, pseudo) values (new.id, new.raw_user_meta_data ->> 'pseudo');
  insert into public.scores (user_id, score, updated_at) values (new.id, 0, now());
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============ Envoi du score (anti-triche) ============
-- Le score ne baisse jamais, et il ne peut pas grimper plus vite qu'un plafond :
-- 2 000 + 1,5 % du score actuel par minute écoulée depuis le dernier envoi.
-- Un score trop haut n'est pas refusé : il est ramené au plafond et rattrape son retard aux envois suivants.
create or replace function public.submit_score(p_score double precision)
returns double precision language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  old_score double precision;
  old_at timestamptz;
  minutes double precision;
  cap double precision;
  new_score double precision;
begin
  if uid is null then raise exception 'non connecté'; end if;
  if p_score is null or p_score = 'NaN' or p_score = 'Infinity' or p_score < 0 then raise exception 'score invalide'; end if;

  select score, updated_at into old_score, old_at from public.scores where user_id = uid for update;
  if not found then
    old_score := 0;
    select created_at into old_at from public.profiles where id = uid;
    insert into public.scores (user_id, score, updated_at) values (uid, 0, coalesce(old_at, now()));
  end if;

  -- Un envoi toutes les 20 secondes maximum.
  if now() - old_at < interval '20 seconds' then return old_score; end if;

  minutes := extract(epoch from (now() - old_at)) / 60;
  cap := old_score + (2000 + old_score * 0.015) * minutes;
  new_score := greatest(old_score, least(p_score, cap));

  update public.scores set score = new_score, updated_at = now() where user_id = uid;
  return new_score;
end $$;

-- ============ Lecture du classement ============
create or replace function public.get_leaderboard(p_limit int default 50)
returns table (rank bigint, pseudo text, score double precision, is_me boolean)
language sql stable security definer set search_path = '' as $$
  with ranked as (
    select rank() over (order by s.score desc) as rank, p.pseudo, s.score, s.user_id = auth.uid() as is_me
    from public.scores s join public.profiles p on p.id = s.user_id
  )
  select * from ranked
  where rank <= least(greatest(p_limit, 1), 100) or is_me
  order by rank, pseudo;
$$;

revoke all on function public.submit_score(double precision) from public, anon;
grant execute on function public.submit_score(double precision) to authenticated;
revoke all on function public.get_leaderboard(int) from public;
grant execute on function public.get_leaderboard(int) to anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
