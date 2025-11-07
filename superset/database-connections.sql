-- Database connections to add in Superset UI

-- 1. Trino (Main Iceberg)
-- URI: trino://trino:8080/iceberg
-- Display Name: Trino Iceberg

-- 2. Trino HR Catalog  
-- URI: trino://trino:8080/iceberg_hr
-- Display Name: Trino HR

-- 3. Trino PostgreSQL Catalog
-- URI: trino://trino:8080/postgresql
-- Display Name: Trino PostgreSQL

-- 4. Direct PostgreSQL
-- URI: postgresql://iceberg:password@postgres:5432/iceberg
-- Display Name: PostgreSQL Direct

-- 5. Trino Memory Catalog
-- URI: trino://trino:8080/memory
-- Display Name: Trino Memory
