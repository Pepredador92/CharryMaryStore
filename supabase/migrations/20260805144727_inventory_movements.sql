create table public.inventory_movements (
  id uuid not null,
  presentation_id uuid not null,
  quantity_delta bigint not null,
  movement_kind text not null,
  order_id uuid null,
  actor_operational_person_id uuid null,
  cause text not null,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint pk_inventory_movements primary key (id),
  constraint fk_inventory_movements__sellable_presentations foreign key (presentation_id) references public.sellable_presentations (id) on delete restrict,
  constraint fk_inventory_movements__orders foreign key (order_id) references public.orders (id) on delete restrict,
  constraint fk_inventory_movements__operational_people foreign key (actor_operational_person_id) references public.operational_people (id) on delete restrict,
  constraint ck_inventory_movements__quantity_delta_nonzero check (quantity_delta <> 0),
  constraint ck_inventory_movements__movement_kind check (
    movement_kind in ('stock_entry', 'manual_adjustment', 'order_decrement', 'order_compensation')
  ),
  constraint ck_inventory_movements__stock_entry check (
    movement_kind <> 'stock_entry'
    or (quantity_delta > 0 and order_id is null)
  ),
  constraint ck_inventory_movements__manual_adjustment check (
    movement_kind <> 'manual_adjustment'
    or order_id is null
  ),
  constraint ck_inventory_movements__order_decrement check (
    movement_kind <> 'order_decrement'
    or (quantity_delta < 0 and order_id is not null)
  ),
  constraint ck_inventory_movements__order_compensation check (
    movement_kind <> 'order_compensation'
    or (quantity_delta > 0 and order_id is not null)
  )
);

create index ix_inventory_movements__presentation_id
  on public.inventory_movements (presentation_id);

create index ix_inventory_movements__order_id
  on public.inventory_movements (order_id)
  where order_id is not null;

create index ix_inventory_movements__actor_operational_person_id
  on public.inventory_movements (actor_operational_person_id)
  where actor_operational_person_id is not null;

create index ix_inventory_movements__occurred_at
  on public.inventory_movements (occurred_at);
