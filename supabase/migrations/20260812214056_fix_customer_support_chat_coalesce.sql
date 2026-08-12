create or replace function private.customer_support_conversations(
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
    select coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.to_jsonb(request_row)
        || pg_catalog.jsonb_build_object(
          'last_message_at', message_summary.last_message_at,
          'last_message_preview', message_summary.last_message_preview,
          'unread_count', message_summary.unread_count
        )
        order by coalesce(message_summary.last_message_at, request_row.opened_at) desc
      ),
      '[]'::jsonb
    )
    into v_result
    from public.support_requests request_row
    left join lateral (
      select
        pg_catalog.max(message.sent_at) as last_message_at,
        (
          pg_catalog.array_agg(message.body order by message.sent_at desc)
        )[1] as last_message_preview,
        pg_catalog.count(*) filter (
          where message.direction = 'outgoing'
            and message.channel = 'internal'
            and message.sent_at > coalesce(
              request_row.customer_last_read_at,
              request_row.opened_at
            )
        ) as unread_count
      from public.support_messages message
      where message.support_request_id = request_row.id
    ) message_summary on true
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
    'messages', coalesce((
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

create or replace function private.customer_support_unread_count()
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
    and message.sent_at > coalesce(
      request_row.customer_last_read_at,
      request_row.opened_at
    );

  return v_count;
end;
$$;
