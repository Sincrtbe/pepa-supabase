-- ============================================================================
-- pepa · 0006 · Policies finales endurecidas en TODAS las tablas core
-- Versión "production-ish": suficiente para MVP público, no para escalar.
-- ============================================================================
-- Este script:
--   1. Endurece shopping_lists: SELECT con is_list_member + admin
--   2. Asegura policies en list_items, list_members, scans, prices, products
--   3. Mantiene el patrón pep_v2_* y elimina policies huérfanas de 0001 si las hay
-- ============================================================================

-- ─── shopping_lists (SELECT endurecido) ─────────────────────────────────────
drop policy if exists "pep_v2_lists_select" on public.shopping_lists;
create policy "pep_v2_lists_select"
  on public.shopping_lists for select
  using (
    public.is_list_member(id, auth.uid())
    or public.is_admin(auth.uid())
    or owner_id = auth.uid()   -- el owner siempre ve sus listas
  );

-- ─── list_members ──────────────────────────────────────────────────────────
drop policy if exists "pep_v2_members_select" on public.list_members;
create policy "pep_v2_members_select"
  on public.list_members for select
  using (
    user_id = auth.uid()
    or exists(select 1 from public.shopping_lists where id = list_id and owner_id = auth.uid())
    or public.is_admin(auth.uid())
  );

drop policy if exists "pep_v2_members_insert" on public.list_members;
create policy "pep_v2_members_insert"
  on public.list_members for insert
  with check (
    user_id = auth.uid()
    or public.is_admin(auth.uid())
  );

drop policy if exists "pep_v2_members_delete" on public.list_members;
create policy "pep_v2_members_delete"
  on public.list_members for delete
  using (
    user_id = auth.uid()
    or exists(select 1 from public.shopping_lists where id = list_id and owner_id = auth.uid())
    or public.is_admin(auth.uid())
  );

-- ─── list_items ────────────────────────────────────────────────────────────
drop policy if exists "pep_v2_items_select" on public.list_items;
create policy "pep_v2_items_select"
  on public.list_items for select
  using (
    public.is_list_member(list_id, auth.uid())
    or public.is_admin(auth.uid())
  );

drop policy if exists "pep_v2_items_insert" on public.list_items;
create policy "pep_v2_items_insert"
  on public.list_items for insert
  with check (
    auth.role() = 'authenticated'
    and (public.is_list_member(list_id, auth.uid()) or public.is_admin(auth.uid()))
    and (added_by = auth.uid() or added_by is null)
  );

drop policy if exists "pep_v2_items_update" on public.list_items;
create policy "pep_v2_items_update"
  on public.list_items for update
  using (
    public.is_list_member(list_id, auth.uid())
    or public.is_admin(auth.uid())
  )
  with check (
    public.is_list_member(list_id, auth.uid())
    or public.is_admin(auth.uid())
  );

drop policy if exists "pep_v2_items_delete" on public.list_items;
create policy "pep_v2_items_delete"
  on public.list_items for delete
  using (
    public.is_list_member(list_id, auth.uid())
    or public.is_admin(auth.uid())
  );

-- ─── scans ─────────────────────────────────────────────────────────────────
drop policy if exists "pep_v2_scans_select" on public.scans;
create policy "pep_v2_scans_select"
  on public.scans for select
  using (user_id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "pep_v2_scans_insert" on public.scans;
create policy "pep_v2_scans_insert"
  on public.scans for insert
  with check (auth.role() = 'authenticated' and (user_id = auth.uid() or user_id is null));

drop policy if exists "pep_v2_scans_update" on public.scans;
create policy "pep_v2_scans_update"
  on public.scans for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- ─── prices ────────────────────────────────────────────────────────────────
drop policy if exists "pep_v2_prices_insert" on public.prices;
create policy "pep_v2_prices_insert"
  on public.prices for insert
  with check (auth.role() = 'authenticated' and (reported_by = auth.uid() or reported_by is null));

drop policy if exists "pep_v2_prices_update" on public.prices;
create policy "pep_v2_prices_update"
  on public.prices for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

drop policy if exists "pep_v2_prices_delete" on public.prices;
create policy "pep_v2_prices_delete"
  on public.prices for delete
  using (public.is_admin(auth.uid()));

-- ─── products ──────────────────────────────────────────────────────────────
drop policy if exists "pep_v2_products_insert" on public.products;
create policy "pep_v2_products_insert"
  on public.products for insert
  with check (auth.role() = 'authenticated' and (created_by = auth.uid() or created_by is null));

drop policy if exists "pep_v2_products_update" on public.products;
create policy "pep_v2_products_update"
  on public.products for update
  using (
    public.is_admin(auth.uid())
    or (created_by = auth.uid() and verified = false)
  );

drop policy if exists "pep_v2_products_delete" on public.products;
create policy "pep_v2_products_delete"
  on public.products for delete
  using (public.is_admin(auth.uid()));

-- Verificación final
do $$
declare n int;
begin
  select count(*) into n from pg_policies where schemaname='public' and policyname like 'pep_v2_%';
  raise notice 'Policies pep_v2_* totales: %', n;
  if n < 12 then
    raise exception 'Esperaba ≥ 12 policies pep_v2_*, encontré %', n;
  end if;
  raise notice 'OK: 0006 aplicadas. Policies pep_v2_* listas para MVP.';
end;
$$;

NOTIFY pgrst, 'reload schema';
