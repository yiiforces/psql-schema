
CREATE TABLE config(
	id            serial NOT NULL,
	category      text,
	key_conf    character varying(100) NOT NULL,
	description   text,
	default_value text,
	current_value text,
	CONSTRAINT pk_conf PRIMARY KEY (id)
);

CREATE UNIQUE INDEX config_index01 ON config (id);
CREATE        INDEX config_index02 ON config (key_conf);
CREATE        INDEX config_index03 ON config (description);
CREATE        INDEX config_index04 ON config (default_value);
CREATE        INDEX config_index05 ON config (current_value);

CREATE OR REPLACE FUNCTION  _has_conf(text, text) RETURNS type_status AS
$BODY$
	DECLARE
		_count integer;
		_status type_status;
	BEGIN
		select count(*) into _count from config
		where
			category       = $1
			and key_conf	 = $2;

		IF(_count = 0) THEN
			select
				false
				,'RECORD_NOT_FOUND' into _status;
		ELSE
			select
				true
				,'SUCCESS' into _status;
		END IF;

		return _status;
	END;
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION  _get_conf(text, text) RETURNS type_conf AS
$BODY$
	DECLARE
		_conf   type_conf;
		_status type_status;
	BEGIN

		select * into _status from _has_conf($1,$2);
		_conf.category    = $1;
		_conf.key_conf    = $2;
		_conf.status_op   = _status.status_op;
		_conf.status_code = _status.status_code;

		IF(_status.status_op = false) THEN
			return _conf;
		END IF;

		select id ,description
		,(
			case
				WHEN current_value is not null THEN current_value
				ELSE default_value END
		) as value
		into _conf.id, _conf.description, _conf.value from config
		where
			category     = $1
			and key_conf = $2;

		RAISE NOTICE '%', _conf;
		return _conf;
	END;
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _set_conf(_cat text, _key text, _current text) RETURNS type_conf AS
$BODY$
	DECLARE
		_conf   type_conf;
		_status type_status;
	BEGIN
		_conf.category  = _cat;
		_conf.key_conf  = _key;
		_conf.value     = _current;

		--check exist:
		select * into _status from _has_conf(_cat, _key);
		IF(_status.status_op = FALSE) THEN
			_conf.status_op   = false;
			_conf.status_code = _status.status_code;
			return _conf;
		END IF;

		update config set current_value =_current
			where category   = _cat
			and key_conf   = _key
			RETURNING id , description into _conf.id, _conf.description;

		IF(_current is null) THEN
			select default_value into _conf.value from config  where category   = _cat and key_conf = _key;
		END IF;

		_conf.status_op   = true;
		_conf.status_code = 'SUCCESS_UPDATE_RECORD';
		return _conf;
	END;
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _add_conf(_cat text, _key text, _desc text, _default text, _current text) RETURNS type_conf AS
$BODY$
	DECLARE
		_conf   type_conf;
		_status type_status;
	BEGIN
		_conf.category    = _cat;
		_conf.key_conf    = _key;
		_conf.description = _desc;

		IF(_current is NULL) THEN
			_conf.value = _default;
		ELSE
			_conf.value = _current;
		END IF;

		--check exist:
		select * into _status from _has_conf(_cat, _key);
		IF(_status.status_op = TRUE) THEN
			select * from _set_conf(_cat,_key, _current) into _conf;
			return _conf;
		END IF;

		insert into config (category, key_conf, description, default_value, current_value)
		values (_conf.category, _conf.key_conf, _conf.description, _default, _current) RETURNING id into _conf.id;
		_conf.status_op   = true;
		_conf.status_code = 'SUCCESS_INSERT_RECORD';
		return _conf;
	END;
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _rm_conf(_cat text, _key text) RETURNS type_conf AS
$BODY$
	DECLARE
		_conf type_conf;
	BEGIN
		SELECT * into _conf FROM _get_conf(_cat, _key);
		IF(_conf.status_op = false) THEN
			return _conf;
		END if;

		DELETE FROM config WHERE category =_cat AND key_conf = _key;
		_conf.status_code = 'SUCCESS_DELETE_RECORD';
		return _conf;
	END;
$BODY$
LANGUAGE plpgsql;
