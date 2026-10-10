-- The Candy Bowl — initial Supabase schema
-- Run in Supabase SQL Editor on a new project. Review school policy before real use.
create extension if not exists pgcrypto;

create type public.account_state as enum ('active','suspended','banned');
create type public.listing_state as enum ('pending','active','sold_out','hidden','removed');
create type public.order_state as enum ('pending','accepted','ready_for_handover','completed','cancelled','disputed','rejected');
create type public.payment_state as enum ('unpaid','paid_in_cash','refunded_in_cash');
create type public.report_state as enum ('submitted','under_review','more_information_required','resolved','dismissed');
create type public.strike_state as enum ('active','revoked','expired');

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null check (char_length(display_name) between 1 and 40),
 role text not null default 'user' check (role in ('user','admin')),
 account_status public.account_state not null default 'active',
 created_at timestamptz not null default now()
);
create table public.listings (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.profiles(id) on delete restrict,
 name text not null check (char_length(name) between 1 and 90),
 description text not null default '' check (char_length(description)<=1200),
 category text not null check (category in ('Chocolate','Lollies','Gummies','Mints','Chewing gum','Biscuits and sweets','Candy bundles','Other')),
 price numeric(10,2) not null check (price>0),
 quantity_available integer not null check (quantity_available>=0),
 image_url text,
 allergen_information text not null default '',
 status public.listing_state not null default 'pending',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.orders (
 id uuid primary key default gen_random_uuid(),
 buyer_id uuid not null references public.profiles(id) on delete restrict,
 seller_id uuid not null references public.profiles(id) on delete restrict,
 listing_id uuid not null references public.listings(id) on delete restrict,
 item_name_snapshot text not null,
 unit_price_snapshot numeric(10,2) not null check (unit_price_snapshot>0),
 quantity integer not null check (quantity>0),
 total_amount numeric(12,2) generated always as (unit_price_snapshot*quantity) stored,
 order_status public.order_state not null default 'pending',
 payment_status public.payment_state not null default 'unpaid',
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint no_self_order check (buyer_id<>seller_id)
);
create table public.order_events (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete restrict,
 actor_id uuid references public.profiles(id) on delete set null,
 event_type text not null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create table public.reports (
 id uuid primary key default gen_random_uuid(),
 reporter_id uuid not null references public.profiles(id) on delete restrict,
 reported_user_id uuid references public.profiles(id) on delete set null,
 listing_id uuid references public.listings(id) on delete set null,
 order_id uuid references public.orders(id) on delete set null,
 category text not null,
 description text not null check (char_length(description) between 10 and 2000),
 status public.report_state not null default 'submitted',
 resolution text,
 reviewed_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 resolved_at timestamptz
);
create table public.strikes (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete restrict,
 report_id uuid references public.reports(id) on delete set null,
 reason text not null check (char_length(reason)>=10),
 issued_by uuid not null references public.profiles(id) on delete restrict,
 status public.strike_state not null default 'active',
 issued_at timestamptz not null default now(),
 expires_at timestamptz
);
create table public.suspensions (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete restrict,
 reason text not null,
 start_at timestamptz not null default now(),
 end_at timestamptz,
 status text not null default 'active' check(status in ('active','expired','revoked','permanent')),
 issued_by uuid not null references public.profiles(id) on delete restrict
);
create table public.appeals (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete restrict,
 strike_id uuid references public.strikes(id) on delete set null,
 suspension_id uuid references public.suspensions(id) on delete set null,
 reason text not null check(char_length(reason)>=10),
 status text not null default 'submitted' check(status in ('submitted','under_review','accepted','rejected')),
 reviewed_by uuid references public.profiles(id) on delete set null,
 created_at timestamptz not null default now(),
 check (strike_id is not null or suspension_id is not null)
);
create table public.admin_audit_logs (
 id uuid primary key default gen_random_uuid(),
 admin_id uuid not null references public.profiles(id) on delete restrict,
 action text not null,
 target_user_id uuid references public.profiles(id) on delete set null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);
create table public.notifications (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 title text not null,
 body text not null,
 read_at timestamptz,
 created_at timestamptz not null default now()
);

create index listings_public_idx on public.listings(status,created_at desc);
create index listings_seller_idx on public.listings(seller_id,created_at desc);
create index orders_buyer_idx on public.orders(buyer_id,created_at desc);
create index orders_seller_idx on public.orders(seller_id,created_at desc);
create index reports_status_idx on public.reports(status,created_at desc);
create index strikes_user_idx on public.strikes(user_id,status);
create index notifications_user_idx on public.notifications(user_id,created_at desc);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.account_status='active') $$;

create or replace function public.is_eligible(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=p_uid and p.account_status='active')
and not exists(select 1 from public.suspensions s where s.user_id=p_uid and s.status in ('active','permanent') and (s.end_at is null or s.end_at>now())) $$;

-- Profile is created on sign-up. Role is never taken from user metadata.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.profiles(id,display_name) values(new.id,coalesce(nullif(left(trim(new.raw_user_meta_data->>'display_name'),40),''),'Candy Bowl user'));
 return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Guard profile updates: ordinary users may only change their display name.
create or replace function public.guard_profile_update()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 if auth.uid()=old.id and not public.is_admin() then
   if new.role<>old.role or new.account_status<>old.account_status or new.id<>old.id then raise exception 'You cannot change role or account status'; end if;
 end if;
 new.display_name=left(trim(new.display_name),40);
 return new;
end $$;
create trigger profile_update_guard before update on public.profiles for each row execute procedure public.guard_profile_update();

create or replace function public.place_order(p_listing_id uuid,p_quantity integer)
returns uuid language plpgsql security definer set search_path=public
as $$
declare v_listing public.listings%rowtype; v_order_id uuid;
begin
 if auth.uid() is null then raise exception 'Sign in to place an order'; end if;
 if p_quantity is null or p_quantity<1 then raise exception 'Quantity must be at least one'; end if;
 if not public.is_eligible(auth.uid()) then raise exception 'Your account is not eligible to place orders'; end if;
 select * into v_listing from public.listings where id=p_listing_id for update;
 if not found or v_listing.status<>'active' then raise exception 'Listing is unavailable'; end if;
 if v_listing.seller_id=auth.uid() then raise exception 'You cannot order your own listing'; end if;
 if v_listing.quantity_available<p_quantity then raise exception 'Not enough stock is available'; end if;
 if not public.is_eligible(v_listing.seller_id) then raise exception 'Seller is not currently eligible'; end if;
 update public.listings set quantity_available=quantity_available-p_quantity,
   status=case when quantity_available-p_quantity=0 then 'sold_out'::public.listing_state else status end,
   updated_at=now() where id=p_listing_id;
 insert into public.orders(buyer_id,seller_id,listing_id,item_name_snapshot,unit_price_snapshot,quantity)
 values(auth.uid(),v_listing.seller_id,v_listing.id,v_listing.name,v_listing.price,p_quantity) returning id into v_order_id;
 insert into public.order_events(order_id,actor_id,event_type,details) values(v_order_id,auth.uid(),'order_placed',jsonb_build_object('quantity',p_quantity,'total',v_listing.price*p_quantity));
 insert into public.notifications(user_id,title,body) values(v_listing.seller_id,'New order','You have a new order to review.');
 return v_order_id;
end $$;

create or replace function public.transition_order(p_order_id uuid,p_action text)
returns void language plpgsql security definer set search_path=public
as $$
declare o public.orders%rowtype; v_next public.order_state;
begin
 select * into o from public.orders where id=p_order_id for update;
 if not found then raise exception 'Order not found'; end if;
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if not public.is_eligible(auth.uid()) and p_action not in ('report_dispute') then raise exception 'Account is not eligible for this action'; end if;
 if p_action='accept' and auth.uid()=o.seller_id and o.order_status='pending' then v_next:='accepted';
 elsif p_action='reject' and auth.uid()=o.seller_id and o.order_status='pending' then v_next:='rejected';
 elsif p_action='ready' and auth.uid()=o.seller_id and o.order_status='accepted' then v_next:='ready_for_handover';
 elsif p_action='complete' and auth.uid()=o.seller_id and o.order_status='ready_for_handover' then v_next:='completed';
 elsif p_action='cancel' and auth.uid()=o.buyer_id and o.order_status='pending' then v_next:='cancelled';
 elsif p_action='dispute' and (auth.uid()=o.buyer_id or auth.uid()=o.seller_id) and o.order_status in ('pending','accepted','ready_for_handover') then v_next:='disputed';
 else raise exception 'This action is not permitted for this order'; end if;
 update public.orders set order_status=v_next,updated_at=now() where id=p_order_id;
 if v_next in ('cancelled','rejected') then
   update public.listings set quantity_available=quantity_available+o.quantity,status='active',updated_at=now() where id=o.listing_id and status<>'removed' and status<>'hidden';
 end if;
 insert into public.order_events(order_id,actor_id,event_type,details) values(o.id,auth.uid(),p_action,jsonb_build_object('from',o.order_status,'to',v_next));
 insert into public.notifications(user_id,title,body) values(case when auth.uid()=o.buyer_id then o.seller_id else o.buyer_id end,'Order updated','Your order status is now '||replace(v_next::text,'_',' ')||'.');
end $$;

create or replace function public.confirm_cash_payment(p_order_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
declare o public.orders%rowtype;
begin
 select * into o from public.orders where id=p_order_id for update;
 if not found or auth.uid()<>o.seller_id then raise exception 'Only the seller can record cash payment'; end if;
 if o.order_status not in ('ready_for_handover','completed') then raise exception 'Order is not ready for handover'; end if;
 if o.payment_status<>'unpaid' then raise exception 'Payment is already recorded'; end if;
 update public.orders set payment_status='paid_in_cash',updated_at=now() where id=p_order_id;
 insert into public.order_events(order_id,actor_id,event_type) values(o.id,auth.uid(),'cash_payment_recorded');
 insert into public.notifications(user_id,title,body) values(o.buyer_id,'Cash payment recorded','The seller marked the order as paid in cash.');
end $$;

-- Friendly RPC names used by the frontend.
create or replace function public.accept_order(p_order_id uuid) returns void language sql security definer set search_path=public as $$ select public.transition_order(p_order_id,'accept') $$;
create or replace function public.reject_order(p_order_id uuid) returns void language sql security definer set search_path=public as $$ select public.transition_order(p_order_id,'reject') $$;
create or replace function public.mark_order_ready(p_order_id uuid) returns void language sql security definer set search_path=public as $$ select public.transition_order(p_order_id,'ready') $$;
create or replace function public.confirm_handover(p_order_id uuid) returns void language sql security definer set search_path=public as $$ select public.transition_order(p_order_id,'complete') $$;
-- confirm_cash_payment(uuid) is defined above with the trusted implementation.

-- RLS
alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.orders enable row level security;
alter table public.order_events enable row level security;
alter table public.reports enable row level security;
alter table public.strikes enable row level security;
alter table public.suspensions enable row level security;
alter table public.appeals enable row level security;
alter table public.admin_audit_logs enable row level security;
alter table public.notifications enable row level security;

create policy "Profiles visible to signed-in users in limited fields" on public.profiles for select to authenticated using (true);
create policy "Users update own profile" on public.profiles for update to authenticated using (id=auth.uid() or public.is_admin()) with check (id=auth.uid() or public.is_admin());
create policy "Public reads active listings" on public.listings for select to anon,authenticated using (status='active' and quantity_available>0 or seller_id=auth.uid() or public.is_admin());
create policy "Eligible users create own listings" on public.listings for insert to authenticated with check (seller_id=auth.uid() and public.is_eligible(auth.uid()) and status in ('active','pending'));
create policy "Seller or admin updates listing" on public.listings for update to authenticated using (seller_id=auth.uid() or public.is_admin()) with check ((seller_id=auth.uid() and public.is_eligible(auth.uid())) or public.is_admin());
create policy "Seller or admin deletes listing" on public.listings for delete to authenticated using (seller_id=auth.uid() or public.is_admin());
create policy "Buyer or seller reads order" on public.orders for select to authenticated using (buyer_id=auth.uid() or seller_id=auth.uid() or public.is_admin());
create policy "Order event parties read events" on public.order_events for select to authenticated using (exists(select 1 from public.orders o where o.id=order_id and (o.buyer_id=auth.uid() or o.seller_id=auth.uid())) or public.is_admin());
create policy "Order parties read reports" on public.reports for select to authenticated using (reporter_id=auth.uid() or public.is_admin());
create policy "Authenticated user submits report" on public.reports for insert to authenticated with check (reporter_id=auth.uid());
create policy "Admins manage reports" on public.reports for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "Users read own strikes" on public.strikes for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "Users read own suspensions" on public.suspensions for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "Users read own appeals" on public.appeals for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "Users submit own appeals" on public.appeals for insert to authenticated with check (user_id=auth.uid());
create policy "Admins read audit logs" on public.admin_audit_logs for select to authenticated using (public.is_admin());
create policy "Users read own notifications" on public.notifications for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "Users mark own notifications read" on public.notifications for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());

-- No direct client insert/update/delete permissions for orders or moderation tables.
revoke insert,update,delete on public.orders from anon,authenticated;
revoke insert,update,delete on public.order_events from anon,authenticated;
revoke insert,update,delete on public.strikes from anon,authenticated;
revoke insert,update,delete on public.suspensions from anon,authenticated;
revoke insert,update,delete on public.admin_audit_logs from anon,authenticated;
grant execute on function public.place_order(uuid,integer) to authenticated;
grant execute on function public.accept_order(uuid) to authenticated;
grant execute on function public.reject_order(uuid) to authenticated;
grant execute on function public.mark_order_ready(uuid) to authenticated;
grant execute on function public.confirm_handover(uuid) to authenticated;
grant execute on function public.confirm_cash_payment(uuid) to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.is_eligible(uuid) to authenticated;

-- IMPORTANT: Configure the first admin securely from the SQL Editor after signup:
-- update public.profiles set role='admin' where id='AUTH_USER_UUID_HERE';
-- Never expose the service_role key. Review and test every policy before real use.
