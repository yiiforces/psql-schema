drop schema public cascade;
create schema public;
create EXTENSION hstore;
create EXTENSION pgcrypto;
create EXTENSION unaccent;

create type type_status as (
    status_op   boolean,
    status_code TEXT
);

create type type_status_row as (
    pk          bigint,
    status_op   boolean,
    status_code TEXT,
    row_value  jsonb
);

create type type_conf as (
    id          integer,
    category    TEXT,
    key_conf    TEXT,
    description TEXT,
    value       TEXT,
    status_op   boolean,
    status_code TEXT
);


CREATE OR REPLACE FUNCTION _array_unique (ANYARRAY) RETURNS ANYARRAY AS
$BODY$
  SELECT ARRAY(
    SELECT DISTINCT $1[s.i]
    FROM generate_series(array_lower($1,1), array_upper($1,1)) AS s(i)
    ORDER BY 1
  );
$BODY$ LANGUAGE SQL STRICT;

CREATE OR REPLACE FUNCTION _array_merge (a1 ANYARRAY, a2 ANYARRAY) RETURNS ANYARRAY AS
$BODY$
    SELECT ARRAY_AGG(x ORDER BY x)
    FROM (
        SELECT DISTINCT UNNEST($1 || $2) AS x
    ) s;
$BODY$ LANGUAGE SQL STRICT;

CREATE OR REPLACE FUNCTION _rand_str(integer)
RETURNS VARCHAR(255) AS
$BODY$
    DECLARE
        randStr     TEXT:='';
        prefixAlpha TEXT:='';
    BEGIN
        IF($1 < 1) THEN
            return randStr;
        END IF;

        IF($1 > 255) THEN
            $1:= 255;
            RAISE NOTICE 'truncate to 255';
        END IF;

        -- generate prefix [a-z{3}]
        SELECT
            array_to_string(ARRAY(SELECT chr((97 + round(random() * 25)) :: integer)
        FROM generate_series(1, 3)), '')::text INTO prefixAlpha;

        LOOP
            EXIT WHEN LENGTH(randStr) > $1;
            randStr := randStr || MD5(random()::text);
        END LOOP;

        return UPPER(SUBSTRING ( (prefixAlpha  || randStr), 1, $1));
    END;
$BODY$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _rand_int(low INT ,high INT) RETURNS INT AS
$BODY$
    BEGIN
       RETURN floor(random()* (high-low + 1) + low);
    END;
$BODY$ language 'plpgsql' STRICT;

CREATE OR REPLACE FUNCTION _trim(TEXT)
RETURNS TEXT AS
$BODY$
    BEGIN
        IF($1 is null) THEN
            return null;
        END IF;

        return trim(regexp_replace($1, '(\s+\s)+', ' ', 'gi'));
    END;
$BODY$
LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION _slug("value" TEXT) RETURNS TEXT AS
$BODY$
  -- removes accents (diacritic signs) from a given string --
  WITH "unaccented" AS (
    SELECT unaccent("value") AS "value"
  ),
  -- lowercases the string
  "lowercase" AS (
    SELECT lower("value") AS "value"
    FROM "unaccented"
  ),
  -- replaces anything that's not a letter, number, hyphen('-'), or underscore('_') with a hyphen('-')
  "hyphenated" AS (
    SELECT regexp_replace("value", '[^a-z0-9\\-_\/]+', '-', 'gi') AS "value"
    FROM "lowercase"
  ),
  -- trims hyphens('-') if they exist on the head or tail of the string
  "trimmed" AS (
    SELECT regexp_replace(regexp_replace("value", '\\-+$', ''), '^\\-', '') AS "value"
    FROM "hyphenated"
  ),

  "trimmed2" AS (
    SELECT regexp_replace("value", '(\/){2,}', '/', 'g') AS "value"
    FROM "trimmed"
  )

  SELECT "value" FROM "trimmed2";
$BODY$ LANGUAGE SQL STRICT IMMUTABLE;

CREATE OR REPLACE FUNCTION _slug("value" TEXT, "extension" TEXT) RETURNS TEXT AS
$BODY$
    select lower(( _slug("value") || '.' || "extension"));
$BODY$ LANGUAGE SQL STRICT IMMUTABLE;


CREATE OR REPLACE FUNCTION _ck_email(text) returns BOOLEAN AS
    'select $1 ~ ''^[^@\s]+@[^@\s]+(\.[^@\s]+)+$'' as result
' LANGUAGE sql;



CREATE OR REPLACE FUNCTION _uniqid(tbName text, columnName text, length int) returns TEXT as
$$
DECLARE
_sql     TEXT;
_randStr TEXT;
_count   int;
BEGIN
    IF (length < 16) then
        length := 16;
    end if;

    LOOP
        _randStr := _rand_str(length);
        _sql     := format('select count(id) from %s where %s=%L', tbName, columnName, _randStr);
        -- raise notice '%', _sql;
        execute _sql into _count;
        IF(_count = 0) THEN EXIT;
        END IF;
    END LOOP;

    return _randStr;
END;
$$
LANGUAGE plpgsql;



create table cache_schema(
    table_name  varchar(255) not null unique,
    num_rows    bigint  not null default 0,
    revision    integer not null default 0, -- time
    primary key (table_name)
);

CREATE UNIQUE INDEX cache_schema_index01 ON cache_schema (table_name);
CREATE        INDEX cache_schema_index02 ON cache_schema (num_rows);
CREATE        INDEX cache_schema_index03 ON cache_schema (revision);


CREATE OR REPLACE function register_cache() RETURNS trigger AS
$BODY$
DECLARE
    _rc  RECORD;
    _toInsert BOOLEAN := true;
BEGIN

    SELECT * into _rc FROM cache_schema WHERE table_name = TG_TABLE_NAME;
    IF(_rc is  not null) THEN
    _toInsert := false;
    END IF;

    EXECUTE format('select count(*), EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)::INT from %s', TG_TABLE_NAME) into _rc.num_rows, _rc.revision;

    IF(_toInsert is true ) THEN
        INSERT into cache_schema  (num_rows, revision, table_name ) values (_rc.num_rows, _rc.revision, TG_TABLE_NAME);
    ELSE
    UPDATE cache_schema SET
        num_rows     = _rc.num_rows,
        revision     = _rc.revision
    WHERE table_name = TG_TABLE_NAME;
    END IF;

    IF(TG_OP = 'DELETE') THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END
$BODY$
language plpgsql;
