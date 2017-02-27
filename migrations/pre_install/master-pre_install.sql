do $$
  begin
    if exists (select * from "subscriptions" where "systemMachineImageId" is null) then
      update "subscriptions" set "systemMachineImageId" = (select "id" from "systemMachineImages" where "isDefault"=true);
    end if;
  end
$$;
