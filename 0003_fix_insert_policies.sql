-- ============================================================================
-- pepa · 0003 v2 · Re-crea las policies de INSERT que pueden no haberse
-- generado en la aplicación inicial + simplifica la de shopping_lists
-- para no depender de auth.uid() en el trigger BEFORE.
-- ============================================================================

-- ─── shopping_lists ────────────────────────────────────────────────────────
drop policy if exists "lists_insert_own"          on public.shopping_lists;
drop policy if exists "lists_insert_authenticated" on public.shopping_lists;

create policy "lists_insert_authenticated"
  on public.shopping_lists for insert
  with check (
    auth.role() = 'authenticated'
    -- Permitimos que el cliente envíe owner_id (que conoce de la sesión)
    -- o null (lo rellenará el trigger BEFORE INSERT si existe)
    and (auth.uid() = owner_id or owner_id is null)
  );

-- ─── list_members ──────────────────────────────────────────────────────────
drop policy if exists "members_insert_owner_or_admin" on public.list_members;
drop policy if exists "members_insert_authenticated"  on public.list_members;

create policy "members_insert_authenticated"
  on public.list_members for insert
  with check (
    auth.role() = 'authenticated'
    and (user_id = auth.uid() or public.is_admin(auth.uid()))
  );
-- Nota: el trigger handle_new_list añade al owner cuando se crea una lista.
-- Esta policy permite joins manuales (e.g. cuando un usuario acepta un token).

-- ─── list_items ───────────────────────────────────────────────────────────
drop policy if exists "items_insert_list_member"       on public.list_items;
drop policy if exists "items_insert_list_member_or_admin" on public.list_items;

create policy "items_insert_list_member_or_admin"
  on public.list_items for insert
  with check (
    auth.role() = 'authenticated'
    and (public.is_list_member(list_id, auth.uid()) or public.is_admin(auth.uid()))
    and (added_by = auth.uid() or added_by is null)
  );

-- ─── scans ─────────────────────────────────────────────────────────────────
drop policy if exists "scans_insert_own"          on public.scans;
drop policy if exists "scans_insert_authenticated" on public.scans;

create policy "scans_insert_authenticated"
  on public.scans for insert
  with check (
    auth.role() = 'authenticated'
    and (user_id = auth.uid() or user_id is null)
  );

-- ─── prices ────────────────────────────────────────────────────────────────
drop policy if exists "prices_insert_authenticated" on public.prices;

create policy "prices_insert_authenticated"
  on public.prices for insert
  with check (
    auth.role() = 'authenticated'
    and (reported_by = auth.uid() or reported_by is null)
  );

-- ─── products ─────────────────────────────────────────────────────────────
drop policy if exists "products_insert_authenticated" on public.products;

create policy "products_insert_authenticated"
  on public.products for insert
  with check (
    auth.role() = 'authenticated'
    and (created_by = auth.uid() or created_by is null)
  );

-- ─── Verificación ──────────────────────────────────────────────────────────
do $$
declare
  missing text;
begin
  missing := '';
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='shopping_lists' and policyname='lists_insert_authenticated'
  ) then missing := missing || 'lists_insert_authenticated '; end if;
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='list_members' and policyname='members_insert_authenticated'
  ) then missing := missing || 'members_insert_authenticated '; end if;
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='list_items' and policyname='items_insert_list_member_or_admin'
  ) then missing := missing || 'items_insert_list_member_or_admin '; end if;
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='scans' and policyname='scans_insert_authenticated'
  ) then missing := missing || 'scans_insert_authenticated '; end if;
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='prices' and policyname='prices_insert_authenticated'
  ) then missing := missing || 'prices_insert_authenticated '; end if;
  if not exists (
    select 1 from pg_policies
    where schemaname='public' and tablename='products' and policyname='products_insert_authenticated'
  ) then missing := missing || 'products_insert_authenticated '; end if;
  if length(missing) > 0 then
    raise exception 'Faltan policies: %', missing;
  end if;
  raise notice 'OK: 6 policies de INSERT creadas/actualizadas';
end;
$$;
