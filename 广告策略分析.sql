

-- 第1步：检查导入行数。
SELECT 'source_notes' AS table_name, COUNT(*) AS row_count FROM source_notes
UNION ALL SELECT 'campaign_summary', COUNT(*) FROM campaign_summary
UNION ALL SELECT 'ad_daily', COUNT(*) FROM ad_daily
UNION ALL SELECT 'search_terms', COUNT(*) FROM search_terms
UNION ALL SELECT 'listing_records', COUNT(*) FROM listing_records;

-- 第2步：检查重复和订单合计。
SELECT period, campaign_name, COUNT(*) AS n
FROM campaign_summary GROUP BY period, campaign_name HAVING COUNT(*) > 1;
SELECT * FROM campaign_summary WHERE total_orders <> ad_orders + organic_orders;

-- 第3步：按时期汇总。
CREATE TEMPORARY TABLE period_totals AS
SELECT period,
 CASE WHEN period = '预算调整前' THEN 14 ELSE 16 END AS days,
 SUM(ad_spend) AS ad_spend, SUM(ad_sales) AS ad_sales,
 SUM(total_sales) AS total_sales, SUM(clicks) AS clicks,
 SUM(ad_orders) AS ad_orders, SUM(organic_orders) AS organic_orders
FROM campaign_summary GROUP BY period;

-- 第4步：日均
SELECT period,
 ROUND(ad_spend/days,2) AS daily_spend,
 ROUND(ad_sales/days,2) AS daily_ad_sales,
 ROUND(total_sales/days,2) AS daily_total_sales,
 ROUND((total_sales*0.34-ad_spend)/days,2) AS daily_profit,
 ROUND(organic_orders/days,2) AS daily_organic_orders,
 ROUND(ad_sales/NULLIF(ad_spend,0),2) AS roas,
 ROUND(100*ad_spend/NULLIF(ad_sales,0),2) AS acos_pct,
 ROUND(100*ad_spend/NULLIF(total_sales,0),2) AS tacos_pct,
 ROUND(ad_spend/NULLIF(clicks,0),2) AS cpc,
 ROUND(100*ad_orders/NULLIF(clicks,0),2) AS cvr_pct,
 ROUND(ad_sales/NULLIF(ad_orders,0),2) AS aov
FROM period_totals;


-- 第5步：找低效活动
SELECT campaign_type,
 ROUND(ad_sales/NULLIF(ad_spend,0),2) AS roas,
 ROUND(100*ad_spend/NULLIF(ad_sales,0),2) AS acos_pct,
 ROUND((ad_sales*0.34-ad_spend)/16,2) AS daily_ad_profit,
 ROUND((total_sales*0.34-ad_spend)/16,2) AS daily_total_profit
FROM campaign_summary WHERE period='预算调整后'
ORDER BY daily_total_profit;


-- 第6步：新增日均花费流向哪里？先按活动算前后差额，再汇总占比。
CREATE TEMPORARY TABLE spend_change AS
SELECT campaign_type,
 SUM(CASE WHEN period='预算调整后' THEN ad_spend/16 ELSE -ad_spend/14 END) AS daily_increase
FROM campaign_summary GROUP BY campaign_type;
SELECT * FROM spend_change ORDER BY daily_increase DESC;
SELECT ROUND(100*SUM(CASE WHEN campaign_type IN ('SP-广泛','SP-自动','SP-竞品')
 THEN daily_increase ELSE 0 END)/NULLIF(SUM(daily_increase),0),2) AS low_efficiency_share_pct
FROM spend_change;

-- 第7步：排查搜索词
SELECT search_term, clicks, ad_orders, ad_spend,
 ROUND(ad_sales/NULLIF(ad_spend,0),2) AS roas
FROM search_terms ORDER BY ad_spend DESC;
SELECT COUNT(*) AS zero_order_terms, SUM(ad_spend) AS zero_order_spend
FROM search_terms WHERE ad_orders=0;


-- 第8步：查看页面事件。
SELECT * FROM listing_records ORDER BY record_date;

-- 第9步：设置试行花费。
CREATE TEMPORARY TABLE trial_budget AS
SELECT campaign_type, ad_spend/16 AS current_daily_spend,
 CASE WHEN campaign_type IN ('SP-广泛','SP-自动') THEN 0.5
 WHEN campaign_type='SP-竞品' THEN 0 ELSE 1 END AS keep_ratio
FROM campaign_summary WHERE period='预算调整后';
SELECT campaign_type, ROUND(current_daily_spend,2) AS current_daily_spend,
 keep_ratio, ROUND(current_daily_spend*keep_ratio,2) AS target_daily_spend
FROM trial_budget;
SELECT ROUND(SUM(current_daily_spend*keep_ratio),2) AS daily_target,
 ROUND(SUM(current_daily_spend*keep_ratio)*14,2) AS total_14_days,
 ROUND(100*(1-SUM(current_daily_spend*keep_ratio)/SUM(current_daily_spend)),2) AS reduction_pct
FROM trial_budget;


-- 第10步：核对日表
CREATE TEMPORARY TABLE daily_totals AS
SELECT period, campaign_name, SUM(ad_spend) AS spend
FROM ad_daily GROUP BY period, campaign_name;
SELECT s.period, s.campaign_name, s.ad_spend AS summary_spend,
 d.spend AS daily_table_spend, d.spend-s.ad_spend AS difference
FROM campaign_summary AS s LEFT JOIN daily_totals AS d
ON s.period=d.period AND s.campaign_name=d.campaign_name;
