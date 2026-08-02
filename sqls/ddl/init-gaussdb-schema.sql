-- Create gaussdb schema to prevent PostgreSQL JDBC driver error:
-- "ERROR: schema 'gaussdb' does not exist"
-- The driver defaults to SET search_path TO "$user", public
CREATE SCHEMA IF NOT EXISTS gaussdb;
