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
drop function if exists public.get_leaderboard(int);
create function public.get_leaderboard(p_limit int default 50)
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

-- ============ Remarques des joueurs (bugs, idées...) ============
-- Les joueurs écrivent via send_feedback() ; personne ne peut les relire depuis le jeu.
-- Pour les lire : Table Editor > feedback (ou : select * from public.feedback order by created_at desc;)
create table if not exists public.feedback (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  user_id uuid references auth.users (id) on delete set null,
  pseudo text,
  kind text not null check (kind in ('bug', 'idee', 'autre')),
  message text not null check (char_length(message) between 3 and 2000),
  info jsonb,
  traite boolean not null default false
);
alter table public.feedback enable row level security;

create or replace function public.send_feedback(p_kind text, p_message text, p_info jsonb default null)
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); ps text; msg text := btrim(coalesce(p_message, ''));
begin
  if p_kind not in ('bug', 'idee', 'autre') then return 'Type de remarque inconnu'; end if;
  if char_length(msg) < 3 then return 'Écris au moins quelques mots'; end if;
  if char_length(msg) > 2000 then return 'Message trop long (2000 caractères maximum)'; end if;
  if pg_column_size(p_info) > 4000 then p_info := null; end if;
  -- anti-spam : 1 remarque toutes les 20 s par compte, 30 par heure pour les joueurs non connectés
  if uid is not null then
    if exists (select 1 from public.feedback where user_id = uid and created_at > now() - interval '20 seconds') then
      return 'Doucement ! Attends quelques secondes avant d''envoyer une autre remarque'; end if;
    select pseudo into ps from public.profiles where id = uid;
  elsif (select count(*) from public.feedback where user_id is null and created_at > now() - interval '1 hour') >= 30 then
    return 'Trop de remarques en ce moment, réessaie plus tard';
  end if;
  insert into public.feedback (user_id, pseudo, kind, message, info) values (uid, ps, p_kind, msg, p_info);
  return 'ok';
end $$;
revoke all on function public.send_feedback(text, text, jsonb) from public;
grant execute on function public.send_feedback(text, text, jsonb) to anon, authenticated;

-- ============ Visiter la rue des autres joueurs ============
-- Visite en lecture seule depuis le classement ; « rue privée » pour refuser les visites ;
-- pourboire en partant, au maximum 50 % de l'argent du joueur visité, récupéré par lui à sa prochaine connexion.
alter table public.profiles add column if not exists private boolean not null default false;

create table if not exists public.tips (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  from_id uuid references public.profiles (id) on delete cascade,
  to_id uuid not null references public.profiles (id) on delete cascade,
  amount double precision not null check (amount > 0),
  claimed boolean not null default false
);
alter table public.tips enable row level security;

drop function if exists public.get_leaderboard(int);
create function public.get_leaderboard(p_limit int default 50)
returns table (rank bigint, pseudo text, score double precision, is_me boolean, private boolean, online boolean)
language sql stable security definer set search_path = '' as $$
  -- « en ligne » : le jeu envoie le score chaque minute tant qu'il est ouvert (et pas en pause AFK)
  with ranked as (
    select rank() over (order by s.score desc) as rank, p.pseudo, s.score, s.user_id = auth.uid() as is_me, p.private,
           s.updated_at > now() - interval '150 seconds' as online
    from public.scores s join public.profiles p on p.id = s.user_id
  )
  select * from ranked
  where rank <= least(greatest(p_limit, 1), 100) or is_me
  order by rank, pseudo;
$$;
revoke all on function public.get_leaderboard(int) from public;
grant execute on function public.get_leaderboard(int) to anon, authenticated;

create or replace function public.set_private(p_private boolean)
returns text language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then return 'Tu n''es pas connecté'; end if;
  update public.profiles set private = coalesce(p_private, false) where id = auth.uid();
  return 'ok';
end $$;
revoke all on function public.set_private(boolean) from public, anon;
grant execute on function public.set_private(boolean) to authenticated;

-- ne renvoie que ce qui se voit dans la rue (pas les actions, ni le reste de la sauvegarde)
create or replace function public.get_street(p_pseudo text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare pr record; d jsonb;
begin
  select id, pseudo, private into pr from public.profiles where lower(pseudo) = lower(p_pseudo);
  if not found then return jsonb_build_object('error', 'Joueur introuvable'); end if;
  if pr.private and pr.id is distinct from auth.uid() then return jsonb_build_object('error', pr.pseudo || ' a une rue privée'); end if;
  select data into d from public.saves where user_id = pr.id;
  if d is null then return jsonb_build_object('error', pr.pseudo || ' n''a pas encore de rue sauvegardée'); end if;
  return jsonb_build_object(
    'pseudo', pr.pseudo,
    'ci', least(greatest(coalesce((d -> 'meta' ->> 'cur')::int, least(coalesce((d -> 'meta' ->> 'prestige')::int, 0), 3)), 0), 3),
    'cash', coalesce((d ->> 'cash')::double precision, 0),
    'snap', jsonb_build_object(
      'distrib', d -> 'distrib', 'distUp', d -> 'distUp', 'local', d -> 'local', 'emp', d -> 'emp', 'staff', d -> 'staff',
      'emUp', d -> 'emUp', 'manager', d -> 'manager', 'frigo', d -> 'frigo', 'secu', d -> 'secu', 'shops', d -> 'shops',
      'owned', d -> 'owned', 'rivalBought', d -> 'rivalBought', 'band', d -> 'band', 'bandUp', d -> 'bandUp', 'up', d -> 'up'));
end $$;
revoke all on function public.get_street(text) from public;
grant execute on function public.get_street(text) to anon, authenticated;

create or replace function public.send_tip(p_pseudo text, p_amount double precision)
returns text language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); pr record; c double precision;
begin
  if uid is null then return 'Connecte-toi pour laisser un pourboire'; end if;
  if p_amount is null or p_amount = 'NaN' or p_amount < 1 then return 'Pourboire trop petit'; end if;
  select id, pseudo, private into pr from public.profiles where lower(pseudo) = lower(p_pseudo);
  if not found then return 'Joueur introuvable'; end if;
  if pr.id = uid then return 'Pas de pourboire à toi-même !'; end if;
  if pr.private then return pr.pseudo || ' a une rue privée'; end if;
  select coalesce((data ->> 'cash')::double precision, 0) into c from public.saves where user_id = pr.id;
  if p_amount > 0.5 * coalesce(c, 0) + 1 then return 'Maximum : 50 % de l''argent de ' || pr.pseudo; end if;
  if exists (select 1 from public.tips where from_id = uid and to_id = pr.id and created_at > now() - interval '24 hours') then
    return 'Tu as déjà laissé un pourboire à ' || pr.pseudo || ' il y a moins de 24 h'; end if;
  insert into public.tips (from_id, to_id, amount) values (uid, pr.id, p_amount);
  return 'ok';
end $$;
revoke all on function public.send_tip(text, double precision) from public, anon;
grant execute on function public.send_tip(text, double precision) to authenticated;

-- le joueur visité récupère ses pourboires (une seule fois chacun)
create or replace function public.claim_tips()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r jsonb;
begin
  if uid is null then return null; end if;
  with c as (update public.tips set claimed = true where to_id = uid and not claimed returning from_id, amount),
       g as (select coalesce(p.pseudo, 'Un visiteur') as pseudo, sum(c.amount) as amount from c left join public.profiles p on p.id = c.from_id group by 1)
  select jsonb_build_object('total', coalesce(sum(g.amount), 0),
                            'from', coalesce(jsonb_agg(g.pseudo), '[]'::jsonb),
                            'items', coalesce(jsonb_agg(jsonb_build_object('pseudo', g.pseudo, 'amount', g.amount)), '[]'::jsonb))
    into r from g;
  return r;
end $$;
revoke all on function public.claim_tips() from public, anon;
grant execute on function public.claim_tips() to authenticated;

-- ============ Braquer un joueur du classement ============
-- Mini-jeu de tir côté jeu : le taux de réussite (0 à 1) donne de 5 % au butin maximum (30 % à 5 % selon la richesse),
-- sans jamais dépasser l'argent du voleur.
-- Le voleur : 1 braquage par heure. La cible : protégée 24 h après s'être fait braquer.
-- Une rue privée ne peut ni braquer ni être braquée. La cible perd l'argent à sa prochaine connexion.
create table if not exists public.heists (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  from_id uuid references public.profiles (id) on delete set null,
  to_id uuid not null references public.profiles (id) on delete cascade,
  pct double precision not null,
  amount double precision not null check (amount >= 0),
  claimed boolean not null default false
);
alter table public.heists enable row level security;

-- butin maximum selon la richesse : 30 % si la cible a autant ou moins que toi, 5 % si elle a 10 fois plus (échelle logarithmique)
create or replace function public.heist_pctmax(p_victim double precision, p_thief double precision)
returns double precision language sql immutable as $$
  select 30 - 25 * least(greatest(log(greatest(coalesce(p_victim, 0), 1) / greatest(coalesce(p_thief, 0), 1)), 0), 1)
$$;

create or replace function public.heist_preview(p_pseudo text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := auth.uid(); pr record; c double precision; mine double precision;
begin
  if uid is null then return jsonb_build_object('error', 'Connecte-toi pour braquer'); end if;
  select id, pseudo, private into pr from public.profiles where lower(pseudo) = lower(p_pseudo);
  if not found or pr.private then return jsonb_build_object('error', 'Cible indisponible'); end if;
  select coalesce((data ->> 'cash')::double precision, 0) into c from public.saves where user_id = pr.id;
  select coalesce((data ->> 'cash')::double precision, 0) into mine from public.saves where user_id = uid;
  return jsonb_build_object('pseudo', pr.pseudo, 'pctmax', round(public.heist_pctmax(c, mine)::numeric, 1));
end $$;
revoke all on function public.heist_preview(text) from public, anon;
grant execute on function public.heist_preview(text) to authenticated;

create or replace function public.heist_player(p_pseudo text, p_rate double precision)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); pr record; c double precision; mine double precision; r double precision; pmax double precision; pct double precision; amt double precision;
begin
  if uid is null then return jsonb_build_object('error', 'Connecte-toi pour braquer'); end if;
  if exists (select 1 from public.profiles where id = uid and private) then return jsonb_build_object('error', 'Ta rue est privée : impossible de braquer les autres'); end if;
  select id, pseudo, private into pr from public.profiles where lower(pseudo) = lower(p_pseudo);
  if not found then return jsonb_build_object('error', 'Joueur introuvable'); end if;
  if pr.id = uid then return jsonb_build_object('error', 'Tu ne peux pas te braquer toi-même'); end if;
  if pr.private then return jsonb_build_object('error', pr.pseudo || ' a une rue privée'); end if;
  if exists (select 1 from public.heists where from_id = uid and created_at > now() - interval '1 hour') then
    return jsonb_build_object('error', 'Tes bandits se font discrets : un braquage par heure'); end if;
  if exists (select 1 from public.heists where to_id = pr.id and created_at > now() - interval '24 hours') then
    return jsonb_build_object('error', pr.pseudo || ' s''est déjà fait braquer aujourd''hui'); end if;
  r := least(greatest(coalesce(nullif(p_rate, 'NaN'), 0), 0), 1);
  select coalesce((data ->> 'cash')::double precision, 0) into c from public.saves where user_id = pr.id;
  select coalesce((data ->> 'cash')::double precision, 0) into mine from public.saves where user_id = uid;
  c := greatest(coalesce(c, 0), 0); mine := greatest(coalesce(mine, 0), 0);
  pmax := public.heist_pctmax(c, mine);
  pct := round((5 + (pmax - 5) * r)::numeric, 1);
  amt := least(floor(c * pct / 100), floor(mine));  -- jamais plus que l'argent du voleur
  if amt < 1 then return jsonb_build_object('error', case when floor(c * pct / 100) < 1 then pr.pseudo || ' n''a rien à voler' else 'Ton butin est plafonné à ton propre argent : tu n''as rien sur toi' end); end if;
  insert into public.heists (from_id, to_id, pct, amount) values (uid, pr.id, pct, amt);
  return jsonb_build_object('ok', true, 'pseudo', pr.pseudo, 'pct', pct, 'pctmax', round(pmax::numeric, 1), 'amount', amt, 'capped', amt < floor(c * pct / 100));
end $$;
revoke all on function public.heist_player(text, double precision) from public, anon;
grant execute on function public.heist_player(text, double precision) to authenticated;

-- la victime découvre ses braquages (une seule fois chacun)
create or replace function public.claim_heists()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); r jsonb;
begin
  if uid is null then return null; end if;
  with c as (update public.heists set claimed = true where to_id = uid and not claimed returning from_id, amount),
       g as (select coalesce(p.pseudo, 'Un inconnu') as pseudo, sum(c.amount) as amount from c left join public.profiles p on p.id = c.from_id group by 1)
  select jsonb_build_object('total', coalesce(sum(g.amount), 0), 'items', coalesce(jsonb_agg(jsonb_build_object('pseudo', g.pseudo, 'amount', g.amount)), '[]'::jsonb)) into r from g;
  return r;
end $$;
revoke all on function public.claim_heists() from public, anon;
grant execute on function public.claim_heists() to authenticated;
