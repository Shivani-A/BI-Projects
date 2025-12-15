###1. Retrieve the number of unique customers by country and city along with their average purchase value.
Select 
    c.Country,
    c.City,
    count(distinct c.Customer_ID) as unique_customers,
    Avg(t.Line_Total) as avg_purchase_value
From customers c
Left Join transactions t 
    On c.Customer_ID = t.Customer_ID
Group By 
    c.Country,
    c.City
Order by 
    c.Country,
    c.City;

#2. Calculate the percentage of returns compared to total transactions and track how it changes monthly.
Select
    date_format(t.Date, '%Y-%m') as yearmonth,
    count(*) as total_transactions,
    sum(case when t.Transaction_Type = 'Return' then 1 else 0 end) as return_transactions,
    round(
        (sum(case when t.Transaction_Type = 'Return' then 1 else 0 end) 
         / count(*)) * 100, 
        2
    ) as return_percentage
from transactions t
group by DATE_FORMAT(t.Date, '%Y-%m')
order by yearmonth;

#3. Identify the top categories by total revenue and their share in overall sales.
Select 
    p.Category,
    sum(t.Line_Total) as category_revenue,
    round(
        (sum(t.Line_Total) / total.total_revenue) * 100,
        2
    ) as revenue_share_percentage
from transactions t
join products p 
    on t.Product_ID = p.Product_ID
cross join (
    select SUM(Line_Total) as total_revenue
    from transactions
) as total
group by p.Category, total.total_revenue
order by category_revenue desc;

## calculated for subcategories as well
Select 
    p.Sub_Category,
    sum(t.Line_Total) as subcategory_revenue,
    round(
        (sum(t.Line_Total) / total.total_revenue) * 100,
        2
    ) as revenue_share_percentage
From transactions t
Join products p 
    on t.Product_ID = p.Product_ID
cross join (
    Select sum(Line_Total) as total_revenue
    From transactions
) as total
Group by p.Sub_Category, total.total_revenue
Order by subcategory_revenue desc;

##4. Compare total sales volume and average basket value across payment methods.
Select
    t.Payment_Method,
    sum(t.Line_Total) as total_sales_volume,
    avg(t.Invoice_Total) as avg_basket_value
from transactions t
Where t.Transaction_Type = 'sale'   
Group by t.Payment_Method
Order by total_sales_volume desc;

##5. Compare sales volume and revenue during discount periods versus non-discount periods.
Select
    case 
        when t.Discount > 0 then 'Discount Period'
        else 'Non-Discount Period'
    end as period_type,
    count(*) as total_transactions,
    sum(t.Line_Total) as total_revenue
from transactions t
where t.Transaction_Type = 'sale'
group by period_type;

##6. Measure the proportion of new versus repeat customers each month along with their average spend.
with first_purchase as (
    select
        Customer_ID,
        min(date_format(date, '%Y-%m-01')) as First_Purchase_Month
    from transactions
    group by Customer_ID
),
customer_monthly as (
    select
        Customer_ID,
        date_format(date, '%Y-%m-01') as Txn_Month,
        sum(Invoice_Total) as Monthly_Spend
    from transactions
    group by Customer_ID, date_format(date, '%Y-%m-01')
)
select
    cm.Txn_Month as month,
    sum(case when cm.Txn_Month = fp.First_Purchase_Month then 1 else 0 end) as New_Customers,
    sum(case when cm.Txn_Month > fp.First_Purchase_Month then 1 else 0 end) as Repeat_Customers,
    sum(case when cm.Txn_Month = fp.First_Purchase_Month then 1 else 0 end) 
        / count(distinct cm.Customer_ID) as New_Proportion,
    sum(case when cm.Txn_Month > fp.First_Purchase_Month then 1 else 0 end)
        / count(distinct cm.Customer_ID) as Repeat_Proportion,

    avg(case when cm.Txn_Month = fp.First_Purchase_Month then cm.Monthly_Spend end) as Avg_Spend_New,
    avg(case when cm.Txn_Month > fp.First_Purchase_Month then cm.Monthly_Spend end) as Avg_Spend_Repeat

from customer_monthly cm
join first_purchase fp using (Customer_ID)
group by cm.Txn_Month
order by cm.Txn_Month;

###7. Identify the top and bottom stores by revenue and return rates.
with store_stats as (
    select
        s.Store_ID,
        s.Store_Name,
        s.City,
        s.Country,
        sum(case when t.Transaction_Type = 'Sale' then t.Invoice_Total else 0 end) as Revenue,
        sum(case when t.Transaction_Type = 'Return' then 1 else 0 end) as Return_Count,
        count(*) as Total_Transactions,
        sum(case when t.Transaction_Type = 'Return' then 1 else 0 end) * 1.0 / count(*) as Return_Rate
    from stores s
    left join transactions t on s.Store_ID = t.Store_ID
    group by s.Store_ID, s.Store_Name, s.City, s.Country
),
ranked as (
    select
        *,
        row_number() over (order by Revenue desc) as Top_Revenue_Rank,
        row_number() over (order by Revenue asc)  as Bottom_Revenue_Rank,
        row_number() over (order by Return_Rate desc) as Top_Return_Rank,
        row_number() over (order by Return_Rate asc)  as Bottom_Return_Rank
    from store_stats
)
select
    case
        when Top_Revenue_Rank = 1 then 'Top Revenue'
        when Bottom_Revenue_Rank = 1 then 'Bottom Revenue'
        when Top_Return_Rank = 1 then 'Top Return Rate'
        when Bottom_Return_Rank = 1 then 'Bottom Return Rate'
    end as Category,
    Store_ID,
    Store_Name,
    City,
    Country,
    Revenue,
    Return_Count,
    Total_Transactions,
    Return_Rate
from ranked
where Top_Revenue_Rank = 1
   or Bottom_Revenue_Rank = 1
   or Top_Return_Rank = 1
   or Bottom_Return_Rank = 1
order by Category;

###8. Segment products into price bands and analyze their contribution to total revenue and returns.
Select
    case 
        when t.Unit_Price < 50 then 'Low'
        when t.Unit_Price between 50 and 150 then 'Mid'
        when t.Unit_Price between 150 and 300 then 'Upper-Mid'
        else 'Premium'
    end as Price_Band,

    sum(case when t.Transaction_Type = 'Sale' then t.Line_Total else 0 end) as Revenue,
    sum(case when t.Transaction_Type = 'Return' then t.Line_Total else 0 end) as Return_Value,

    sum(case when t.Transaction_Type = 'Return' then 1 else 0 end) /
    count(*) as Return_Rate,

   sum(case when t.Transaction_Type = 'Sale' then t.Line_Total else 0 end) /
    (select sum(Line_Total) from transactions where Transaction_Type = 'Sale') 
    as Revenue_Contribution,

    sum(case when t.Transaction_Type = 'Return' then t.Line_Total else 0 end) /
    (select sum(Line_Total) from transactions where Transaction_Type = 'Return')
    as Return_Contribution

from transactions t
group by Price_Band
order by Revenue desc;

##9. Calculate the average number of items and revenue per basket across different countries.
Select
    s.Country,
    avg(items_per_basket) as Avg_Items_Per_Basket,
    avg(revenue_per_basket) as Avg_Revenue_Per_Basket
from (
    select
        t.Invoice_ID,
        t.Store_ID,
        sum(t.Quantity) as items_per_basket,
        sum(t.Line_Total) as revenue_per_basket
    from transactions t
    group by t.Invoice_ID, t.Store_ID
) basket
join stores s on basket.Store_ID = s.Store_ID
group by s.Country
order by Avg_Revenue_Per_Basket desc;

##10. Analyze month-over-month revenue growth overall and for the top three categories.
#Overall Month-over-Month Revenue Growth
with monthly_overall as (
    select
        date_format(Date, '%Y-%m-01') as Month,
        sum(Line_Total) as Revenue
    from transactions
    group by date_format(Date, '%Y-%m-01')
)
select
    Month,
    Revenue,
    Revenue - lag(Revenue) over (order by Month) as MoM_Change,
    (Revenue - lag(Revenue) over (order by Month)) / lag(Revenue) over (order by Month) as MoM_Growth
from monthly_overall
order by Month;

#Top 3 Categories Month-over-Month Revenue Growth
with monthly_revenue as (
    select
        date_format(t.Date, '%Y-%m-01') as Month,
        p.Category,
        sum(t.Line_Total) as Revenue
    from transactions t
    join products p on t.Product_ID = p.Product_ID
    group by date_format(t.Date, '%Y-%m-01'), p.Category
),
top_categories as (
    select Category
    from monthly_revenue
    group by Category
    order by sum(Revenue) desc
    limit 3
)
select
    Month,
    Category,
    Revenue,
    Revenue - lag(Revenue) over (partition by Category order by Month) as MoM_Change,
    (Revenue - lag(Revenue) over (partition by Category order by Month)) / lag(Revenue) over (partition by Category order by Month) as MoM_Growth
from monthly_revenue
where Category in (select Category from top_categories)
order by Category, Month;


