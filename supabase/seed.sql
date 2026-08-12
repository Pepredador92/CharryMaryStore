insert into public.capabilities (
  id,
  code,
  name,
  description,
  is_active
)
values
  (
    '78150cfd-c579-5f90-beb3-0cdbdc1ce61f',
    'catalog.read',
    'Consultar catálogo',
    null,
    true
  ),
  (
    'f4d9df74-f443-5772-a66e-9383d3b9be3f',
    'catalog.manage',
    'Administrar catálogo',
    null,
    true
  ),
  (
    '526fbce4-e3fb-5cb3-80ad-a7c4f0e60988',
    'inventory.read',
    'Consultar inventario',
    null,
    true
  ),
  (
    '1cb3680c-bb11-5e4d-b936-d8432e733e13',
    'inventory.adjust',
    'Ajustar inventario',
    null,
    true
  ),
  (
    '89eefa17-4bbc-5ab0-a97a-688325a4a420',
    'access.read',
    'Consultar accesos',
    null,
    true
  ),
  (
    '9d11be5b-dacb-5d89-8ef2-5d572184f769',
    'access.manage',
    'Administrar accesos',
    null,
    true
  ),
  (
    '1ca315d8-15f5-50ee-b968-628fdb2c0ae0',
    'orders.read',
    'Consultar pedidos',
    null,
    true
  ),
  (
    '438e6762-964b-5b4f-9bca-4956985ec8e3',
    'orders.manage',
    'Administrar pedidos',
    null,
    true
  ),
  (
    'df398d4f-2e15-526f-b6c2-5d3fdc68e107',
    'preparation.read',
    'Consultar preparación',
    null,
    true
  ),
  (
    '174c9b68-bdd7-5fbd-8886-44c59fe5086d',
    'preparation.operate',
    'Operar preparación',
    null,
    true
  ),
  (
    'fd3a3895-0a0e-58b6-9939-48a3b8f7d865',
    'preparation.manage',
    'Administrar preparación',
    null,
    true
  ),
  (
    '744d06e2-c0f2-5149-9a5f-6b98100d97ee',
    'delivery.read',
    'Consultar entregas',
    null,
    true
  ),
  (
    '324c01a1-7d4f-5b7e-bcff-a65cbb67cf8c',
    'delivery.operate',
    'Operar entregas',
    null,
    true
  ),
  (
    'fe2547ca-7cc6-55e6-8b7c-8e59cf4400ca',
    'delivery.manage',
    'Administrar entregas',
    null,
    true
  ),
  (
    '7d39065a-480c-5266-a755-beb4463651cf',
    'audit.read',
    'Consultar auditoría',
    null,
    true
  ),
  (
    '7c74e536-c425-5581-9892-9448b46faf6e',
    'delivery_evidence.read',
    'Consultar evidencia de entrega',
    null,
    true
  ),
  (
    '79bb59e0-bd55-5349-98be-45a536ebc565',
    'delivery_evidence.manage',
    'Administrar evidencia de entrega',
    null,
    true
  ),
  (
    '1f7e790f-9fee-5ce4-b2c9-57d842ebacc9',
    'support.handle',
    'Atender solicitudes de atención',
    null,
    true
  ),
  (
    '98c1fc44-c193-5c76-abca-66582a9f08dd',
    'support.sensitive',
    'Acceder a atención sensible',
    null,
    true
  )
on conflict (code) do nothing;
