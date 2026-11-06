-- =====================================================================
--  Mise à jour : olympiades (Oui / Peut-être / Non par personne), lien perso
--  de modification, verrou des modifications après le 29 mars 2027, pot de miel.
--  À coller dans Supabase > SQL Editor > New query, puis "Run".
--  Ne supprime aucune réponse ; peut être relancé sans risque.
-- =====================================================================

-- Mise à niveau d'une base existante : ajoute la colonne, ou la convertit si elle était en oui/non (boolean)
do $$
declare t text;
begin
  select data_type into t from information_schema.columns
   where table_schema = 'public' and table_name = 'participants' and column_name = 'olympiades';
  if t is null then
    alter table public.participants add column olympiades text;
  elsif t = 'boolean' then
    alter table public.participants alter column olympiades type text
      using case when olympiades then 'Oui' when not olympiades then 'Non' end;
  end if;
end $$;
alter table public.participants drop constraint if exists participants_olympiades_check;
alter table public.participants add constraint participants_olympiades_check
  check (olympiades in ('Oui', 'Peut-être', 'Non'));

create or replace function public.submit_rsvp(p jsonb)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare
  rid      uuid := (p ->> 'id')::uuid;
  pres     text := p ->> 'presence';
  vient    boolean := pres in ('Oui', 'Peut-être');
  nb_parts int  := coalesce(jsonb_array_length(p -> 'participants'), 0);
begin
  -- Pot de miel : champ invisible rempli = robot. On ignore sans rien dire.
  if coalesce(p ->> 'hp', '') <> '' then return; end if;
  if rid is null then raise exception 'id manquant'; end if;
  -- Date limite : après le 29 mars 2027 (heure de Paris), une réponse existante ne peut plus être modifiée,
  -- sauf par un organisateur connecté. (Même date que verrouModifs dans index.html.)
  if now() >= timestamptz '2027-03-30 00:00:00 Europe/Paris'
     and exists (select 1 from public.reponses where id = rid)
     and not public.is_admin() then
    raise exception 'modifications_closes';
  end if;
  if nb_parts > 12 then raise exception 'Trop de participants'; end if;
  -- Garde-fou anti-spam : la table ne peut pas dépasser 400 réponses (94 invitations prévues)
  if not exists (select 1 from public.reponses where id = rid)
     and (select count(*) from public.reponses) >= 400 then
    raise exception 'Limite de réponses atteinte';
  end if;

  insert into public.reponses as r
    (id, nom, contact, presence, arrivee, dodo, covoit, ville_depart, places, aide, chanson, message)
  values (
    rid,
    btrim(p ->> 'nom'),
    nullif(btrim(p ->> 'contact'), ''),
    pres,
    case when vient then nullif(p ->> 'arrivee', '') end,
    case when vient then nullif(p ->> 'dodo', '') end,
    case when vient then nullif(p ->> 'covoit', '') end,
    case when vient then nullif(btrim(p ->> 'villeDepart'), '') end,
    case when vient and p ->> 'covoit' = 'Propose' then nullif(p ->> 'places', '')::int end,
    case when vient then coalesce(
      array(select left(x, 40) from jsonb_array_elements_text(coalesce(p -> 'aide', '[]'::jsonb)) as x limit 10),
      '{}') else '{}' end,
    case when vient then nullif(btrim(p ->> 'chanson'), '') end,
    nullif(btrim(p ->> 'message'), '')
  )
  on conflict (id) do update set
    updated_at   = now(),
    nom          = excluded.nom,
    contact      = excluded.contact,
    presence     = excluded.presence,
    arrivee      = excluded.arrivee,
    dodo         = excluded.dodo,
    covoit       = excluded.covoit,
    ville_depart = excluded.ville_depart,
    places       = excluded.places,
    aide         = excluded.aide,
    chanson      = excluded.chanson,
    message      = excluded.message;

  delete from public.participants where reponse_id = rid;

  if vient then
    insert into public.participants (reponse_id, ordre, nom, type, regime, precision, olympiades)
    select rid,
           t.ord,
           left(coalesce(nullif(btrim(t.e ->> 'nom'), ''), 'Invité ' || t.ord), 80),
           case when t.e ->> 'type' like 'Enfant%' then 'Enfant' else 'Adulte' end,
           left(coalesce(nullif(t.e ->> 'regime', ''), 'Aucun'), 40),
           nullif(left(btrim(coalesce(t.e ->> 'precision', '')), 200), ''),
           case when p ->> 'arrivee' = 'Après-midi' and t.e ->> 'olympiades' in ('Oui', 'Peut-être', 'Non')
                then t.e ->> 'olympiades' end
    from jsonb_array_elements(coalesce(p -> 'participants', '[]'::jsonb)) with ordinality as t(e, ord);
  end if;
end;
$$;
revoke execute on function public.submit_rsvp(jsonb) from public;
grant  execute on function public.submit_rsvp(jsonb) to anon, authenticated;

-- ---------- Lien perso : relire SA réponse à partir de son id ----------
-- L'id est un UUID aléatoire (impossible à deviner) : le connaître revient à avoir le lien perso.
create or replace function public.get_rsvp(rid uuid)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'id', r.id, 'nom', r.nom, 'contact', coalesce(r.contact, ''), 'presence', r.presence,
    'arrivee', coalesce(r.arrivee, ''), 'dodo', coalesce(r.dodo, ''), 'message', coalesce(r.message, ''),
    'participants', coalesce((
      select jsonb_agg(jsonb_build_object(
               'nom', p.nom,
               'type', case when p.type = 'Enfant' then 'Enfant (- 12 ans)' else 'Adulte' end,
               'regime', p.regime, 'precision', coalesce(p.precision, ''), 'olympiades', p.olympiades)
             order by p.ordre)
      from public.participants p where p.reponse_id = r.id), '[]'::jsonb))
  from public.reponses r
  where r.id = rid;
$$;
revoke execute on function public.get_rsvp(uuid) from public;
grant  execute on function public.get_rsvp(uuid) to anon, authenticated;
