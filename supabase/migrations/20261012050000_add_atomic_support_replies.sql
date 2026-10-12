create or replace function public.admin_reply_support(
    p_thread_id uuid,
    p_sender_id uuid,
    p_body text
)
returns table (user_id uuid, user_email text, subject text)
language plpgsql
security definer
set search_path = ''
as $$
declare
    ticket public.support_threads%rowtype;
begin
    if p_thread_id is null or p_sender_id is null or p_body is null
       or char_length(btrim(p_body)) not between 1 and 5000 then
        raise exception 'Invalid support reply';
    end if;

    select *
    into ticket
    from public.support_threads
    where id = p_thread_id
    for update;

    if not found then
        raise exception 'Support ticket not found' using errcode = 'P0002';
    end if;
    if ticket.status <> 'in_progress' or ticket.claimed_by is distinct from p_sender_id then
        raise exception 'Claim this ticket before replying' using errcode = 'P0001';
    end if;

    insert into public.support_messages (thread_id, sender_id, sender_is_admin, body)
    values (ticket.id, p_sender_id, true, btrim(p_body));

    update public.support_threads
    set updated_at = now()
    where id = ticket.id;

    return query select ticket.user_id, ticket.user_email, ticket.subject;
end;
$$;

revoke all on function public.admin_reply_support(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.admin_reply_support(uuid, uuid, text) to service_role;
