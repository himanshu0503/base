do $$
  begin
    if exists (select 1 from information_schema.columns where table_name = 'projects' and column_name = 'isOrphaned') then
      update projects set "isOrphaned" = false where "isOrphaned" is NULL;
      create temp table temp_pa as select id from projects;
      delete from temp_pa using "projectAccounts" where "projectAccounts"."projectId" = temp_pa.id;
      update projects set "isOrphaned" = true from temp_pa where temp_pa.id = projects.id;
      drop table temp_pa;
    end if;
  end
$$;
