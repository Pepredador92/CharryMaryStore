alter table public.support_requests
  add column customer_last_read_at timestamptz null;

create index ix_support_messages__request_direction_sent_at
  on public.support_messages (support_request_id, direction, sent_at desc);

create function private.customer_support_conversations(
  p_request_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_personal_account_id uuid;
  v_result jsonb;
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  select personal_account.id
  into v_personal_account_id
  from public.personal_accounts personal_account
  where personal_account.auth_user_id = auth.uid()
    and personal_account.status = 'active'
  limit 1;

  if v_personal_account_id is null then
    raise exception 'Personal Account is not available';
  end if;

  if p_request_id is null then
    select pg_catalog.coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(request_row)
        || pg_catalog.jsonb_build_object(
          'last_message_at', (
            select pg_catalog.max(message.sent_at)
            from public.support_messages message
            where message.support_request_id = request_row.id
          ),
          'last_message_preview', (
            select pg_catalog.left(message.body, 120)
            from public.support_messages message
            where message.support_request_id = request_row.id
            order by message.sent_at desc
            limit 1
          ),
          'unread_count', (
            select pg_catalog.count(*)
            from public.support_messages message
            where message.support_request_id = request_row.id
              and message.direction = 'outgoing'
              and message.channel = 'internal'
              and message.sent_at > pg_catalog.coalesce(
                request_row.customer_last_read_at,
                request_row.opened_at
              )
          )
        )
        order by pg_catalog.coalesce(
          (
            select pg_catalog.max(message.sent_at)
            from public.support_messages message
            where message.support_request_id = request_row.id
          ),
          request_row.opened_at
        ) desc
      ),
      '[]'::jsonb
    )
    into v_result
    from public.support_requests request_row
    where request_row.personal_account_id = v_personal_account_id
      and request_row.deleted_at is null;

    return v_result;
  end if;

  update public.support_requests request_row
  set customer_last_read_at = v_now
  where request_row.id = p_request_id
    and request_row.personal_account_id = v_personal_account_id
    and request_row.deleted_at is null;

  if not found then
    raise exception 'Support conversation does not exist or is not accessible';
  end if;

  select pg_catalog.jsonb_build_object(
    'request', pg_catalog.to_jsonb(request_row),
    'messages', pg_catalog.coalesce((
      select pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(message)
        order by message.sent_at
      )
      from public.support_messages message
      where message.support_request_id = request_row.id
        and message.channel = 'internal'
    ), '[]'::jsonb)
  )
  into v_result
  from public.support_requests request_row
  where request_row.id = p_request_id
    and request_row.personal_account_id = v_personal_account_id
    and request_row.deleted_at is null;

  return v_result;
end;
$$;

revoke all on function private.customer_support_conversations(uuid) from PUBLIC;
revoke all on function private.customer_support_conversations(uuid) from anon;
revoke all on function private.customer_support_conversations(uuid) from authenticated;
grant execute on function private.customer_support_conversations(uuid) to authenticated;

create function public.customer_support_conversations(
  p_request_id uuid default null
)
returns jsonb
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.customer_support_conversations(p_request_id)
$$;

revoke all on function public.customer_support_conversations(uuid) from PUBLIC;
revoke all on function public.customer_support_conversations(uuid) from anon;
revoke all on function public.customer_support_conversations(uuid) from authenticated;
grant execute on function public.customer_support_conversations(uuid) to authenticated;

create function private.customer_support_unread_count()
returns integer
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  v_personal_account_id uuid;
  v_count integer;
begin
  if auth.uid() is null then
    return 0;
  end if;

  select personal_account.id
  into v_personal_account_id
  from public.personal_accounts personal_account
  where personal_account.auth_user_id = auth.uid()
    and personal_account.status = 'active'
  limit 1;

  if v_personal_account_id is null then
    return 0;
  end if;

  select pg_catalog.count(*)::integer
  into v_count
  from public.support_messages message
  join public.support_requests request_row
    on request_row.id = message.support_request_id
  where request_row.personal_account_id = v_personal_account_id
    and request_row.deleted_at is null
    and message.direction = 'outgoing'
    and message.channel = 'internal'
    and message.sent_at > pg_catalog.coalesce(
      request_row.customer_last_read_at,
      request_row.opened_at
    );

  return v_count;
end;
$$;

revoke all on function private.customer_support_unread_count() from PUBLIC;
revoke all on function private.customer_support_unread_count() from anon;
revoke all on function private.customer_support_unread_count() from authenticated;
grant execute on function private.customer_support_unread_count() to authenticated;

create function public.customer_support_unread_count()
returns integer
language sql
stable
security invoker
set search_path = pg_catalog
as $$
  select private.customer_support_unread_count()
$$;

revoke all on function public.customer_support_unread_count() from PUBLIC;
revoke all on function public.customer_support_unread_count() from anon;
revoke all on function public.customer_support_unread_count() from authenticated;
grant execute on function public.customer_support_unread_count() to authenticated;

create function private.customer_send_support_message(
  p_request_id uuid,
  p_body text
)
returns uuid
language plpgsql
volatile
security definer
set search_path = pg_catalog
as $$
declare
  v_personal_account_id uuid;
  v_request public.support_requests%rowtype;
  v_message_id uuid := pg_catalog.gen_random_uuid();
  v_now timestamptz := pg_catalog.clock_timestamp();
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  if nullif(pg_catalog.btrim(p_body), '') is null
    or pg_catalog.char_length(pg_catalog.btrim(p_body)) > 4000 then
    raise exception 'Message is required and must not exceed 4000 characters';
  end if;

  select personal_account.id
  into v_personal_account_id
  from public.personal_accounts personal_account
  where personal_account.auth_user_id = auth.uid()
    and personal_account.status = 'active'
  limit 1;

  if v_personal_account_id is null then
    raise exception 'Personal Account is not available';
  end if;

  select *
  into v_request
  from public.support_requests request_row
  where request_row.id = p_request_id
    and request_row.personal_account_id = v_personal_account_id
    and request_row.deleted_at is null
  for update;

  if not found then
    raise exception 'Support conversation does not exist or is not accessible';
  end if;
  if v_request.status = 'closed' then
    raise exception 'Closed support conversation cannot receive messages';
  end if;

  insert into public.support_messages (
    id,
    support_request_id,
    direction,
    author_kind,
    body,
    channel,
    is_sensitive,
    sent_at
  ) values (
    v_message_id,
    p_request_id,
    'incoming',
    'customer',
    pg_catalog.btrim(p_body),
    'internal',
    false,
    v_now
  );

  update public.support_requests request_row
  set status = case
        when request_row.status = 'resolved' then 'in_attention'
        else request_row.status
      end,
      customer_last_read_at = v_now,
      updated_at = v_now
  where request_row.id = p_request_id;

  return v_message_id;
end;
$$;

revoke all on function private.customer_send_support_message(uuid, text) from PUBLIC;
revoke all on function private.customer_send_support_message(uuid, text) from anon;
revoke all on function private.customer_send_support_message(uuid, text) from authenticated;
grant execute on function private.customer_send_support_message(uuid, text) to authenticated;

create function public.customer_send_support_message(
  p_request_id uuid,
  p_body text
)
returns uuid
language sql
volatile
security invoker
set search_path = pg_catalog
as $$
  select private.customer_send_support_message(p_request_id, p_body)
$$;

revoke all on function public.customer_send_support_message(uuid, text) from PUBLIC;
revoke all on function public.customer_send_support_message(uuid, text) from anon;
revoke all on function public.customer_send_support_message(uuid, text) from authenticated;
grant execute on function public.customer_send_support_message(uuid, text) to authenticated;
