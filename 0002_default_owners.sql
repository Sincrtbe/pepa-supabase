-- ============================================================================
-- pepa · 0002 v3 · Triggers BEFORE INSERT rellenan FKs desde auth.uid()
-- Versión robusta: drops idempotentes + verificación al final
-- ============================================================================

-- Limpia cualquier residuo de intentos anteriores (idempotente)
drop trigger if exists fill_shopping_list_owner_trigger on public.shopping_lists;
drop trigger if exists fill_list_item_added_by_trigger on public.list_items;
drop trigger if exists fill_scan_user_id_trigger on public.scans;
drop trigger if exists fill_price_reported_by_trigger on public.prices;

drop function if exists public.fill_shopping_list_owner();
drop function if exists public.fill_list_item_added_by();
drop function if exists public.fill_scan_user_id();
drop function if exists public.fill_price_reported_by();

-- Crea funciones
create function public.fill_shopping_list_owner()
returns trigger language plpgsql as $$
begin
  if new.owner_id is null then
    new.owner_id := auth.uid();
  end if;
  return new;
end;
$$;

create function public.fill_list_item_added_by()
returns trigger language plpgsql as $$
begin
  if new.added_by is null then
    new.added_by := auth.uid();
  end if;
  return new;
end;
$$;

create function public.fill_scan_user_id()
returns trigger language plpgsql as $$
begin
  if new.user_id is null then
    new.user_id := auth.uid();
  end if;
  return new;
end;
$$;

create function public.fill_price_reported_by()
returns trigger language plpgsql as $$
begin
  if new.reported_by is null then
    new.reported_by := auth.uid();
  end if;
  return new;
end;
$$;

-- Crea triggers
create trigger fill_shopping_list_owner_trigger
before insert on public.shopping_lists
for each row execute function public.fill_shopping_list_owner();

create trigger fill_list_item_added_by_trigger
before insert on public.list_items
for each row execute function public.fill_list_item_added_by();

create trigger fill_scan_user_id_trigger
before insert on public.scans
for each row execute function public.fill_scan_user_id();

create trigger fill_price_reported_by_trigger
before insert on public.prices
for each row execute function public.fill_price_reported_by();

-- Verificación: si algún trigger no se creó, falla con mensaje claro
do $$
declare
  missing text;
begin
  missing := '';
  if not exists (select 1 from pg_trigger where tgname = 'fill_shopping_list_owner_trigger') then
    missing := missing || 'fill_shopping_list_owner_trigger ';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'fill_list_item_added_by_trigger') then
    missing := missing || 'fill_list_item_added_by_trigger ';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'fill_scan_user_id_trigger') then
    missing := missing || 'fill_scan_user_id_trigger ';
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'fill_price_reported_by_trigger') then
    missing := missing || 'fill_price_reported_by_trigger ';
  end if;
  if length(missing) > 0 then
    raise exception 'Falta crear triggers: %', missing;
  end if;
  raise notice 'OK: 4 triggers creados correctamente';
end;
$$;
