-- Homeless Tycoon : comptes pseudo + mot de passe, classement et sauvegarde en ligne.
-- À coller dans Supabase : SQL Editor > New query > Run. On peut le relancer sans risque après une mise à jour.
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

-- ============ Sauvegarde de la partie dans le compte ============
-- Chaque joueur ne peut lire et écrire que sa propre sauvegarde.
create table if not exists public.saves (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  data jsonb not null check (pg_column_size(data) < 1000000),
  updated_at timestamptz not null default now()
);
alter table public.saves enable row level security;
drop policy if exists "ma sauvegarde : lire" on public.saves;
create policy "ma sauvegarde : lire" on public.saves for select to authenticated using (user_id = auth.uid());
drop policy if exists "ma sauvegarde : créer" on public.saves;
create policy "ma sauvegarde : créer" on public.saves for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "ma sauvegarde : modifier" on public.saves;
create policy "ma sauvegarde : modifier" on public.saves for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ============ Comptes créés avant ce script ============
-- Un compte inscrit avant la création du déclencheur n'a ni profil ni score : il n'apparaît pas au classement
-- et sa sauvegarde est refusée. On les rattrape ici, puis le jeu appelle ensure_profile() à chaque connexion.
insert into public.profiles (id, pseudo)
  select u.id, u.raw_user_meta_data ->> 'pseudo' from auth.users u
  where (u.raw_user_meta_data ->> 'pseudo') ~ '^[A-Za-z0-9_-]{3,16}$'
    and not exists (select 1 from public.profiles p where p.id = u.id)
    and not exists (select 1 from public.profiles p where lower(p.pseudo) = lower(u.raw_user_meta_data ->> 'pseudo'))
  on conflict do nothing;
insert into public.scores (user_id) select id from public.profiles on conflict do nothing;

drop function if exists public.ensure_profile();
create function public.ensure_profile()
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); ps text;
begin
  if uid is null then return 'non connecté'; end if;
  if not exists (select 1 from public.profiles where id = uid) then
    select u.raw_user_meta_data ->> 'pseudo' into ps from auth.users u where u.id = uid;
    if ps is null or ps !~ '^[A-Za-z0-9_-]{3,16}$' then return 'pseudo invalide (' || coalesce(ps, 'vide') || ')'; end if;
    if exists (select 1 from public.profiles where lower(pseudo) = lower(ps)) then return 'le pseudo ' || ps || ' est déjà pris par un autre compte'; end if;
    insert into public.profiles (id, pseudo) values (uid, ps);
  end if;
  insert into public.scores (user_id) values (uid) on conflict do nothing;
  return 'ok';
exception when others then return sqlerrm;
end $$;
revoke all on function public.ensure_profile() from public, anon;
grant execute on function public.ensure_profile() to authenticated;

-- ============ Changer de pseudo ============
-- Change le nom affiché au classement. L'identifiant de connexion (pseudo choisi à l'inscription) ne change pas,
-- donc un pseudo ne peut pas reprendre l'identifiant de connexion d'un autre joueur.
create or replace function public.set_pseudo(p_pseudo text)
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then return 'Tu n''es pas connecté'; end if;
  if p_pseudo is null or p_pseudo !~ '^[A-Za-z0-9_-]{3,16}$' then return 'Pseudo : 3 à 16 caractères, lettres, chiffres, - ou _'; end if;
  if exists (select 1 from public.profiles where lower(pseudo) = lower(p_pseudo) and id <> uid)
     or exists (select 1 from auth.users where lower(email) = lower(p_pseudo) || '@joueurs.poubelletycoon.app' and id <> uid)
  then return 'Ce pseudo est déjà pris'; end if;
  update public.profiles set pseudo = p_pseudo where id = uid;
  if not found then return 'Profil introuvable : reconnecte-toi'; end if;
  begin -- le jeu met aussi à jour ce champ de son côté : un refus ici n'annule pas le changement
    update auth.users set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('pseudo', p_pseudo) where id = uid;
  exception when others then null;
  end;
  return 'ok';
exception when unique_violation then return 'Ce pseudo est déjà pris';
end $$;
revoke all on function public.set_pseudo(text) from public, anon;
grant execute on function public.set_pseudo(text) to authenticated;
