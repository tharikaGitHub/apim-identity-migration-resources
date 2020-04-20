CREATE TABLE IF NOT EXISTS IDN_OAUTH2_AUTHZ_CODE_SCOPE(
    CODE_ID VARCHAR(255),
    SCOPE VARCHAR(60),
    TENANT_ID INTEGER DEFAULT -1,
    PRIMARY KEY (CODE_ID, SCOPE),
    FOREIGN KEY (CODE_ID) REFERENCES IDN_OAUTH2_AUTHORIZATION_CODE (CODE_ID) ON DELETE CASCADE
) ENGINE INNODB;

CREATE TABLE IF NOT EXISTS IDN_OAUTH2_TOKEN_BINDING (
    TOKEN_ID VARCHAR(255),
    TOKEN_BINDING_TYPE VARCHAR(32),
    TOKEN_BINDING_REF VARCHAR(32),
    TOKEN_BINDING_VALUE VARCHAR(1024),
    TENANT_ID INTEGER DEFAULT -1,
    PRIMARY KEY (TOKEN_ID),
    FOREIGN KEY (TOKEN_ID) REFERENCES IDN_OAUTH2_ACCESS_TOKEN(TOKEN_ID) ON DELETE CASCADE
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS IDN_FED_AUTH_SESSION_MAPPING (
    IDP_SESSION_ID VARCHAR(255) NOT NULL,
    SESSION_ID VARCHAR(255) NOT NULL,
    IDP_NAME VARCHAR(255) NOT NULL,
    AUTHENTICATOR_ID VARCHAR(255),
    PROTOCOL_TYPE VARCHAR(255),
    TIME_CREATED TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (IDP_SESSION_ID)
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS IDN_OAUTH2_CIBA_AUTH_CODE (
    AUTH_CODE_KEY CHAR(36),
    AUTH_REQ_ID CHAR(36),
    ISSUED_TIME TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSUMER_KEY VARCHAR(255),
    LAST_POLLED_TIME TIMESTAMP NOT NULL,
    POLLING_INTERVAL INTEGER,
    EXPIRES_IN  INTEGER,
    AUTHENTICATED_USER_NAME VARCHAR(255),
    USER_STORE_DOMAIN VARCHAR(100),
    TENANT_ID INTEGER,
    AUTH_REQ_STATUS VARCHAR(100) DEFAULT 'REQUESTED',
    IDP_ID INTEGER,
    UNIQUE(AUTH_REQ_ID),
    PRIMARY KEY (AUTH_CODE_KEY),
    FOREIGN KEY (CONSUMER_KEY) REFERENCES IDN_OAUTH_CONSUMER_APPS(CONSUMER_KEY) ON DELETE CASCADE
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS IDN_OAUTH2_CIBA_REQUEST_SCOPES (
    AUTH_CODE_KEY CHAR(36),
    SCOPE VARCHAR(255),
    FOREIGN KEY (AUTH_CODE_KEY) REFERENCES IDN_OAUTH2_CIBA_AUTH_CODE(AUTH_CODE_KEY) ON DELETE CASCADE
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS IDN_OAUTH2_DEVICE_FLOW (
    CODE_ID VARCHAR(255),
    DEVICE_CODE VARCHAR(255),
    USER_CODE VARCHAR(25),
    CONSUMER_KEY_ID INTEGER,
    LAST_POLL_TIME TIMESTAMP NOT NULL,
    EXPIRY_TIME TIMESTAMP NOT NULL,
    TIME_CREATED TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    POLL_TIME BIGINT,
    STATUS VARCHAR(25) DEFAULT 'PENDING',
    AUTHZ_USER VARCHAR(100),
    TENANT_ID INTEGER,
    USER_DOMAIN VARCHAR(50),
    IDP_ID INTEGER,
    PRIMARY KEY (DEVICE_CODE),
    UNIQUE (CODE_ID),
    UNIQUE (USER_CODE),
    FOREIGN KEY (CONSUMER_KEY_ID) REFERENCES IDN_OAUTH_CONSUMER_APPS(ID) ON DELETE CASCADE
)ENGINE INNODB;

CREATE TABLE IF NOT EXISTS IDN_OAUTH2_DEVICE_FLOW_SCOPES (
    ID INTEGER NOT NULL AUTO_INCREMENT,
    SCOPE_ID VARCHAR(255),
    SCOPE VARCHAR(255),
    PRIMARY KEY (ID),
    FOREIGN KEY (SCOPE_ID) REFERENCES IDN_OAUTH2_DEVICE_FLOW(CODE_ID) ON DELETE CASCADE
)ENGINE INNODB;

ALTER TABLE IDN_OAUTH2_ACCESS_TOKEN
    ADD COLUMN TOKEN_BINDING_REF VARCHAR(32) DEFAULT 'NONE',
    CHANGE IDP_ID IDP_ID INTEGER DEFAULT -1 NOT NULL,
    DROP INDEX CON_APP_KEY,
    ADD CONSTRAINT CON_APP_KEY UNIQUE (CONSUMER_KEY_ID,AUTHZ_USER,TENANT_ID,USER_DOMAIN,USER_TYPE,TOKEN_SCOPE_HASH,TOKEN_STATE,TOKEN_STATE_ID,IDP_ID,TOKEN_BINDING_REF);

ALTER TABLE IDN_OAUTH2_ACCESS_TOKEN_AUDIT CHANGE IDP_ID IDP_ID INTEGER DEFAULT -1 NOT NULL;

ALTER TABLE IDN_OAUTH2_AUTHORIZATION_CODE CHANGE IDP_ID IDP_ID INTEGER DEFAULT -1 NOT NULL;

ALTER TABLE IDN_ASSOCIATED_ID ADD COLUMN ASSOCIATION_ID CHAR(36) NOT NULL;

UPDATE IDN_ASSOCIATED_ID SET ASSOCIATION_ID = UUID();

ALTER TABLE SP_APP
    ADD COLUMN (
        UUID CHAR(36),
        IMAGE_URL VARCHAR(1024),
        ACCESS_URL VARCHAR(1024),
        IS_DISCOVERABLE CHAR(1) DEFAULT '0'),
    ADD CONSTRAINT APPLICATION_UUID_CONSTRAINT UNIQUE (UUID);

UPDATE SP_APP SET UUID = UUID();

ALTER TABLE IDP
    ADD COLUMN (
        IMAGE_URL VARCHAR(1024),
        UUID CHAR(36)),
    ADD UNIQUE (UUID);

UPDATE IDP SET UUID = UUID();

DROP PROCEDURE IF EXISTS ALTER_IDN_CONFIG_FILE;

DELIMITER $$
CREATE PROCEDURE ALTER_IDN_CONFIG_FILE()
BEGIN
    IF EXISTS(SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='IDN_CONFIG_FILE') THEN
        IF NOT EXISTS(SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='IDN_CONFIG_FILE' AND COLUMN_NAME='NAME') THEN
            ALTER TABLE `IDN_CONFIG_FILE` ADD COLUMN `NAME` VARCHAR(255) NULL;
        END IF;
    END IF;
END $$
DELIMITER ;

CALL ALTER_IDN_CONFIG_FILE();

DROP PROCEDURE IF EXISTS ALTER_IDN_CONFIG_FILE;

ALTER TABLE FIDO2_DEVICE_STORE
    ADD COLUMN (
        DISPLAY_NAME VARCHAR(255),
        IS_USERNAMELESS_SUPPORTED CHAR(1) DEFAULT '0');

ALTER TABLE IDN_OAUTH2_SCOPE_BINDING
    ADD COLUMN BINDING_TYPE VARCHAR(255) NOT NULL DEFAULT 'DEFAULT',
    CHANGE SCOPE_BINDING SCOPE_BINDING VARCHAR(255) NOT NULL,
    ADD UNIQUE (SCOPE_ID, SCOPE_BINDING, BINDING_TYPE);

-- Related to Scope Management --
DROP INDEX IDX_SC_N_TID ON IDN_OAUTH2_SCOPE;

ALTER TABLE IDN_OAUTH2_SCOPE
    ADD COLUMN SCOPE_TYPE VARCHAR(255) NOT NULL DEFAULT 'OAUTH2';

CREATE TABLE IF NOT EXISTS IDN_OIDC_SCOPE_CLAIM_MAPPING_NEW (
    ID INTEGER NOT NULL AUTO_INCREMENT,
    SCOPE_ID INTEGER NOT NULL,
    EXTERNAL_CLAIM_ID INTEGER NOT NULL,
    PRIMARY KEY (ID),
    FOREIGN KEY (SCOPE_ID) REFERENCES IDN_OAUTH2_SCOPE(SCOPE_ID) ON DELETE CASCADE,
    FOREIGN KEY (EXTERNAL_CLAIM_ID) REFERENCES IDN_CLAIM(ID) ON DELETE CASCADE,
    UNIQUE (SCOPE_ID, EXTERNAL_CLAIM_ID)
);

DROP PROCEDURE IF EXISTS OIDC_SCOPE_DATA_MIGRATE_PROCEDURE;

DELIMITER $$
CREATE PROCEDURE OIDC_SCOPE_DATA_MIGRATE_PROCEDURE()
BEGIN
    DECLARE oidc_scope_count INT DEFAULT 0;
    DECLARE row_offset INT DEFAULT 0;
    DECLARE oauth_scope_id INT DEFAULT 0;
    DECLARE oidc_scope_id INT DEFAULT 0;
    SELECT COUNT(*) FROM IDN_OIDC_SCOPE INTO oidc_scope_count;
    WHILE row_offset < oidc_scope_count DO
        SELECT ID INTO @oidc_scope_id FROM IDN_OIDC_SCOPE LIMIT row_offset,1;
        INSERT INTO IDN_OAUTH2_SCOPE (NAME, DISPLAY_NAME, TENANT_ID, SCOPE_TYPE) SELECT NAME, NAME, TENANT_ID, 'OIDC' FROM IDN_OIDC_SCOPE LIMIT row_offset,1;
        SELECT LAST_INSERT_ID() INTO @oauth_scope_id;
        INSERT INTO IDN_OIDC_SCOPE_CLAIM_MAPPING_NEW (SCOPE_ID, EXTERNAL_CLAIM_ID) SELECT @oauth_scope_id, EXTERNAL_CLAIM_ID FROM IDN_OIDC_SCOPE_CLAIM_MAPPING WHERE SCOPE_ID = @oidc_scope_id;
        SET row_offset = row_offset + 1;
    END WHILE;
END $$
DELIMITER ;

CALL OIDC_SCOPE_DATA_MIGRATE_PROCEDURE();

DROP PROCEDURE IF EXISTS OIDC_SCOPE_DATA_MIGRATE_PROCEDURE;

DROP TABLE IDN_OIDC_SCOPE_CLAIM_MAPPING;

RENAME TABLE IDN_OIDC_SCOPE_CLAIM_MAPPING_NEW TO IDN_OIDC_SCOPE_CLAIM_MAPPING;

DROP TABLE IDN_OIDC_SCOPE;

CREATE INDEX IDX_IDN_AUTH_BIND ON IDN_OAUTH2_TOKEN_BINDING (TOKEN_BINDING_REF);

CREATE INDEX IDX_AI_DN_UN_AI ON IDN_ASSOCIATED_ID(DOMAIN_NAME, USER_NAME, ASSOCIATION_ID);

CREATE INDEX IDX_AT_CKID_AU_TID_UD_TSH_TS ON IDN_OAUTH2_ACCESS_TOKEN(CONSUMER_KEY_ID, AUTHZ_USER, TENANT_ID, USER_DOMAIN, TOKEN_SCOPE_HASH, TOKEN_STATE);

CREATE INDEX IDX_FEDERATED_AUTH_SESSION_ID ON IDN_FED_AUTH_SESSION_MAPPING (SESSION_ID);

TRUNCATE TABLE IDN_AUTH_SESSION_APP_INFO;

TRUNCATE TABLE IDN_AUTH_SESSION_STORE;

TRUNCATE TABLE IDN_AUTH_SESSION_META_DATA;

TRUNCATE TABLE IDN_AUTH_USER;

TRUNCATE TABLE IDN_AUTH_USER_SESSION_MAPPING;
