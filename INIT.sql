-- ============================================================================
-- pepa · Schema inicial (Supabase Postgres)
-- Migración MySQL→Postgres: 9 tablas + tabla auxiliar list_members para sharing
-- Diseñado para escalar a 100k usuarios sin cambios estructurales.
-- ============================================================================

-- Extensiones necesarias (pg_trgm va ANTES de cualquier índice gin_trgm_ops)
create extension if not exists "pgcrypto";   -- gen_random_uuid()
create extension if not exists "citext";     -- emails case-insensitive
create extension if not exists "pg_trgm";    -- búsqueda fuzzy trigram

-- ============================================================================
-- HELPER: trigger genérico para updated_at
-- ============================================================================
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ============================================================================
-- TABLA: profiles (extiende auth.users 1:1)
--   Por qué no editamos auth.users: es la tabla interna de Supabase Auth.
--   Toda la metadata de negocio va aquí.
-- ============================================================================
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       citext unique,
  name        text,
  role        text not null default 'user' check (role in ('user','admin')),
  is_premium  boolean not null default false,
  premium_expires_at timestamptz,
  scan_limit  integer not null default 5,   -- /mes; premium = null (ilimitado)
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index profiles_role_idx on public.profiles(role);
create index profiles_premium_idx on public.profiles(is_premium);

create trigger profiles_updated_at
before update on public.profiles
for each row execute function public.handle_updated_at();

-- Auto-crear perfil cuando se registra un usuario en auth.users
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'name', split_part(new.email,'@',1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- ============================================================================
-- TABLA: shopping_lists
--   owner_id es el dueño. list_members gestiona accesos compartidos.
--   share_token permite invitar sin cuenta creada (deep link).
-- ============================================================================
create table public.shopping_lists (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles(id) on delete cascade,
  name        text not null check (length(name) between 1 and 255),
  share_token text unique default encode(gen_random_bytes(16),'hex'),
  archived_at timestamptz,                  -- soft-delete friendly
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index shopping_lists_owner_idx on public.shopping_lists(owner_id);
create index shopping_lists_share_token_idx on public.shopping_lists(share_token) where share_token is not null;
create index shopping_lists_updated_idx on public.shopping_lists(updated_at desc);

create trigger shopping_lists_updated_at
before update on public.shopping_lists
for each row execute function public.handle_updated_at();

-- ============================================================================
-- TABLA: list_members  (N:M users ↔ lists)
--   Un usuario ve una lista si: es owner OR tiene fila en list_members.
-- ============================================================================
create type list_member_role as enum ('owner','editor','viewer');

create table public.list_members (
  list_id     uuid not null references public.shopping_lists(id) on delete cascade,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  role        list_member_role not null default 'editor',
  invited_by  uuid references public.profiles(id),
  joined_at   timestamptz not null default now(),
  primary key (list_id, user_id)
);

create index list_members_user_idx on public.list_members(user_id);

-- Cuando se crea una lista, el owner se auto-añade como owner.
create or replace function public.handle_new_list()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.list_members (list_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict do nothing;
  return new;
end;
$$;

create trigger on_shopping_list_created
after insert on public.shopping_lists
for each row execute function public.handle_new_list();

-- ============================================================================
-- TABLA: products
--   Catálogo crowdsourced. verified=false = pendiente de revisión admin.
-- ============================================================================
create table public.products (
  id                uuid primary key default gen_random_uuid(),
  ean               text unique check (ean ~ '^\d{8,14}$'),  -- EAN-8/12/13/14
  name              text not null,
  brand             text,
  category          text,
  image_url         text,
  health_score      smallint check (health_score between 0 and 100),
  verified          boolean not null default false,
  -- Para comparador de precios
  unit              text,    -- 'kg','L','unit','pack'
  unit_quantity     numeric(10,3),  -- cantidad en el envase (ej 1.5 para "1.5 L")
  standard_unit     text,    -- 'kg','L','unit' (normalizado)
  -- Origen del producto
  created_by        uuid references public.profiles(id),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index products_name_trgm_idx on public.products using gin (name gin_trgm_ops);
create index products_brand_idx on public.products(brand);
create index products_category_idx on public.products(category);
create index products_verified_idx on public.products(verified);

create trigger products_updated_at
before update on public.products
for each row execute function public.handle_updated_at();

-- ============================================================================
-- TABLA: supermarkets
-- ============================================================================
create table public.supermarkets (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  chain       text,                          -- 'Mercadona','Carrefour',...
  logo_url    text,
  created_at  timestamptz not null default now()
);

create unique index supermarkets_name_chain_uq
  on public.supermarkets(name) where chain is null;

-- ============================================================================
-- TABLA: prices
--   Histórico de precios por producto y supermercado (la killer feature del comparador).
-- ============================================================================
create table public.prices (
  id              uuid primary key default gen_random_uuid(),
  product_id      uuid not null references public.products(id) on delete cascade,
  supermarket_id  uuid not null references public.supermarkets(id) on delete cascade,
  price           numeric(10,2) not null check (price >= 0),
  currency        text not null default 'EUR',
  is_offer        boolean not null default false,
  observed_at     timestamptz not null default now(),
  reported_by     uuid references public.profiles(id),
  created_at      timestamptz not null default now()
);

create index prices_product_idx on public.prices(product_id, observed_at desc);
create index prices_supermarket_idx on public.prices(supermarket_id);
create index prices_offer_idx on public.prices(product_id) where is_offer;

-- ============================================================================
-- TABLA: list_items
--   Items dentro de una lista. product_id nullable = item "custom" sin catálogo.
-- ============================================================================
create table public.list_items (
  id          uuid primary key default gen_random_uuid(),
  list_id     uuid not null references public.shopping_lists(id) on delete cascade,
  product_id  uuid references public.products(id) on delete set null,
  name        text not null,                              -- snapshot del nombre
  brand       text,
  quantity    numeric(10,2) not null default 1,
  unit        text default 'unit',
  notes       text,
  is_purchased boolean not null default false,
  purchased_at timestamptz,
  purchased_by uuid references public.profiles(id),
  added_by    uuid references public.profiles(id),
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index list_items_list_idx on public.list_items(list_id, sort_order);
create index list_items_product_idx on public.list_items(product_id);
create index list_items_unbought_idx on public.list_items(list_id) where not is_purchased;

create trigger list_items_updated_at
before update on public.list_items
for each row execute function public.handle_updated_at();

-- Si se marca como comprado, registrar timestamp + autor
create or replace function public.handle_item_purchased()
returns trigger language plpgsql as $$
begin
  if new.is_purchased = true and old.is_purchased = false then
    new.purchased_at := now();
  elsif new.is_purchased = false then
    new.purchased_at := null;
    new.purchased_by := null;
  end if;
  return new;
end;
$$;

create trigger list_items_purchased
before update on public.list_items
for each row execute function public.handle_item_purchased();

-- ============================================================================
-- TABLA: scans  (imágenes subidas por usuarios para crear/identificar productos)
-- ============================================================================
create type scan_status as enum ('pending_review','approved','rejected');

create table public.scans (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles(id) on delete cascade,
  image_url       text not null,
  storage_path    text,                              -- path en Supabase Storage
  ean             text,
  submitted_data  jsonb,                             -- nombre, marca, precio propuestos
  result_product_id uuid references public.products(id),
  status          scan_status not null default 'pending_review',
  reviewed_by     uuid references public.profiles(id),
  reviewed_at     timestamptz,
  rejection_reason text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index scans_status_idx on public.scans(status, created_at desc);
create index scans_user_idx on public.scans(user_id);

create trigger scans_updated_at
before update on public.scans
for each row execute function public.handle_updated_at();

-- ============================================================================
-- TABLA: user_scan_limits (cuota mensual de escaneos para usuarios free)
--   Premium tiene scan_limit null en profiles (ilimitado).
--   Esta tabla hace el conteo real.
-- ============================================================================
create table public.user_scan_limits (
  user_id      uuid not null references public.profiles(id) on delete cascade,
  month        date not null,                       -- primer día del mes
  scan_count   integer not null default 0,
  primary key (user_id, month)
);

create index user_scan_limits_month_idx on public.user_scan_limits(month);

-- ============================================================================
-- TABLA: subscriptions (preparada para Stripe, VACÍA en MVP)
-- ============================================================================
create type subscription_status as enum ('active','trialing','past_due','canceled','incomplete','incomplete_expired','unpaid','paused');
create type subscription_plan   as enum ('monthly','yearly');

create table public.subscriptions (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null unique references public.profiles(id) on delete cascade,
  stripe_customer_id       text unique,
  stripe_subscription_id   text unique,
  status                   subscription_status not null default 'incomplete',
  plan                     subscription_plan,
  current_period_start     timestamptz,
  current_period_end       timestamptz,
  cancel_at_period_end     boolean not null default false,
  canceled_at              timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);

create index subscriptions_user_idx on public.subscriptions(user_id);
create index subscriptions_status_idx on public.subscriptions(status);

create trigger subscriptions_updated_at
before update on public.subscriptions
for each row execute function public.handle_updated_at();

-- Cuando se crea/actualiza una subscription activa, marcar profile como premium.
create or replace function public.handle_subscription_change()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status in ('active','trialing') then
    update public.profiles
       set is_premium = true,
           premium_expires_at = new.current_period_end,
           scan_limit = null
     where id = new.user_id;
  else
    update public.profiles
       set is_premium = false,
           premium_expires_at = null,
           scan_limit = 5
     where id = new.user_id
       and id != auth.uid();   -- no pisar cambios manuales del propio admin
  end if;
  return new;
end;
$$;

create trigger subscriptions_upsert_profile
after insert or update on public.subscriptions
for each row execute function public.handle_subscription_change();

-- ============================================================================
-- ROW LEVEL SECURITY
--   Política: "Negar por defecto, abrir por necesidad"
-- ============================================================================
alter table public.profiles           enable row level security;
alter table public.shopping_lists     enable row level security;
alter table public.list_members       enable row level security;
alter table public.products           enable row level security;
alter table public.supermarkets       enable row level security;
alter table public.prices             enable row level security;
alter table public.list_items         enable row level security;
alter table public.scans              enable row level security;
alter table public.user_scan_limits   enable row level security;
alter table public.subscriptions      enable row level security;

-- Helper: ¿el usuario actual es admin?
create or replace function public.is_admin(uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.profiles where id = uid and role = 'admin');
$$;

-- Helper: ¿el usuario es miembro de la lista?
create or replace function public.is_list_member(lid uuid, uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.list_members
    where list_id = lid and user_id = uid
  );
$$;

-- ----- profiles -----
create policy "profiles_select_own_or_admin"
  on public.profiles for select
  using (auth.uid() = id or public.is_admin(auth.uid()));

create policy "profiles_update_own"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id and role = (select role from public.profiles where id = auth.uid()));
  -- ↑ el check evita que un user se auto-promocione a admin

create policy "profiles_admin_all"
  on public.profiles for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ----- shopping_lists -----
create policy "lists_select_member_or_admin"
  on public.shopping_lists for select
  using (public.is_list_member(id, auth.uid()) or public.is_admin(auth.uid()));

create policy "lists_insert_own"
  on public.shopping_lists for insert
  with check (auth.uid() = owner_id);

create policy "lists_update_owner_or_admin"
  on public.shopping_lists for update
  using (owner_id = auth.uid() or public.is_admin(auth.uid()))
  with check (owner_id = auth.uid() or public.is_admin(auth.uid()));

create policy "lists_delete_owner_or_admin"
  on public.shopping_lists for delete
  using (owner_id = auth.uid() or public.is_admin(auth.uid()));

-- ----- list_members -----
create policy "members_select_self_or_list_visible"
  on public.list_members for select
  using (
    user_id = auth.uid()
    or public.is_list_member(list_id, auth.uid())
    or public.is_admin(auth.uid())
  );

create policy "members_insert_owner_or_admin"
  on public.list_members for insert
  with check (
    exists(select 1 from public.shopping_lists where id = list_id and owner_id = auth.uid())
    or public.is_admin(auth.uid())
  );

create policy "members_delete_owner_or_admin_or_self"
  on public.list_members for delete
  using (
    user_id = auth.uid()
    or exists(select 1 from public.shopping_lists where id = list_id and owner_id = auth.uid())
    or public.is_admin(auth.uid())
  );

-- ----- products -----
-- Cualquier usuario autenticado puede leer (catálogo público).
create policy "products_select_authenticated"
  on public.products for select
  using (auth.role() = 'authenticated');

-- Crear producto: cualquier usuario autenticado (queda verified=false).
create policy "products_insert_authenticated"
  on public.products for insert
  with check (auth.uid() = created_by);

-- Actualizar: solo admin (o el creador si sigue sin verificar).
create policy "products_update_admin_or_creator_unverified"
  on public.products for update
  using (
    public.is_admin(auth.uid())
    or (created_by = auth.uid() and verified = false)
  )
  with check (
    public.is_admin(auth.uid())
    or (created_by = auth.uid() and verified = false)
  );

create policy "products_delete_admin"
  on public.products for delete
  using (public.is_admin(auth.uid()));

-- ----- supermarkets -----
create policy "supermarkets_select_all"
  on public.supermarkets for select
  using (true);   -- público

create policy "supermarkets_write_admin"
  on public.supermarkets for all
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ----- prices -----
-- Lectura pública (es info que beneficia al usuario para comparar).
create policy "prices_select_all"
  on public.prices for select
  using (true);

-- Cualquier usuario autenticado puede reportar un precio.
create policy "prices_insert_authenticated"
  on public.prices for insert
  with check (auth.uid() = reported_by);

create policy "prices_update_admin"
  on public.prices for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create policy "prices_delete_admin"
  on public.prices for delete
  using (public.is_admin(auth.uid()));

-- ----- list_items -----
create policy "items_select_list_member"
  on public.list_items for select
  using (public.is_list_member(list_id, auth.uid()));

create policy "items_insert_list_member"
  on public.list_items for insert
  with check (public.is_list_member(list_id, auth.uid()));

create policy "items_update_list_member"
  on public.list_items for update
  using (public.is_list_member(list_id, auth.uid()))
  with check (public.is_list_member(list_id, auth.uid()));

create policy "items_delete_list_member"
  on public.list_items for delete
  using (public.is_list_member(list_id, auth.uid()));

-- ----- scans -----
create policy "scans_select_own_or_admin"
  on public.scans for select
  using (user_id = auth.uid() or public.is_admin(auth.uid()));

create policy "scans_insert_own"
  on public.scans for insert
  with check (user_id = auth.uid());

create policy "scans_update_admin"
  on public.scans for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ----- user_scan_limits -----
create policy "scan_limits_select_own_or_admin"
  on public.user_scan_limits for select
  using (user_id = auth.uid() or public.is_admin(auth.uid()));

create policy "scan_limits_insert_own"
  on public.user_scan_limits for insert
  with check (user_id = auth.uid());

create policy "scan_limits_update_own"
  on public.user_scan_limits for update
  using (user_id = auth.uid() or public.is_admin(auth.uid()))
  with check (user_id = auth.uid() or public.is_admin(auth.uid()));

-- ----- subscriptions -----
create policy "subs_select_own_or_admin"
  on public.subscriptions for select
  using (user_id = auth.uid() or public.is_admin(auth.uid()));

-- Solo service_role (Edge Functions de Stripe) puede escribir.
-- No creamos policy de write → por defecto nadie puede.

-- ============================================================================
-- FUNCTIONS: expuestas vía RPC (uso desde cliente sin saltarse RLS)
-- ============================================================================

-- increment_scan_count: atómico y respeta el límite del usuario.
-- Devuelve true si se contabilizó; false si excedió el límite.
create or replace function public.increment_scan_count(
  p_user_id uuid,
  p_month   date
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limit integer;
  v_count integer;
begin
  -- Limitar al usuario autenticado si está disponible
  if auth.uid() is not null and auth.uid() <> p_user_id then
    raise exception 'No autorizado';
  end if;

  select scan_limit into v_limit from public.profiles where id = p_user_id;
  -- premium (scan_limit is null) → siempre true
  if v_limit is null then
    insert into public.user_scan_limits (user_id, month, scan_count)
    values (p_user_id, p_month, 1)
    on conflict (user_id, month)
      do update set scan_count = public.user_scan_limits.scan_count + 1;
    return true;
  end if;

  select scan_count into v_count
    from public.user_scan_limits
    where user_id = p_user_id and month = p_month;
  v_count := coalesce(v_count, 0);

  if v_count >= v_limit then
    return false;
  end if;

  insert into public.user_scan_limits (user_id, month, scan_count)
  values (p_user_id, p_month, v_count + 1)
  on conflict (user_id, month)
    do update set scan_count = public.user_scan_limits.scan_count + 1;
  return true;
end;
$$;

grant execute on function public.increment_scan_count(uuid, date) to authenticated;

-- join_list_by_token: añadir al usuario actual como miembro de una lista
-- a partir de su share_token.
create or replace function public.join_list_by_token(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_list_id uuid;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'No autenticado';
  end if;

  select id into v_list_id
    from public.shopping_lists
    where share_token = p_token and archived_at is null;

  if v_list_id is null then
    raise exception 'Token inválido o lista archivada';
  end if;

  insert into public.list_members (list_id, user_id, role)
  values (v_list_id, v_user_id, 'editor')
  on conflict do nothing;

  return v_list_id;
end;
$$;

grant execute on function public.join_list_by_token(text) to authenticated;

-- ============================================================================
-- VIEWS: listos para la UI
-- ============================================================================
-- Vista de "mis listas" con info de miembros
create or replace view public.my_lists as
select
  sl.id,
  sl.name,
  sl.owner_id,
  sl.share_token,
  sl.archived_at,
  sl.created_at,
  sl.updated_at,
  (select count(*) from public.list_items li where li.list_id = sl.id) as item_count,
  (select count(*) from public.list_items li where li.list_id = sl.id and not li.is_purchased) as pending_count,
  lm.role as my_role
from public.shopping_lists sl
join public.list_members lm on lm.list_id = sl.id
where lm.user_id = auth.uid();

-- ============================================================================
-- GRANTs (Supabase predefine roles anon, authenticated, service_role)
-- ============================================================================
grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to authenticated, service_role;
grant all on all sequences in schema public to authenticated, service_role;
grant select on public.my_lists to authenticated;

-- anon solo necesita signup/login → no grants a tablas
-- service_role (usado por Edge Functions) tiene all arriba
-- ============================================================================
-- pepa · 0002 · Rellena automáticamente owner_id, added_by, user_id
-- desde auth.uid() en INSERT para que la app cliente no tenga que preocuparse.
-- Mantiene la RLS estricta (auth.uid() = owner_id en WITH CHECK).
-- ============================================================================

-- shopping_lists: rellena owner_id si falta
create or replace function public.fill_shopping_list_owner()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.owner_id is null then
    new.owner_id := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists fill_shopping_list_owner_trigger on public.shopping_lists;
create trigger fill_shopping_list_owner_trigger
before insert on public.shopping_lists
for each row execute function public.fill_shopping_list_owner();

-- list_items: rellena added_by si falta
create or replace function public.fill_list_item_added_by()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.added_by is null then
    new.added_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists fill_list_item_added_by_trigger on public.list_items;
create trigger fill_list_item_added_by_trigger
before insert on public.list_items
for each row execute function public.fill_list_item_added_by();

-- scans: rellena user_id si falta
create or replace function public.fill_scan_user_id()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is null then
    new.user_id := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists fill_scan_user_id_trigger on public.scans;
create trigger fill_scan_user_id_trigger
before insert on public.scans
for each row execute function public.fill_scan_user_id();

-- prices: rellena reported_by si falta
create or replace function public.fill_price_reported_by()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.reported_by is null then
    new.reported_by := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists fill_price_reported_by_trigger on public.prices;
create trigger fill_price_reported_by_trigger
before insert on public.prices
for each row execute function public.fill_price_reported_by();
-- ============================================================================
-- pepa · Seed de datos demo
-- Ejecutar después de 0001_initial_schema.sql
-- Útil para tener algo que mostrar en la beta del 5 de julio
-- ============================================================================

-- Supermercados españoles típicos
insert into public.supermarkets (name, chain) values
  ('Mercadona Centro',  'Mercadona'),
  ('Mercadona Norte',   'Mercadona'),
  ('Carrefour Plaza',   'Carrefour'),
  ('Carrefour Express', 'Carrefour'),
  ('Lidl',              'Lidl'),
  ('Dia',               'Dia'),
  ('Consum',            'Consum'),
  ('Alcampo',           'Alcampo'),
  ('El Corte Inglés',   'El Corte Inglés'),
  ('Eroski',            'Eroski')
on conflict do nothing;

-- Productos demo para que el comparador tenga datos en beta
insert into public.products (ean, name, brand, category, verified, unit, unit_quantity, standard_unit, image_url) values
  ('8410000000017', 'Aceite de Oliva Virgen Extra 1L',         'La Española',  'Aceite',         true, 'L',     1.000, 'L',     null),
  ('8410000000024', 'Aceite de Oliva Suave 1L',                 'Carbonell',    'Aceite',         true, 'L',     1.000, 'L',     null),
  ('8410000000031', 'Aceite de Girasol 1L',                     'Koipe',        'Aceite',         true, 'L',     1.000, 'L',     null),
  ('8410000000048', 'Leche entera 1L',                          'Pascual',      'Lácteos',        true, 'L',     1.000, 'L',     null),
  ('8410000000055', 'Leche semidesnatada 1L',                   'Pascual',      'Lácteos',        true, 'L',     1.000, 'L',     null),
  ('8410000000062', 'Leche desnatada 1L',                       'President',    'Lácteos',        true, 'L',     1.000, 'L',     null),
  ('8410000000079', 'Arroz redondo 1kg',                        'SOS',          'Arroz/Pasta',    true, 'kg',    1.000, 'kg',    null),
  ('8410000000086', 'Pasta espaguetis 500g',                    'Barilla',      'Arroz/Pasta',    true, 'kg',    0.500, 'kg',    null),
  ('8410000000093', 'Macarrones 500g',                          'Gallo',        'Arroz/Pasta',    true, 'kg',    0.500, 'kg',    null),
  ('8410000000109', 'Pan de molde integral',                    'Bimbo',        'Panadería',      true, 'unit',  1.000, 'unit',  null),
  ('8410000000116', 'Huevos clase M caja 12',                   'Mercadona',    'Huevos',         true, 'unit',  12.000,'unit',  null),
  ('8410000000123', 'Azúcar blanco 1kg',                        'Azucarera',    'Despensa',       true, 'kg',    1.000, 'kg',    null),
  ('8410000000130', 'Sal fina 1kg',                             'Clemensa',     'Despensa',       true, 'kg',    1.000, 'kg',    null),
  ('8410000000147', 'Café molido natural 250g',                 'Marcilla',     'Despensa',       true, 'kg',    0.250, 'kg',    null),
  ('8410000000154', 'Tomate frito bote 400g',                   'Orlando',      'Conservas',      true, 'kg',    0.400, 'kg',    null),
  ('8410000000161', 'Atún en aceite de oliva lata 80g',         'Calvo',        'Conservas',      true, 'kg',    0.080, 'kg',    null),
  ('8410000000178', 'Garbanzos bote 400g',                      'Luengo',       'Conservas',      true, 'kg',    0.400, 'kg',    null),
  ('8410000000185', 'Judías verdes bote 400g',                  'Carrefour',    'Conservas',      true, 'kg',    0.400, 'kg',    null),
  ('8410000000192', 'Detergente líquido 30 lavados 1.5L',       'Skip',         'Limpieza',       true, 'L',     1.500, 'L',     null),
  ('8410000000208', 'Papel higiénico 12 rollos',                'Scottex',      'Limpieza',       true, 'unit',  12.000,'unit',  null),
  ('8410000000215', 'Detergente lavavajillas 1kg',              'Fairy',        'Limpieza',       true, 'kg',    1.000, 'kg',    null),
  ('8410000000222', 'Champú 750ml',                             'Pantene',      'Higiene',        true, 'L',     0.750, 'L',     null),
  ('8410000000239', 'Gel de ducha 750ml',                       'Dove',         'Higiene',        true, 'L',     0.750, 'L',     null),
  ('8410000000246', 'Pasta de dientes 75ml',                    'Colgate',      'Higiene',        true, 'L',     0.075, 'L',     null),
  ('8410000000253', 'Manzanas Golden 1kg',                      'Generic',      'Fruta',          true, 'kg',    1.000, 'kg',    null),
  ('8410000000260', 'Plátanos 1kg',                             'Generic',      'Fruta',          true, 'kg',    1.000, 'kg',    null),
  ('8410000000277', 'Tomates 1kg',                              'Generic',      'Verdura',        true, 'kg',    1.000, 'kg',    null),
  ('8410000000284', 'Patatas 1kg',                              'Generic',      'Verdura',        true, 'kg',    1.000, 'kg',    null),
  ('8410000000291', 'Cebolla 1kg',                              'Generic',      'Verdura',        true, 'kg',    1.000, 'kg',    null),
  ('8410000000307', 'Pollo entero 1.5kg',                       'Generic',      'Carne',          true, 'kg',    1.500, 'kg',    null)
on conflict (ean) do nothing;

-- Precios demo por supermercado y producto (subset para probar comparador)
-- Aceite de Oliva Virgen Extra 1L
insert into public.prices (product_id, supermarket_id, price, is_offer)
select p.id, s.id,
       case s.chain
         when 'Mercadona' then 9.85
         when 'Carrefour' then 10.50
         when 'Lidl'      then 9.20
         when 'Dia'       then 9.95
         when 'Consum'    then 10.10
         when 'Alcampo'   then 9.75
         when 'El Corte Inglés' then 11.20
         when 'Eroski'    then 10.05
         else 10.00
       end,
       case when s.chain in ('Lidl','Alcampo') then true else false end
from public.products p
cross join public.supermarkets s
where p.ean = '8410000000017'
on conflict do nothing;

-- Leche entera 1L
insert into public.prices (product_id, supermarket_id, price, is_offer)
select p.id, s.id,
       case s.chain
         when 'Mercadona' then 1.15
         when 'Carrefour' then 1.25
         when 'Lidl'      then 1.05
         when 'Dia'       then 1.20
         when 'Consum'    then 1.18
         when 'Alcampo'   then 1.10
         when 'El Corte Inglés' then 1.35
         when 'Eroski'    then 1.22
         else 1.20
       end,
       false
from public.products p
cross join public.supermarkets s
where p.ean = '8410000000048'
on conflict do nothing;

-- Arroz 1kg
insert into public.prices (product_id, supermarket_id, price)
select p.id, s.id,
       case s.chain
         when 'Mercadona' then 1.55
         when 'Carrefour' then 1.69
         when 'Lidl'      then 1.39
         when 'Dia'       then 1.60
         else 1.65
       end
from public.products p
cross join public.supermarkets s
where p.ean = '8410000000079'
on conflict do nothing;

-- Huevos 12 unidades
insert into public.prices (product_id, supermarket_id, price)
select p.id, s.id,
       case s.chain
         when 'Mercadona' then 2.95
         when 'Carrefour' then 3.25
         when 'Lidl'      then 2.75
         when 'Dia'       then 3.05
         else 3.10
       end
from public.products p
cross join public.supermarkets s
where p.ean = '8410000000116'
on conflict do nothing;
