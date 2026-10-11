-- The Candy Bowl: admin suspension controls migration
-- Run in Supabase SQL Editor AFTER schema.sql.

create or replace function public.admin_suspend_user(p_user_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_suspension_id uuid; v_end timestamptz;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_user_id is null or p_user_id=auth.uid() then raise exception 'Choose another user to suspend'; end if;
  if p_reason is null or char_length(trim(p_reason))<10 then raise exception 'Enter a reason of at least 10 characters'; end if;
  if not exists(select 1 from public.profiles where id=p_user_id) then raise exception 'User not found'; end if;
  if exists(select 1 from public.suspensions where user_id=p_user_id and status in ('active','permanent') and (end_at is null or end_at>now())) then raise exception 'This user already has an active suspension'; end if;
  v_end := now()+interval '30 days';
  insert into public.suspensions(user_id,reason,start_at,end_at,status,issued_by)
  values(p_user_id,trim(p_reason),now(),v_end,'active',auth.uid()) returning id into v_suspension_id;
  insert into public.admin_audit_logs(admin_id,action,target_user_id,details)
  values(auth.uid(),'user_suspended_30_days',p_user_id,jsonb_build_object('reason',trim(p_reason),'suspension_id',v_suspension_id,'end_at',v_end));
  insert into public.notifications(user_id,title,body) values(p_user_id,'Marketplace suspension','An administrator suspended your marketplace activity for 30 days. Reason: '||trim(p_reason)||' You may contact the marketplace administrator to appeal.');
  return v_suspension_id;
end; $$;

create or replace function public.admin_reinstate_user(p_user_id uuid, p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_count integer;
begin
  if auth.uid() is null or not public.is_admin() then raise exception 'Administrator access required'; end if;
  if p_user_id is null or p_user_id=auth.uid() then raise exception 'Choose another user'; end if;
  if p_reason is null or char_length(trim(p_reason))<5 then raise exception 'Enter a reason of at least 5 characters'; end if;
  update public.suspensions set status='revoked' where user_id=p_user_id and status in ('active','permanent') and (end_at is null or end_at>now());
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'No active suspension was found for this user'; end if;
  insert into public.admin_audit_logs(admin_id,action,target_user_id,details) values(auth.uid(),'user_reinstated',p_user_id,jsonb_build_object('reason',trim(p_reason)));
  insert into public.notifications(user_id,title,body) values(p_user_id,'Marketplace access restored','An administrator reinstated your marketplace access. Reason: '||trim(p_reason));
end; $$;

drop policy if exists "Public reads active listings" on public.listings;
create policy "Public reads eligible active listings" on public.listings for select to anon,authenticated
using ((status='active' and quantity_available>0 and public.is_eligible(seller_id)) or seller_id=auth.uid() or public.is_admin());

grant execute on function public.admin_suspend_user(uuid,text) to authenticated;
grant execute on function public.admin_reinstate_user(uuid,text) to authenticated;
