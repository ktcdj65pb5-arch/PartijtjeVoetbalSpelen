-- Schema voor de S.V. Wissel veldreservering
-- Uit te voeren in de Supabase SQL editor (Project > SQL Editor > New query)

create extension if not exists pgcrypto;

-- 1. Speeldagen ------------------------------------------------------------
-- Eén rij per speelmoment (nu 3: 27 sep, 11 okt, 1 nov 2026).
-- "eenheden_per_tijdsblok" = het veld verdeeld in kwart-plekken (standaard 4:
-- het hele veld). Een half veld kost er 2, een kwart veld 1.

create table speeldagen (
  id uuid primary key default gen_random_uuid(),
  datum date not null unique,
  eenheden_per_tijdsblok integer not null default 4 check (eenheden_per_tijdsblok >= 0),
  created_at timestamptz not null default now()
);

-- 2. Reserveringen -----------------------------------------------------------

create table reserveringen (
  id uuid primary key default gen_random_uuid(),
  speeldag_id uuid not null references speeldagen(id) on delete cascade,
  tijdsblok text not null check (tijdsblok in ('10-11', '11-12')),
  veldtype text not null check (veldtype in ('half', 'kwart')),
  naam text not null,
  team text,
  telefoon text not null,
  aantal_deelnemers integer not null check (aantal_deelnemers >= 1),
  email text,
  doeltje text,
  opmerking text,
  created_at timestamptz not null default now()
);

create index on reserveringen (speeldag_id, tijdsblok);

-- 3. Prijzen (publiek zichtbaar) --------------------------------------------

create table prijzen (
  veldtype text primary key check (veldtype in ('half', 'kwart')),
  bedrag numeric(6,2) not null check (bedrag >= 0)
);

insert into prijzen (veldtype, bedrag) values
  ('half', 25),
  ('kwart', 15);

-- 4. Beheerinstellingen (NIET publiek zichtbaar) -----------------------------
-- Bevat de beheer-pincode. Losse tabel van "prijzen" zodat de RLS-policies
-- hieronder het makkelijk gescheiden kunnen houden: iedereen mag prijzen
-- lezen, niemand behalve een ingelogde beheerder mag de pincode lezen.

create table admin_instellingen (
  id integer primary key default 1 check (id = 1),
  pincode text not null default '1234'
);

insert into admin_instellingen (id, pincode) values (1, '1234');

-- 5. Capaciteit afdwingen in de database -------------------------------------
-- Voorkomt overboeken ook bij gelijktijdige aanmeldingen (dit deed de client
-- eerst zelf, maar dat is niet waterdicht bij twee mensen die tegelijk
-- inschrijven). "half" telt als 2 eenheden, "kwart" als 1.

create or replace function check_capaciteit()
returns trigger as $$
declare
  kosten integer;
  bezet integer;
  capaciteit integer;
begin
  kosten := case new.veldtype when 'half' then 2 else 1 end;

  select eenheden_per_tijdsblok into capaciteit
  from speeldagen where id = new.speeldag_id;

  select coalesce(sum(case veldtype when 'half' then 2 else 1 end), 0) into bezet
  from reserveringen
  where speeldag_id = new.speeldag_id and tijdsblok = new.tijdsblok;

  if bezet + kosten > capaciteit then
    raise exception 'Niet genoeg ruimte meer in dit tijdsblok';
  end if;

  return new;
end;
$$ language plpgsql;

create trigger trg_check_capaciteit
  before insert on reserveringen
  for each row execute function check_capaciteit();

-- 6. Publiek zichtbare beschikbaarheid (zonder namen/telefoonnummers) -------
-- De publieke inschrijfpagina gebruikt deze view om te tonen hoeveel plekken
-- vrij zijn, zonder dat bezoekers elkaars contactgegevens kunnen zien.

create view bezetting as
select
  speeldag_id,
  tijdsblok,
  coalesce(sum(case veldtype when 'half' then 2 else 1 end), 0) as eenheden_bezet
from reserveringen
group by speeldag_id, tijdsblok;

-- 7. Row Level Security -------------------------------------------------------

alter table speeldagen enable row level security;
alter table reserveringen enable row level security;
alter table prijzen enable row level security;
alter table admin_instellingen enable row level security;

-- Iedereen (ook niet-ingelogde bezoekers) mag speeldagen en prijzen lezen.
create policy "speeldagen zijn publiek leesbaar"
  on speeldagen for select
  to anon, authenticated
  using (true);

create policy "prijzen zijn publiek leesbaar"
  on prijzen for select
  to anon, authenticated
  using (true);

-- Iedereen mag een reservering aanmaken, maar alleen ingelogde beheerders
-- mogen bestaande reserveringen (met naam/telefoon/email) lezen of verwijderen.
create policy "iedereen mag reserveren"
  on reserveringen for insert
  to anon, authenticated
  with check (true);

create policy "alleen beheerders lezen reserveringen"
  on reserveringen for select
  to authenticated
  using (true);

create policy "alleen beheerders verwijderen reserveringen"
  on reserveringen for delete
  to authenticated
  using (true);

-- Alleen ingelogde beheerders mogen speeldagen/prijzen/instellingen wijzigen.
create policy "alleen beheerders wijzigen speeldagen"
  on speeldagen for all
  to authenticated
  using (true) with check (true);

create policy "alleen beheerders wijzigen prijzen"
  on prijzen for all
  to authenticated
  using (true) with check (true);

create policy "alleen beheerders lezen en wijzigen instellingen"
  on admin_instellingen for all
  to authenticated
  using (true) with check (true);

-- De view erft RLS van de onderliggende tabel niet automatisch door zelf een
-- SELECT-grant nodig te hebben; deze is voor iedereen leesbaar (geen
-- persoonsgegevens).
grant select on bezetting to anon, authenticated;

-- 8. Startdata: de drie speeldagen uit de flyer ------------------------------

insert into speeldagen (datum, eenheden_per_tijdsblok) values
  ('2026-09-27', 4),
  ('2026-10-11', 4),
  ('2026-11-01', 4);
