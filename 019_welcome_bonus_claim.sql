create or replace function public.okeyx_welcome_bonus_status()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid text := auth.uid()::text;
  claimed boolean;
  bal bigint;
begin
  if uid is null then return jsonb_build_object('ok',false,'code','auth_required'); end if;
  select exists(select 1 from public.okeyx_reward_claims where user_id=uid and claim_type='welcome_bonus' and claim_key='v1') into claimed;
  select coalesce(coins,0) into bal from public.okeyx_profiles where user_id=uid;
  return jsonb_build_object('ok',true,'available',not claimed,'claimed',claimed,'reward',10000,'coins',coalesce(bal,0));
end;
$$;

create or replace function public.okeyx_claim_welcome_bonus()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid text := auth.uid()::text;
  inserted_count int := 0;
  bal bigint;
begin
  if uid is null then return jsonb_build_object('ok',false,'code','auth_required'); end if;
  insert into public.okeyx_reward_claims(user_id,claim_type,claim_key,reward,metadata)
  values(uid,'welcome_bonus','v1',jsonb_build_object('coins',10000),jsonb_build_object('kind','first_login','version',1))
  on conflict(user_id,claim_type,claim_key) do nothing;
  get diagnostics inserted_count = row_count;
  if inserted_count = 0 then
    select coalesce(coins,0) into bal from public.okeyx_profiles where user_id=uid;
    return jsonb_build_object('ok',false,'code','already_claimed','coins',coalesce(bal,0));
  end if;
  update public.okeyx_profiles set coins = greatest(coalesce(coins,0),10000) where user_id=uid returning coins into bal;
  return jsonb_build_object('ok',true,'reward',10000,'coins',coalesce(bal,10000));
end;
$$;

revoke all on function public.okeyx_welcome_bonus_status() from public, anon;
revoke all on function public.okeyx_claim_welcome_bonus() from public, anon;
grant execute on function public.okeyx_welcome_bonus_status() to authenticated, service_role;
grant execute on function public.okeyx_claim_welcome_bonus() to authenticated, service_role;
