do $$
  begin
    if exists (select 1 from information_schema.columns where table_name = 'projects' and column_name = 'isOrphaned') then
      update projects set "isOrphaned" = true where "id" not in (select distinct "projectId" from "projectAccounts");
    end if;
  end
$$;
