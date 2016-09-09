create table if not exists "systemConfigs" (
  "id" INT  PRIMARY KEY NOT NULL,
  "defaultMinionCount" INT DEFAULT 1 NOT NULL,
  "defaultPipelineCount" INT DEFAULT 1 NOT NULL,
  "braintreeEnabled" BOOLEAN NOT NULL,
  "cachingEnabled" BOOLEAN DEFAULT TRUE NOT NULL,
  "hubspotEnabled" BOOLEAN DEFAULT TRUE NOT NULL,
  "buildTimeoutMS" INT DEFAULT 3600000 NOT NULL,
  "defaultPrivateJobQuota" INT DEFAULT 150 NOT NULL,
  "serviceUserToken" VARCHAR(36) NOT NULL,
  "vaultUrl" VARCHAR(255),
  "vaultToken" VARCHAR(45),
  "vaultRefreshTimeInSec" INT,
  "amqpUrl" VARCHAR(255),
  "amqpUrlRoot" VARCHAR(255),
  "amqpUrlAdmin" VARCHAR(255),
  "amqpDefaultExchange" VARCHAR(255),
  "apiUrl" VARCHAR(255),
  "apiPort" INT,
  "wwwUrl" VARCHAR(255),
  "runMode" VARCHAR(255) DEFAULT 'debug' NOT NULL,
  "rootQueueList" TEXT,
  "execImage" VARCHAR(255) NOT NULL,
  "createdAt" timestamp with time zone NOT NULL,
  "updatedAt" timestamp with time zone NOT NULL
);
alter table "systemConfigs" owner to "apiuser";
