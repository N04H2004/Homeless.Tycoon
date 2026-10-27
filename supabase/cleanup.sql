-- Homeless Tycoon : ménage automatique pour rester dans le plan gratuit Supabase.
-- À coller une seule fois dans Supabase : SQL Editor > New query > Run.
-- Avant : Database > Extensions > active "pg_cron".
--
-- Chaque nuit à 4 h (UTC) :
--  - supprime les comptes INVITÉS (anonymes, joueurs CrazyGames) sans connexion depuis 30 jours,
--    avec leur profil, score, sauvegarde et le reste (suppression en cascade) ;
--  - vide la table de présence des joueurs qui ne sont plus en ligne depuis 1 jour.
-- Les comptes avec pseudo + mot de passe ne sont jamais supprimés.

create extension if not exists pg_cron;

create or replace function public.cleanup_inactive()
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from auth.users
   where is_anonymous
     and coalesce(last_sign_in_at, created_at) < now() - interval '30 days'
     and not exists (select 1 from public.saves s where s.user_id = auth.users.id and s.updated_at > now() - interval '30 days');
  delete from public.presence where seen_at < now() - interval '1 day';
end $$;
revoke all on function public.cleanup_inactive() from public, anon, authenticated;

select cron.unschedule('homeless-cleanup') where exists (select 1 from cron.job where jobname = 'homeless-cleanup');
select cron.schedule('homeless-cleanup', '0 4 * * *', 'select public.cleanup_inactive()');
