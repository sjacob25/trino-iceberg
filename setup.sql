-- Create schema and sample table
CREATE SCHEMA IF NOT EXISTS iceberg.demo;

CREATE TABLE iceberg.demo.orders (
    order_id BIGINT,
    customer_id BIGINT,
    order_date DATE,
    total_amount DECIMAL(10,2)
) WITH (
    location = 's3a://warehouse/demo/orders'
);

-- Insert sample data
INSERT INTO iceberg.demo.orders VALUES
(1, 101, DATE '2024-01-15', 150.50),
(2, 102, DATE '2024-01-16', 275.00),
(3, 103, DATE '2024-01-17', 89.99);
