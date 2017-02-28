do $$
  begin
    update "subscriptions" set "systemMachineImageId" = (select "id" from "systemMachineImages" where "isDefault"=true) where "systemMachineImageId" is null;
  end
$$;

-- Migration script for populating `jobStatesMap` for older runs

create temp table tjsm as WITH cte AS
(
   SELECT "id","projectId","branchName","runNumber","createdAt","statusCode","isGitTag","isPullRequest","isRelease","gitTagName","releaseName","subscriptionId", "createdBy", "updatedBy", "updatedAt", ROW_NUMBER() OVER (PARTITION BY "projectId","branchName","statusCode","isGitTag","isPullRequest","isRelease" ORDER BY "createdAt" desc)
AS rn FROM runs
)
SELECT "id", "projectId" as pid,"branchName" as bn,"runNumber","createdAt","statusCode","isGitTag","isPullRequest","isRelease","gitTagName","releaseName","subscriptionId", "createdBy", "updatedBy", "updatedAt"
FROM cte
WHERE rn = 1 and "statusCode" in (30,50,60,80) and "branchName" is not null;

alter table tjsm add column "contextTypeCode" int, add column "contextValue" varchar(255), add column "lastSuccessfulJobId" varchar(24), add column "lastFailedJobId" varchar(24), add column "lastUnstableJobId" varchar(24), add column "lastTimedoutJobId" varchar(24);
update tjsm T set "isPullRequest" = false where "isPullRequest" is null;
update tjsm T set "releaseName" = T."gitTagName" where "isRelease" = true and "releaseName" is null;

update tjsm T1 set "lastSuccessfulJobId" = T2.id from (select * from tjsm where "statusCode" = 30) T2 where
  ((T1."isGitTag" = T2."isGitTag") or (T1."isGitTag" is null and T2."isGitTag" is null)) and
  ((T1."isRelease" = T2."isRelease") or (T1."isRelease" is null and T2."isRelease" is null)) and
  ((T1."isPullRequest" = T2."isPullRequest") or (T1."isPullRequest" is null and T2."isPullRequest" is null)) and
  ((T1."bn" = T2."bn") or (T1."bn" is null and T2."bn" is null)) and
  ((T1."gitTagName" = T2."gitTagName") or (T1."gitTagName" is null and T2."gitTagName" is null)) and
  ((T1."releaseName" = T2."releaseName") or (T1."releaseName" is null and T2."releaseName" is null)) and
  T1.pid = T2.pid;

update tjsm T1 set "lastUnstableJobId" = T2.id from (select * from tjsm where "statusCode" = 50) T2 where
  ((T1."isGitTag" = T2."isGitTag") or (T1."isGitTag" is null and T2."isGitTag" is null)) and
  ((T1."isRelease" = T2."isRelease") or (T1."isRelease" is null and T2."isRelease" is null)) and
  ((T1."isPullRequest" = T2."isPullRequest") or (T1."isPullRequest" is null and T2."isPullRequest" is null)) and
  ((T1."bn" = T2."bn") or (T1."bn" is null and T2."bn" is null)) and
  ((T1."gitTagName" = T2."gitTagName") or (T1."gitTagName" is null and T2."gitTagName" is null)) and
  ((T1."releaseName" = T2."releaseName") or (T1."releaseName" is null and T2."releaseName" is null)) and
  T1.pid = T2.pid;

update tjsm T1 set "lastTimedoutJobId" = T2.id from (select * from tjsm where "statusCode" = 60) T2 where
  ((T1."isGitTag" = T2."isGitTag") or (T1."isGitTag" is null and T2."isGitTag" is null)) and
  ((T1."isRelease" = T2."isRelease") or (T1."isRelease" is null and T2."isRelease" is null)) and
  ((T1."isPullRequest" = T2."isPullRequest") or (T1."isPullRequest" is null and T2."isPullRequest" is null)) and
  ((T1."bn" = T2."bn") or (T1."bn" is null and T2."bn" is null)) and
  ((T1."gitTagName" = T2."gitTagName") or (T1."gitTagName" is null and T2."gitTagName" is null)) and
  ((T1."releaseName" = T2."releaseName") or (T1."releaseName" is null and T2."releaseName" is null)) and
  T1.pid = T2.pid;

update tjsm T1 set "lastFailedJobId" = T2.id from (select * from tjsm where "statusCode" = 80) T2 where
  ((T1."isGitTag" = T2."isGitTag") or (T1."isGitTag" is null and T2."isGitTag" is null)) and
  ((T1."isRelease" = T2."isRelease") or (T1."isRelease" is null and T2."isRelease" is null)) and
  ((T1."isPullRequest" = T2."isPullRequest") or (T1."isPullRequest" is null and T2."isPullRequest" is null)) and
  ((T1."bn" = T2."bn") or (T1."bn" is null and T2."bn" is null)) and
  ((T1."gitTagName" = T2."gitTagName") or (T1."gitTagName" is null and T2."gitTagName" is null)) and
  ((T1."releaseName" = T2."releaseName") or (T1."releaseName" is null and T2."releaseName" is null)) and
  T1.pid = T2.pid;

delete from tjsm T1 using (select id, ROW_NUMBER() OVER (PARTITION BY "lastSuccessfulJobId", "lastUnstableJobId", "lastTimedoutJobId", "lastFailedJobId", pid order by "runNumber" desc) as rn from tjsm) T2 where T1.id = T2.id and T2.rn > 1;

update tjsm set "contextTypeCode" = 301, "contextValue" = tjsm."gitTagName" where "isGitTag" = true;
update tjsm set "contextTypeCode" = 302, "contextValue" = tjsm."releaseName" where "isRelease" = true;
update tjsm set "contextTypeCode" = 303, "contextValue" = tjsm.bn where "isPullRequest" = true;
update tjsm set "contextTypeCode" = 304, "contextValue" = tjsm.bn where "isPullRequest" = false and "isGitTag" = false and "isRelease" = false;
update tjsm set "updatedBy" = tjsm."createdBy" where "updatedBy" is null;

truncate "jobStatesMap";

INSERT INTO "jobStatesMap" ("projectId", "subscriptionId", "jobTypeCode", "contextTypeCode", "contextValue", "lastSuccessfulJobId", "lastUnstableJobId", "lastTimedoutJobId", "lastFailedJobId", "lastJobId", "createdBy", "updatedBy", "updatedAt", "createdAt")
SELECT pid,"subscriptionId", 201, "contextTypeCode", "contextValue", "lastSuccessfulJobId", "lastUnstableJobId", "lastTimedoutJobId", "lastFailedJobId", id, "createdBy", "updatedBy", "updatedAt", "createdAt" FROM tjsm;

drop table tjsm;


-- Migration script for populating `jobStatesMap` for older builds

create temp table tjsm as WITH cte AS
(
   SELECT "id","projectId","resourceId","createdAt","statusCode","subscriptionId", "updatedAt", ROW_NUMBER() OVER (PARTITION BY "projectId","resourceId", "statusCode" ORDER BY "createdAt" desc)
AS rn FROM builds
)
SELECT "id","projectId" as pid,"resourceId" as rid,"createdAt","statusCode","subscriptionId", "updatedAt"
FROM cte
WHERE rn = 1 and "statusCode" in (4002,4003);

create temp table rtjsm as WITH cte AS
(
   SELECT "id","projectId","createdAt", "createdBy", "updatedBy","name","typeCode","isJob" FROM resources
)
SELECT "id","projectId" as rpid,"createdAt", "createdBy", "updatedBy","name" as "contextValue","typeCode" as "contextTypeCode"
FROM cte
WHERE "isJob" = true and "typeCode" in (2010,2000,2005,2007,2012,2011,2009);

alter table tjsm add column "contextValue" varchar(255), add column "contextTypeCode" int, add column "lastSuccessfulJobId" varchar(24), add column "lastFailedJobId" varchar(24), add column "createdBy" varchar(24), add column "updatedBy" varchar(24);

update rtjsm set "contextTypeCode" = 305 where "contextTypeCode" = 2010;
update rtjsm set "contextTypeCode" = 306 where "contextTypeCode" = 2000;
update rtjsm set "contextTypeCode" = 307 where "contextTypeCode" = 2005;
update rtjsm set "contextTypeCode" = 308 where "contextTypeCode" = 2007;
update rtjsm set "contextTypeCode" = 309 where "contextTypeCode" = 2012;
update rtjsm set "contextTypeCode" = 310 where "contextTypeCode" = 2011;
update rtjsm set "contextTypeCode" = 311 where "contextTypeCode" = 2009;

update tjsm T1 set "contextValue" = T2."contextValue" from rtjsm T2 where T1.rid = T2.id;
update tjsm T1 set "contextTypeCode" = T2."contextTypeCode" from rtjsm T2 where T1.rid = T2.id;
update tjsm T1 set "createdBy" = T2."createdBy" from rtjsm T2 where T1.rid = T2.id;
update tjsm T1 set "updatedBy" = T2."updatedBy" from rtjsm T2 where T1.rid = T2.id;

delete from tjsm where "contextValue" is null;

update tjsm T1 set "lastSuccessfulJobId" = T2.id from (select * from tjsm where "statusCode" = 4002) T2 where T1.pid = T2.pid and T1.rid = T2.rid;
update tjsm T1 set "lastFailedJobId" = T2.id from (select * from tjsm where "statusCode" = 4003) T2 where T1.pid = T2.pid and T1.rid = T2.rid;

delete from tjsm T1 using (select id, ROW_NUMBER() OVER (PARTITION BY "lastSuccessfulJobId", "lastFailedJobId" order by "createdAt" desc) as rn from tjsm) T2 where T1.id = T2.id and T2.rn > 1;

INSERT INTO "jobStatesMap" ("projectId", "subscriptionId", "jobTypeCode", "contextTypeCode", "contextValue", "lastSuccessfulJobId", "lastFailedJobId", "lastJobId", "createdBy", "updatedBy", "updatedAt", "createdAt")
SELECT pid,"subscriptionId", 202, "contextTypeCode", "contextValue", "lastSuccessfulJobId", "lastFailedJobId", id, "createdBy", "updatedBy", "updatedAt", "createdAt" FROM tjsm;

drop table tjsm;
drop table rtjsm;
