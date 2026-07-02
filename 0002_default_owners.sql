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
