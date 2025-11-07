-- Create sales schema
CREATE SCHEMA IF NOT EXISTS iceberg.sales;

-- Sales transactions table
CREATE TABLE iceberg.sales.transactions (
    transaction_id BIGINT,
    customer_id BIGINT,
    product_id VARCHAR(20),
    product_name VARCHAR(100),
    product_category VARCHAR(50),
    quantity INTEGER,
    unit_price DECIMAL(10,2),
    amount DECIMAL(12,2),
    transaction_date DATE,
    store_location VARCHAR(50),
    sales_rep VARCHAR(50)
) WITH (
    location = 's3a://warehouse/sales/transactions'
);

-- Customer data table
CREATE TABLE iceberg.sales.customers (
    customer_id BIGINT,
    customer_name VARCHAR(100),
    email VARCHAR(100),
    phone VARCHAR(20),
    city VARCHAR(50),
    state VARCHAR(30),
    registration_date DATE
) WITH (
    location = 's3a://warehouse/sales/customers'
);

-- Insert sample sales transactions
INSERT INTO iceberg.sales.transactions VALUES
(1001, 101, 'LAPTOP001', 'Business Laptop Pro', 'Electronics', 1, 1299.99, 1299.99, DATE '2024-01-15', 'New York', 'John Smith'),
(1002, 102, 'PHONE001', 'Smartphone X', 'Electronics', 2, 899.99, 1799.98, DATE '2024-01-15', 'Los Angeles', 'Sarah Johnson'),
(1003, 103, 'DESK001', 'Standing Desk', 'Furniture', 1, 599.99, 599.99, DATE '2024-01-16', 'Chicago', 'Mike Wilson'),
(1004, 104, 'CHAIR001', 'Ergonomic Chair', 'Furniture', 3, 299.99, 899.97, DATE '2024-01-16', 'Houston', 'Lisa Brown'),
(1005, 105, 'MONITOR001', '4K Monitor', 'Electronics', 2, 449.99, 899.98, DATE '2024-01-17', 'Phoenix', 'David Lee'),
(1006, 106, 'TABLET001', 'Tablet Pro', 'Electronics', 1, 699.99, 699.99, DATE '2024-01-17', 'Philadelphia', 'Emma Davis'),
(1007, 107, 'LAMP001', 'LED Desk Lamp', 'Furniture', 4, 79.99, 319.96, DATE '2024-01-18', 'San Antonio', 'James Miller'),
(1008, 108, 'KEYBOARD001', 'Mechanical Keyboard', 'Electronics', 1, 149.99, 149.99, DATE '2024-01-18', 'San Diego', 'Anna Garcia'),
(1009, 109, 'MOUSE001', 'Wireless Mouse', 'Electronics', 5, 59.99, 299.95, DATE '2024-01-19', 'Dallas', 'Robert Martinez'),
(1010, 110, 'BOOKSHELF001', 'Modern Bookshelf', 'Furniture', 1, 399.99, 399.99, DATE '2024-01-19', 'San Jose', 'Jennifer Rodriguez');

-- Insert sample customers
INSERT INTO iceberg.sales.customers VALUES
(101, 'Alice Johnson', 'alice.johnson@email.com', '555-0101', 'New York', 'NY', DATE '2023-06-15'),
(102, 'Bob Smith', 'bob.smith@email.com', '555-0102', 'Los Angeles', 'CA', DATE '2023-07-20'),
(103, 'Carol Davis', 'carol.davis@email.com', '555-0103', 'Chicago', 'IL', DATE '2023-08-10'),
(104, 'David Wilson', 'david.wilson@email.com', '555-0104', 'Houston', 'TX', DATE '2023-09-05'),
(105, 'Eva Brown', 'eva.brown@email.com', '555-0105', 'Phoenix', 'AZ', DATE '2023-10-12'),
(106, 'Frank Miller', 'frank.miller@email.com', '555-0106', 'Philadelphia', 'PA', DATE '2023-11-18'),
(107, 'Grace Lee', 'grace.lee@email.com', '555-0107', 'San Antonio', 'TX', DATE '2023-12-03'),
(108, 'Henry Garcia', 'henry.garcia@email.com', '555-0108', 'San Diego', 'CA', DATE '2024-01-08'),
(109, 'Ivy Martinez', 'ivy.martinez@email.com', '555-0109', 'Dallas', 'TX', DATE '2024-01-14'),
(110, 'Jack Rodriguez', 'jack.rodriguez@email.com', '555-0110', 'San Jose', 'CA', DATE '2024-01-20');
