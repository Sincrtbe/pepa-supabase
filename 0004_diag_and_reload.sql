-- ============================================================================
-- pepa · 0004 · Diagnóstico + schema reload
-- Muestra qué policies existen realmente y fuerza al PostgREST a recargar
-- su schema cache.
-- ============================================================================

-- 1. Forzar reload del schema cache de PostgREST
NOTIFY pgrst, 'reload schema';

-- 2. Listar las policies actuales en las tablas clave
do $$
declare
  r record;
begin
  raise notice '=== POLICIES EN DB ===';
  for r in (
    select tablename, policyname, cmd,
           (select string_agg(qual, ' / ')
            from unnest(coalesce(permissive_qual, array[]::text[])) as qual) as using_clause,
           (select string_agg(with_check, ' / ')
            from unnest(coalesce(with_check_qual, array[]::text[])) as with_check) as check_clause
    from pg_policies
    where schemaname = 'public'
      and tablename in ('shopping_lists','list_members','list_items','scans','prices','products','profiles','supermarkets','user_scan_limits','subscriptions')
    order by tablename, cmd, policyname
  ) loop
    raise notice '%.% [%] USING=(%) CHECK=(%)',
      r.tablename, r.policyname, r.cmd,
      coalesce(r.using_clause,'-'), coalesce(r.check_clause,'-');
  end loop;
end;
$$;

-- 3. Listar los triggers actuales en tablas clave
do $$
declare
  r record;
begin
  raise notice '=== TRIGGERS EN DB ===';
  for r in (
    select tgrelid::regclass::text as tabla, tgname as trigger,
           tgtype, tgenabled
    from pg_trigger
    where not tgisinternal
      and tgrelid::regclass::text like 'public.%'
    order by tgrelid::regclass::text, tgname
  ) loop
    raise notice '%.% [%] enabled=%', r.tabla, r.trigger, r.tgtype, r.tgenabled;
  end loop;
end;
$$;
