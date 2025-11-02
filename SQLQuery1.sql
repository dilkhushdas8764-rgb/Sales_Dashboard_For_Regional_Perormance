-- Sales SQL Project generated from uploaded sales_data.xlsx
-- Database: SalesDB (MS SQL Server syntax)
IF DB_ID('SalesDB') IS NULL
    CREATE DATABASE SalesDB;
GO
USE SalesDB;
GO

-- 1) Staging table to load raw data from Excel
CREATE TABLE staging_sales_raw (
    [Order_ID] INT NULL,
    [Order_Date] DATE NULL,
    [Region] VARCHAR(50) NULL,
    [Country] VARCHAR(50) NULL,
    [Product] VARCHAR(50) NULL,
    [Category] VARCHAR(50) NULL,
    [Sales] DECIMAL(18,2) NULL,
    [Quantity] INT NULL,
    [Discount] DECIMAL(18,2) NULL,
    [Profit] DECIMAL(18,2) NULL
);
GO

-- NOTE: Use SQL Server Import Wizard or BULK INSERT from a CSV exported from Excel to populate staging_sales_raw.

-- 2) Cleaning and canonical tables
-- Example canonical tables: customers, products, stores, employees, dim_date, fact_sales

CREATE TABLE customers (
    customer_id INT IDENTITY(1,1) PRIMARY KEY,
    customer_name VARCHAR(200),
    customer_email VARCHAR(200),
    customer_city VARCHAR(100),
    customer_state VARCHAR(100)
);
GO

CREATE TABLE products (
    product_id INT IDENTITY(1,1) PRIMARY KEY,
    product_sku VARCHAR(100),
    product_name VARCHAR(200),
    category VARCHAR(100),
    unit_price DECIMAL(18,2)
);
GO

CREATE TABLE stores (
    store_id INT IDENTITY(1,1) PRIMARY KEY,
    store_name VARCHAR(200),
    store_city VARCHAR(100),
    store_state VARCHAR(100)
);
GO

CREATE TABLE employees (
    employee_id INT IDENTITY(1,1) PRIMARY KEY,
    employee_name VARCHAR(200),
    employee_role VARCHAR(100)
);
GO

CREATE TABLE dim_date (
    date_key INT PRIMARY KEY, -- YYYYMMDD
    the_date DATE,
    year INT,
    quarter INT,
    month INT,
    day INT,
    weekday INT,
    is_weekend BIT
);
GO

CREATE TABLE fact_sales (
    sale_id INT IDENTITY(1,1) PRIMARY KEY,
    sale_date DATE,
    date_key INT,
    customer_id INT FOREIGN KEY REFERENCES customers(customer_id),
    product_id INT FOREIGN KEY REFERENCES products(product_id),
    store_id INT FOREIGN KEY REFERENCES stores(store_id),
    employee_id INT FOREIGN KEY REFERENCES employees(employee_id),
    quantity INT,
    sales_amount DECIMAL(18,2),
    discount DECIMAL(18,2),
    net_amount AS (sales_amount - discount) PERSISTED
);
GO

-- 3) Example transformations from staging_sales_raw into canonical tables
-- Adjust column names in queries below to match your staging table columns.
-- Example: insert distinct customers

INSERT INTO customers (customer_name)
SELECT DISTINCT [Order_ID] FROM staging_sales_raw WHERE [Order_ID] IS NOT NULL;
GO

-- 4) Example analysis queries

-- Top 10 products by total sales
SELECT p.product_name, SUM(f.sales_amount) AS total_sales, SUM(f.quantity) AS total_qty
FROM fact_sales f
JOIN products p ON f.product_id = p.product_id
GROUP BY p.product_name
ORDER BY total_sales DESC;
GO

-- Monthly sales trend using window functions
WITH monthly AS (
    SELECT YEAR(sale_date) AS yr, MONTH(sale_date) AS mon, SUM(net_amount) AS month_sales
    FROM fact_sales
    GROUP BY YEAR(sale_date), MONTH(sale_date)
)
SELECT yr, mon, month_sales,
       LAG(month_sales) OVER (ORDER BY yr, mon) AS prev_month_sales,
       ROUND((month_sales - LAG(month_sales) OVER (ORDER BY yr, mon)) * 100.0 / NULLIF(LAG(month_sales) OVER (ORDER BY yr, mon),0),2) AS pct_change
FROM monthly
ORDER BY yr, mon;
GO

-- Running total and rank per product
SELECT f.sale_date, p.product_name, f.net_amount,
       SUM(f.net_amount) OVER (PARTITION BY p.product_name ORDER BY f.sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total,
       RANK() OVER (PARTITION BY p.product_name ORDER BY f.net_amount DESC) AS sale_rank
FROM fact_sales f
JOIN products p ON f.product_id = p.product_id;
GO

-- Correlated subquery: find sales where net_amount greater than average for that product
SELECT f.*, p.product_name
FROM fact_sales f
JOIN products p ON f.product_id = p.product_id
WHERE f.net_amount > (
    SELECT AVG(net_amount) FROM fact_sales WHERE product_id = f.product_id
);
GO

-- 5) Views, stored procedures, and a scalar function

CREATE VIEW vw_monthly_store_sales AS
SELECT s.store_name, YEAR(f.sale_date) AS yr, MONTH(f.sale_date) AS mon, SUM(f.net_amount) AS total_net
FROM fact_sales f
JOIN stores s ON f.store_id = s.store_id
GROUP BY s.store_name, YEAR(f.sale_date), MONTH(f.sale_date);
GO

CREATE PROCEDURE usp_GetTopCustomers
    @TopN INT = 10
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP (@TopN) c.customer_name, SUM(f.net_amount) AS total_spend
    FROM fact_sales f
    JOIN customers c ON f.customer_id = c.customer_id
    GROUP BY c.customer_name
    ORDER BY total_spend DESC;
END;
GO

CREATE FUNCTION udf_CalcDiscountPercent(@sale DECIMAL(18,2), @discount DECIMAL(18,2))
RETURNS DECIMAL(5,2)
AS
BEGIN
    RETURN CASE WHEN @sale = 0 THEN 0 ELSE ROUND(@discount * 100.0 / @sale,2) END;
END;
GO

-- 6) Indexes and performance

CREATE INDEX idx_fact_sales_date ON fact_sales(sale_date);
CREATE INDEX idx_fact_sales_product ON fact_sales(product_id);
CREATE INDEX idx_fact_sales_store_date ON fact_sales(store_id, sale_date);
GO

-- 7) Sample reporting queries

-- Year-over-year sales comparison
SELECT cur.year, cur.month,
       cur.month_sales AS current_month_sales,
       prev.month_sales AS prev_year_same_month_sales,
       ROUND((cur.month_sales - prev.month_sales) * 100.0 / NULLIF(prev.month_sales,0),2) AS yoy_pct_change
FROM (
    SELECT YEAR(sale_date) AS year, MONTH(sale_date) AS month, SUM(net_amount) AS month_sales
    FROM fact_sales
    GROUP BY YEAR(sale_date), MONTH(sale_date)
) cur
LEFT JOIN (
    SELECT YEAR(sale_date) AS year, MONTH(sale_date) AS month, SUM(net_amount) AS month_sales
    FROM fact_sales
    GROUP BY YEAR(sale_date), MONTH(sale_date)
) prev
ON cur.month = prev.month AND cur.year = prev.year + 1
ORDER BY cur.year, cur.month;
GO
