
CREATE TYPE type_identity_ban_reason as (
	id_sys_user_owner  integer, -- usuario que realizo el ban
	id_sys_user_remove integer, -- usuario que elimino el ban
	motivo             character varying(255),
	codigo             character varying(50),
	date_init          timestamp with time zone,
	expire_on          timestamp with time zone,
	has_complete 	   integer
);

CREATE TYPE type_identity_history_login as (
	ip  			character varying(20), -- usuario que realizo el ban
	user_agent 		character varying(10),
	date_in    		timestamp with time zone,
	session 		character varying(10)
);

CREATE TYPE type_identity_history_error_login as (
	ip  			character varying(20), -- usuario que realizo el ban
	user_agent 		character varying(10),
	date_in    		timestamp with time zone,
	session 		character varying(10),
	nro_errors 		integer
);

CREATE TYPE type_identity_pin_token as (
	token integer,
	expire_on timestamp with time zone
);


CREATE TYPE type_identity_history_passw as(
	passw    character varying(70),
	date_at  date
);


CREATE TABLE sys_user(
	id serial,
	status_acceso           character varying(20)             NOT NULL default  'EMAIL_VERIFY',
	roles                   integer[]                         DEFAULT ARRAY[1], -- 1 perfil de usuario  (login + account)
	email                   character varying(50)             NOT NULL,
	auth_key                character varying(16)             DEFAULT NULL,
	pin_token               type_identity_pin_token           DEFAULT NULL,

	first_name              character varying(50)             default NULL,
	last_name               character varying(50)             default NULL,

	passw                   character varying(70)             DEFAULT NULL,
	passw_token             character varying(16)             DEFAULT NULL,
	passw_force_change      boolean                           DEFAULT TRUE,
	passw_expire_on         date                              DEFAULT NULL,
	passw_history           type_identity_history_passw[]     DEFAULT NULL,

	ban_reason              type_identity_ban_reason          DEFAULT NULL,
	ban_history             type_identity_ban_reason[]        DEFAULT NULL,

	created_by              integer DEFAULT NULL,
	updated_by              integer DEFAULT NULL,

	created_at              timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
	updated_at              timestamp with time zone DEFAULT NULL,

	last_type_login         timestamp with time zone             DEFAULT NULL,
	history_success_login   type_identity_history_login[]        DEFAULT NULL,
	history_error_login     type_identity_history_error_login[]  DEFAULT NULL,
	primary key (id),
	CONSTRAINT ck1_sys_user check (status_acceso in ('ACTIVE', 'INACTIVE', 'PIN_VERIFY', 'EMAIL_VERIFY') )
);

ALTER TABLE sys_user ADD CONSTRAINT fk01_sys_user FOREIGN KEY(created_by) REFERENCES sys_user (id) on delete set null on update cascade;
ALTER TABLE sys_user ADD CONSTRAINT fk02_sys_user FOREIGN KEY(updated_by) REFERENCES sys_user (id) on delete set null on update cascade;

CREATE UNIQUE INDEX sys_user_index01 ON sys_user (id);
CREATE        INDEX sys_user_index02 ON sys_user (status_acceso);
CREATE        INDEX sys_user_index03 ON sys_user using gin (roles);
CREATE UNIQUE INDEX sys_user_index04 ON sys_user (email);
CREATE UNIQUE INDEX sys_user_index05 ON sys_user (auth_key);

CREATE UNIQUE INDEX sys_user_index06 ON sys_user (passw_token);
CREATE        INDEX sys_user_index07 ON sys_user (pin_token);

CREATE        INDEX sys_user_index08 ON sys_user (passw_force_change);
CREATE        INDEX sys_user_index09 ON sys_user (passw_expire_on);

CREATE        INDEX sys_user_index10 ON sys_user (created_by);
CREATE        INDEX sys_user_index11 ON sys_user (updated_by);

CREATE        INDEX sys_user_index12 ON sys_user (created_at);
CREATE        INDEX sys_user_index13 ON sys_user (updated_at);
CREATE        INDEX sys_user_index14 ON sys_user (last_type_login);
CREATE        INDEX sys_user_index15 ON sys_user using gin (history_success_login);
CREATE        INDEX sys_user_index16 ON sys_user using gin (history_error_login);


CREATE OR REPLACE FUNCTION tgb_sys_user() returns trigger as
$$
DECLARE
	_historyPass type_identity_history_passw;
BEGIN
	IF(TG_OP = 'DELETE') THEN
		RETURN OLD;
	END IF;


	IF(TG_OP = 'INSERT') THEN
		NEW.auth_key    := _uniqid(TG_TABLE_NAME, 'auth_key'    , 16);
		NEW.passw_token := _uniqid(TG_TABLE_NAME, 'passw_token' , 16);
		NEW.created_at  := CURRENT_TIMESTAMP;
		NEW.updated_at  := NULL;

		IF(NEW.passw is null) THEN
			NEW.passw_force_change := true;
		END IF;

		NEW.passw         := crypt(NEW.passw, gen_salt('bf'));
		NEW.passw_history := ARRAY[(NEW.passw, current_timestamp::date)::type_identity_history_passw];
	END IF;

	IF(TG_OP = 'UPDATE') THEN
		NEW.id         := OLD.id;
		NEW.auth_key   := OLD.auth_key;
		NEW.created_at := OLD.created_at;
		NEW.updated_at := CURRENT_TIMESTAMP;

		IF(NEW.passw_token <> OLD.passw_token) THEN
			NEW.passw_token := _uniqid(TG_TABLE_NAME, 'passw_token' , 16);
		END IF;
	END IF;

	return NEW;
END;
$$
language plpgsql;


CREATE TRIGGER tgb_sys_user
BEFORE INSERT OR UPDATE OR DELETE
ON sys_user
FOR EACH ROW
EXECUTE PROCEDURE tgb_sys_user();


-- sys_user_functions:

CREATE OR REPLACE FUNCTION  _add_user(
	tb_relation           TEXT,
	created_by           integer,
	email                 character varying(50),
	first_name               character varying(50),
	last_name             character varying(50),
	status_acceso         character varying(20),
	passw                 character varying(70),
	passw_timelife        int, -- nro dias antes de vencerse el password
	passw_force_change boolean,
	roles                 INT[]
) RETURNS type_status_row AS
$BODY$
DECLARE
	_sql    TEXT;
	_count  integer;
	_status type_status_row;
	_rc     RECORD;
	_cksa boolean;
	_dateExpire date    default null;
	_created_by integer default null;
BEGIN
	IF(_ck_email(email) = false) THEN
		_status.status_op   = false;
		_status.status_code = 'INVALID_EMAIL';
		return _status;
	END IF;

	-- @check if user exist and check users profile && rules
	IF(created_by is not null) THEN
	END IF;

	-- check if exist users:
	BEGIN
		_sql:= format('SELECT * FROM %s WHERE lower(email)=lower(%L)', tb_relation, email);
		execute _sql into _rc;
		IF(_rc.id IS NOT NULL) THEN
			--_status.pk          = _rc.id;
			_status.status_op   = false;
			_status.status_code = 'RECORD_EXIST';
			_status.row_value   = to_jsonb(_rc);
			return _status;
		END IF;
	END;

	IF(passw_force_change is null) THEN
		passw_force_change = true;
	END IF;

	IF(passw_force_change = FALSE and status_acceso <> 'INACTIVE') THEN
		status_acceso = 'ACTIVE';
	END IF;

	-- check status_acceso
	select true into _cksa  WHERE UPPER(status_acceso) in('ACTIVE', 'INACTIVE', 'EMAIL_VERIFY');
	IF(_cksa <> TRUE) THEN
		_status.status_op   = false;
		_status.status_code = 'INVALID_STATUS_ACCESS';
		return _status;
	END IF;

	IF(passw_timelife > 0) THEN
		_dateExpire := (CURRENT_TIMESTAMP + CAST( passw_timelife::TEXT || 'days' AS INTERVAL));
	END IF;

	_sql := format('
			INSERT INTO %s
			(email, first_name, last_name, status_acceso, passw, passw_expire_on, passw_force_change, roles, created_by) values
			(%L,%L,%L,%L,%L,%L,%L,%L,%L) returning *
		',
		tb_relation,
		lower(email),
		initcap(lower(_trim(first_name))),
		initcap(lower(_trim(last_name))),
		UPPER(status_acceso),
		passw,
		_dateExpire,
		passw_force_change,
		_array_unique(roles),
		created_by
	);

	execute _sql into _rc;
	_status.pk          = _rc.id;
	_status.status_op   = true;
	_status.status_code = 'OK';
	_status.row_value   = to_jsonb(_rc);
	return _status;
END;
$BODY$
LANGUAGE plpgsql;

--
