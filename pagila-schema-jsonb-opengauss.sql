--
-- openGauss-compatible schema for JSONB tables (Oracle compatibility mode)
-- Adapted from pagila-schema-jsonb.sql: GENERATED ALWAYS AS IDENTITY → CREATE SEQUENCE + nextval DEFAULT
--

SET statement_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;

SET default_tablespace = '';

CREATE SEQUENCE public.newaptdata_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.packages_apt_postgresql_org (
    id integer NOT NULL DEFAULT nextval('public.newaptdata_id_seq'::regclass),
    last_updated timestamp without time zone DEFAULT now(),
    aptdata jsonb
);

ALTER TABLE public.packages_apt_postgresql_org OWNER TO gaussdb;

CREATE SEQUENCE public.newyumdata_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE public.packages_yum_postgresql_org (
    id integer NOT NULL DEFAULT nextval('public.newyumdata_id_seq'::regclass),
    last_updated timestamp without time zone DEFAULT now(),
    yumdata jsonb
);

ALTER TABLE public.packages_yum_postgresql_org OWNER TO gaussdb;
