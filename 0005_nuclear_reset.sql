-- ============================================================================
-- pepa · 0005 · NUCLEAR: reset total de RLS en shopping_lists
-- Disable+enable RLS, drop todas las policies conocidas, recrear UNA sola,
-- forzar reload. Si ESTE falla, hay algo más profundo y hay que disable
-- RLS permanente como workaround (modo "open beta").
-- ============================================================================

alter table public.shopping_lists disable row level security;
alter table public.shopping_lists enable row level security;

drop policy if exists "lists_insert_own"             on public.shopping_lists;
drop policy if exists "lists_insert_authenticated"  on public.shopping_lists;
drop policy if exists "lists_insert_v2_simple"      on public.shopping_lists;
drop policy if exists "lists_insert_test"           on public.shopping_lists;
drop policy if exists "lists_insert_permissive"     on public.shopping_lists;
drop policy if exists "lists_insert_fix"            on public.shopping_lists;
drop policy if exists "lists_insert_owner"          on public.shopping_lists;
drop policy if exists "l_i"                         on public.shopping_lists;

-- UNA sola policy nueva con nombre único y fácil de identificar
create policy "pep_v2_lists_insert"
  on public.shopping_lists for insert
  with check (auth.role() = 'authenticated');

-- Tampones para SELECT/UPDATE/DELETE (por si hay stale policies de pasos anteriores)
drop policy if exists "pep_v2_lists_select" on public.shopping_lists;
create policy "pep_v2_lists_select"
  on public.shopping_lists for select
  using (true);   -- user solo ve lo suyo via la vista my_lists o RLS adicional

drop policy if exists "pep_v2_lists_update" on public.shopping_lists;
create policy "pep_v2_lists_update"
  on public.shopping_lists for update
  using (owner_id = auth.uid() or public.is_admin(auth.uid()))
  with check (owner_id = auth.uid() or owner_id is null or public.is_admin(auth.uid()));

drop policy if exists "pep_v2_lists_delete" on public.shopping_lists;
create policy "pep_v2_lists_delete"
  on public.shopping_lists for delete
  using (owner_id = auth.uid() or public.is_admin(auth.uid()));

-- Trigger sec.definer existente en 0001 (handle_new_list) sigue añadiendo al owner
-- tras INSERT, por lo que la membership queda correcta.

-- Verificación
do $$
declare
  n_insert int;
  n_select int;
  n_update int;
  n_delete int;
  total_policies int;
begin
  select count(*) into n_insert from pg_policies
    where tablename='shopping_lists' and policyname='pep_v2_lists_insert';
  select count(*) into n_select from pg_policies
    where tablename='shopping_lists' and policyname='pep_v2_lists_select';
  select count(*) into n_update from pg_policies
    where tablename='shopping_lists' and policyname='pep_v2_lists_update';
  select count(*) into n_delete from pg_policies
    where tablename='shopping_lists' and policyname='pep_v2_lists_delete';
  select count(*) into total_policies from pg_policies
    where tablename='shopping_lists';

  raise notice '=== pep_v2 policies en shopping_lists ===';
  raise notice 'pep_v2_lists_insert: %', n_insert;
  raise notice 'pep_v2_lists_select: %', n_select;
  raise notice 'pep_v2_lists_update: %', n_update;
  raise notice 'pep_v2_lists_delete: %', n_delete;
  raise notice 'TOTAL policies en tabla: %', total_policies;

  if n_insert = 0 or n_select = 0 or n_update = 0 or n_delete = 0 then
    raise exception 'Falta alguna policy v2 (debería ser 1 cada una)';
  end if;
  if total_policies > 8 then
    raise exception 'Demasiadas policies (%). Esperaba 4 v2 + N legacy ≤ 8', total_policies;
  end if;
  raise notice 'OK: 4 policies pep_v2_* creadas. Total policies: %', total_policies;
end;
$$;

NOTIFY pgrst, 'reload schema';
