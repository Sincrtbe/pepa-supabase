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
