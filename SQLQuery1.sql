--View total sales by region

SELECT Region, SUM(Sales) AS Total_Sales, SUM(Profit) AS Total_Profit
FROM sales_data
GROUP BY Region
ORDER BY Total_Sales DESC;

--Find top-selling products
SELECT Product, SUM(Sales) AS Total_Sales
FROM sales_data
GROUP BY Product
ORDER BY Total_Sales DESC ;

--Monthly sales trend
SELECT DATENAME(MONTH, Order_Date) AS Month, SUM(Sales) AS Total_Sales
FROM sales_data
GROUP BY DATENAME(MONTH, Order_Date), MONTH(Order_Date)
ORDER BY MONTH(Order_Date);

