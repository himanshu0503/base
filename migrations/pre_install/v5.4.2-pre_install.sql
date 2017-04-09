\echo "Updating systemMachineImageId for subscriptions that have a null value to use the current default image"
update "subscriptions" set "systemMachineImageId" = "systemMachineImages"."id" from "systemMachineImages" where "systemMachineImages"."isDefault" = true and "subscriptions"."systemMachineImageId" is null;

\echo "Sucessfully completed pre_install migrations"
