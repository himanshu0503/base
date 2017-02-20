do $$
  begin
    if exists (select 1 from information_schema.columns where table_name = 'projects' and column_name = 'isOrphaned') then
      create temp table temp_pa as select "projectId" as id from "projectAccounts" group by "projectId";
      update projects set "isOrphaned" = true from (select projects.id from projects left join temp_pa on projects.id = temp_pa.id where temp_pa.id is NULL) T where T.id = projects.id;
      update projects set "isOrphaned" = false from temp_pa where projects.id = temp_pa.id;
      drop table temp_pa;
    end if;
  end
$$;
