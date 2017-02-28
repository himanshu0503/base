do $$
  begin
    update "subscriptions" set "systemMachineImageId" = (select "id" from "systemMachineImages" where "isDefault"=true) where "systemMachineImageId" is null;
  end
$$;
