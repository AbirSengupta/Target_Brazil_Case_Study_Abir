-- =====================================================================
-- Target Brazil (2016-2018) Case Study: MySQL 8.0 solutions
-- Tables: customers, orders, order_items, payments, order_reviews,
--         products, sellers, geolocation  (database: olist_ecommerce)
-- order_reviews was loaded separately via Import_Order_Reviews.sql
-- =====================================================================

USE olist_ecommerce;

-- ---------------------------------------------------------------
-- 1. INITIAL EXPLORATION
-- ---------------------------------------------------------------

-- 1.1 Structure: row counts per table
SELECT 'customers' AS tbl, COUNT(*) AS rows_cnt FROM customers
UNION ALL SELECT 'orders',      COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'payments',    COUNT(*) FROM payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM order_reviews
UNION ALL SELECT 'products',    COUNT(*) FROM products
UNION ALL SELECT 'sellers',     COUNT(*) FROM sellers;
/* ANSWER:
   customers 99,441 | sellers 3,095 | orders 99,441 | order_items 112,650 | payments 103,886
   order_reviews 99,224 | products 32,951 | geolocation 1,000,163.
   Each order has one customer_id. Orders can have several items and several payments, so joins to
   order_items/payments return more rows than orders.
*/

-- Order status distribution
SELECT order_status, COUNT(*) AS orders
FROM orders GROUP BY order_status ORDER BY orders DESC;
/* ANSWER:
   97.0% of orders (96,478) were delivered. Shipped 1,107, canceled 625, unavailable 609,
   invoiced 314, processing 301, created 5, approved 2. Cancellations + unavailable are only ~1.2%.
*/

-- 1.2 Data types of the customers table
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = DATABASE() AND table_name = 'customers'
ORDER BY ordinal_position;
/* ANSWER:
   customer_id, customer_unique_id, customer_city and customer_state are text (VARCHAR/CHAR);
   customer_zip_code_prefix is an integer (INT).
   customer_id is unique per order; customer_unique_id identifies the actual person, so use it to count customers.
*/

-- 1.3 Time range of orders
SELECT MIN(order_purchase_timestamp) AS first_order,
       MAX(order_purchase_timestamp) AS last_order
FROM orders;
/* ANSWER:
   Orders were placed between 2016-09-04 21:15:19 and 2018-10-17 17:30:18 (about 25 months).
   2016 and Sep-Oct 2018 have very few orders, so full-year comparisons should use 2017 and Jan-Aug 2018.
*/

-- Geolocation characteristics: rows vs distinct zip prefixes
SELECT COUNT(*) AS total_rows,
       COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zips
FROM geolocation;
/* ANSWER:
   1,000,163 rows but only 19,015 distinct zip prefixes: each prefix has many coordinate rows.
*/

-- 1.4 Cities & states of customers who ordered in this period
SELECT COUNT(DISTINCT c.customer_city)  AS num_cities,
       COUNT(DISTINCT c.customer_state) AS num_states
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id;
/* ANSWER:
   Customers ordered from 4,119 cities across all 27 Brazilian states (26 states + the Federal District).
   Target reaches every state, but orders are concentrated in a few of them.
*/

-- ---------------------------------------------------------------
-- 2. IN-DEPTH EXPLORATION
-- ---------------------------------------------------------------

-- 2.1 Trend: orders per year and per year-month
SELECT YEAR(order_purchase_timestamp) AS yr, COUNT(*) AS orders
FROM orders GROUP BY yr ORDER BY yr;

SELECT YEAR(order_purchase_timestamp) AS yr,
       MONTH(order_purchase_timestamp) AS mon,
       COUNT(*) AS orders
FROM orders GROUP BY yr, mon ORDER BY yr, mon;
/* ANSWER:
   Orders grew strongly: 329 (2016, Sep-Dec only) -> 45,101 (2017) -> 54,011 (2018, to mid-Oct).
   Monthly orders climbed from 800 in Jan 2017 to a peak of 7,544 in Nov 2017, then held at
   about 6,200-7,300 a month through Aug 2018. Growth slowed in 2018: demand stabilised at a higher level.
*/

-- 2.2 Monthly seasonality (all years combined)
SELECT MONTH(order_purchase_timestamp) AS mon, COUNT(*) AS orders
FROM orders GROUP BY mon ORDER BY mon;
/* ANSWER:
   Months with the most orders: Aug (10,843), May (10,573), Jul (10,318). Orders are steady from May to August.
   Nov 2017 (7,544) is the biggest single month, driven by Black Friday.
   Sep-Dec look low mainly because there is almost no Sep-Dec 2018 data (16 orders in Sep, 4 in Oct, none after),
   so those months mostly reflect 2017 only. Compare the same months year on year rather than reading raw totals as seasonality.
*/

-- 2.3 Time of day
SELECT CASE
         WHEN HOUR(order_purchase_timestamp) BETWEEN 0  AND 6  THEN 'Dawn'
         WHEN HOUR(order_purchase_timestamp) BETWEEN 7  AND 12 THEN 'Morning'
         WHEN HOUR(order_purchase_timestamp) BETWEEN 13 AND 18 THEN 'Afternoon'
         ELSE 'Night'
       END AS time_of_day,
       COUNT(*) AS orders
FROM orders
GROUP BY time_of_day
ORDER BY orders DESC;
/* ANSWER:
   Afternoon (13-18h) 38,135 orders (38%) > Night (19-23h) 28,331 (28%) > Morning (7-12h) 27,733 (28%)
   > Dawn (0-6h) 5,242 (5%).
   Brazilian customers mostly order in the afternoon; promotions and ads work best from midday to late evening.
*/

-- ---------------------------------------------------------------
-- 3. EVOLUTION OF E-COMMERCE ORDERS
-- ---------------------------------------------------------------

-- 3.1 Month-on-month orders per state
SELECT c.customer_state,
       YEAR(o.order_purchase_timestamp)  AS yr,
       MONTH(o.order_purchase_timestamp) AS mon,
       COUNT(*) AS orders
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state, yr, mon
ORDER BY c.customer_state, yr, mon;
/* ANSWER:
   SP leads every month, peaking at 3,253 orders in Aug 2018. RJ (peak 1,048) and MG (peak 943) follow.
   Small northern states never exceed 11 orders a month (peaks: AC 8, AP 11, RR 6).
   Most states grew from 2017 to 2018, but AC, AL, AM, MA, PA, RO and SE had fewer orders in 2018
   (note 2018 data ends in Oct). The gap between SP and the rest stays very large.
*/

-- 3.2 Distribution of customers across states
SELECT customer_state,
       COUNT(DISTINCT customer_unique_id) AS customers,
       ROUND(100 * COUNT(DISTINCT customer_unique_id) /
             (SELECT COUNT(DISTINCT customer_unique_id) FROM customers), 2) AS pct
FROM customers
GROUP BY customer_state
ORDER BY customers DESC;
/* ANSWER:
   SP 40,302 customers (41.9%), RJ 12,384 (12.9%), MG 11,259 (11.7%), RS 5,277 (5.5%), PR 4,882 (5.1%).
   The top 3 states hold 66% of customers; the smallest are AC 77, AP 67, RR 45 (<0.1% each).
   The customer base is heavily concentrated in the Southeast.
*/

-- ---------------------------------------------------------------
-- 4. IMPACT ON ECONOMY
-- ---------------------------------------------------------------

-- 4.1 % increase in cost of orders, 2017 -> 2018 (Jan-Aug only)
SELECT
  ROUND(SUM(CASE WHEN YEAR(o.order_purchase_timestamp) = 2017 THEN p.payment_value ELSE 0 END), 2) AS cost_2017,
  ROUND(SUM(CASE WHEN YEAR(o.order_purchase_timestamp) = 2018 THEN p.payment_value ELSE 0 END), 2) AS cost_2018,
  ROUND(
    (SUM(CASE WHEN YEAR(o.order_purchase_timestamp) = 2018 THEN p.payment_value ELSE 0 END)
   - SUM(CASE WHEN YEAR(o.order_purchase_timestamp) = 2017 THEN p.payment_value ELSE 0 END))
   / SUM(CASE WHEN YEAR(o.order_purchase_timestamp) = 2017 THEN p.payment_value ELSE 0 END) * 100
  , 2) AS pct_increase
FROM orders o
JOIN payments p ON o.order_id = p.order_id
WHERE MONTH(o.order_purchase_timestamp) BETWEEN 1 AND 8;
/* ANSWER:
   Jan-Aug order cost (payment_value): 2017 = R$3,669,022.12, 2018 = R$8,694,733.84.
   Increase = 136.98%: order value more than doubled year on year.
*/

-- 4.2 Money movement: overall price vs freight
SELECT ROUND(SUM(price), 2) AS total_price,
       ROUND(SUM(freight_value), 2) AS total_freight,
       ROUND(100 * SUM(freight_value) / SUM(price + freight_value), 2) AS freight_share_pct
FROM order_items;
/* ANSWER:
   Total product price R$13,591,643.70; total freight R$2,251,909.54.
   Freight is 14.2% of what customers pay, so shipping cost is a large share of each order.
*/

-- 4.3 Total & average price and freight per state
SELECT c.customer_state,
       ROUND(SUM(oi.price), 2)         AS total_price,
       ROUND(AVG(oi.price), 2)         AS avg_price,
       ROUND(SUM(oi.freight_value), 2) AS total_freight,
       ROUND(AVG(oi.freight_value), 2) AS avg_freight
FROM order_items oi
JOIN orders o    ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY total_price DESC;
/* ANSWER:
   SP has the highest total sales (R$5.20M) but the lowest average price (R$109.65) and
   lowest average freight (R$15.15).
   Remote states buy fewer but more expensive items (e.g. PA avg price R$165.69) and pay far more freight
   (PA R$35.83, PE R$32.92). Customers far from SP pay more for both products and shipping.
*/

-- ---------------------------------------------------------------
-- 5. SALES, FREIGHT & DELIVERY TIME
-- ---------------------------------------------------------------

-- 5.1 Delivery time and estimated-vs-actual difference (per order)
SELECT order_id,
       DATEDIFF(order_delivered_customer_date, order_purchase_timestamp) AS time_to_deliver,
       DATEDIFF(order_estimated_delivery_date, order_delivered_customer_date) AS diff_estimated_delivery
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;
/* ANSWER:
   Across all 96,470 delivered orders:
      -  Average delivery time is 12.5 days. The median is 10 days, and the longest delivery took 210 days.
      -  On average, orders arrive 11.88 days before the estimated date.
      -  91.89% of orders arrive early, 1.34% arrive on the estimated day, and only 6.77% arrive late. The latest order arrived 188 days after its estimate.
Insight: deliveries are mostly fast, but the estimates are far too cautious. Giving customers shorter, more accurate estimates could increase sales, because a long estimate can put buyers off.
*/

-- 5.2 Top 5 states: highest & lowest average freight
SELECT c.customer_state, ROUND(AVG(oi.freight_value), 2) AS avg_freight
FROM order_items oi
JOIN orders o    ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state ORDER BY avg_freight DESC LIMIT 5;

SELECT c.customer_state, ROUND(AVG(oi.freight_value), 2) AS avg_freight
FROM order_items oi
JOIN orders o    ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_state ORDER BY avg_freight ASC LIMIT 5;
/* ANSWER:
   Highest avg freight: RR 42.98, PB 42.72, RO 41.07, AC 40.07, PI 39.15.
   Lowest avg freight: SP 15.15, PR 20.53, MG 20.63, RJ 20.96, DF 21.04.
   Freight in the North/Northeast is about 2.8x SP's, reflecting distance from where sellers are.
*/

-- 5.3 Top 5 states: highest & lowest average delivery time
SELECT c.customer_state,
       ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 2) AS avg_delivery_days
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state ORDER BY avg_delivery_days DESC LIMIT 5;

SELECT c.customer_state,
       ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 2) AS avg_delivery_days
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state ORDER BY avg_delivery_days ASC LIMIT 5;
/* ANSWER:
   Slowest: RR ~29.34 days, AP ~27.18, AM ~26.36, AL ~24.50, PA ~23.73.
   Fastest: SP ~8.7 days, PR ~11.94, MG ~11.95, DF ~12.90, SC ~14.91.
   Delivery to the far North takes 3-4x as long as within SP.
*/

-- 5.4 Top 5 states where delivery is fastest compared with the estimate
SELECT c.customer_state,
       ROUND(AVG(DATEDIFF(o.order_estimated_delivery_date, o.order_delivered_customer_date)), 2) AS avg_days_early
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY avg_days_early DESC
LIMIT 5;
/* ANSWER:
   Deliveries beat the estimate by the most in AC (~20.73 days early), RO (~20.1), AP (~19.69), AM (~19.57), RR (~17.29).
   These are the slowest states, so the estimates there are padded heavily. Overly long estimates
   may discourage customers from buying.
*/

-- ---------------------------------------------------------------
-- 6. PAYMENTS
-- ---------------------------------------------------------------

-- 6.1 Month-on-month orders by payment type
SELECT YEAR(o.order_purchase_timestamp)  AS yr,
       MONTH(o.order_purchase_timestamp) AS mon,
       p.payment_type,
       COUNT(DISTINCT o.order_id) AS orders
FROM orders o
JOIN payments p ON o.order_id = p.order_id
GROUP BY yr, mon, p.payment_type
ORDER BY yr, mon, p.payment_type;
/* ANSWER:
   Credit card is the main method every month (e.g. 5,867 orders in Nov 2017). UPI is second
   (1,509 in Nov 2017), then voucher. Debit card is small but grew fast in 2018 (51 orders in May -> 277 in Aug).
   All payment types follow the overall order trend, including the Nov 2017 spike.
*/

-- 6.2 Orders by number of installments
SELECT payment_installments, COUNT(DISTINCT order_id) AS orders
FROM payments
GROUP BY payment_installments
ORDER BY payment_installments;
/* ANSWER:
   1 installment: 49,060 orders (about half). 2: 12,389 | 3: 10,443 | 4: 7,088 | 5: 5,234 | 6: 3,916 | 7: 1623
   | 8: 4,253 | 9: 644 | 10: 5,315. Above 10 installments is rare.
   Many customers spread payments over 2-10 installments, so paying in installments is a key way customers afford purchases.
*/

-- ---------------------------------------------------------------
-- 7. SUPPORTING QUERIES FOR INSIGHTS
-- ---------------------------------------------------------------

-- Review score: late vs on-time deliveries
SELECT CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
            THEN 'Late' ELSE 'On time' END AS delivery_status,
       COUNT(*) AS orders,
       ROUND(AVG(r.review_score), 2) AS avg_review
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status;
/* ANSWER:
   On-time orders (88,658) average 4.29 stars; late orders (7,701) average 2.57 stars.
   Late delivery is the strongest driver of bad reviews.
*/

-- Top 10 product categories by revenue
-- (in this dataset the column is literally named `product category`)
SELECT pr.`product category` AS category, ROUND(SUM(oi.price), 2) AS revenue
FROM order_items oi
JOIN products pr ON oi.product_id = pr.product_id
GROUP BY category
ORDER BY revenue DESC
LIMIT 10;
/* ANSWER:
   Top categories by revenue: Health & Beauty (R$1.26M), Watches & Gifts (R$1.21M), Bed Table Bath (R$1.04M),
   Sport & Leisure (R$0.99M), Computer Accessories (R$0.91M).
   The top results should be about:

Category	          Revenue
Health & Beauty	        ~R$1,258,681
Watches & Gifts	        ~R$1,205,006
Bed, Table & Bath	~R$1,036,989
Sport & Leisure	        ~R$988,049
Computer Accessories	~R$911,954
*/

-- ---------------------------------------------------------------
-- 8. GEOLOCATION: DISTANCE vs FREIGHT & DELIVERY (supports insights)
-- ---------------------------------------------------------------

-- 8.1 Seller-to-customer distance per order item 
DROP TABLE IF EXISTS item_distance;
CREATE TABLE item_distance AS
SELECT oi.order_id,
       oi.freight_value,
       c.customer_state,
       DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
       111 * SQRT(POWER(gs.lat - gc.lat, 2) + POWER(gs.lng - gc.lng, 2)) AS distance_km
FROM order_items oi
JOIN orders o    ON oi.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
JOIN sellers s   ON oi.seller_id = s.seller_id
JOIN geo_zip gc  ON c.customer_zip_code_prefix = gc.zip
JOIN geo_zip gs  ON s.seller_zip_code_prefix = gs.zip;

---  gs.lat - gc.lat and gs.lng - gc.lng give how far apart the seller and customer are, in degrees.
---  SQRT(POWER(a, 2) + POWER(b, 2)) is Pythagoras' theorem: it gives the straight-line distance in degrees.
---  111 * converts degrees to km, because 1 degree is about 111 km.

-- 8.2 Freight & delivery time by distance band
SELECT CASE WHEN distance_km < 100  THEN '1. <100 km'
            WHEN distance_km < 500  THEN '2. 100-500 km'
            WHEN distance_km < 1000 THEN '3. 500-1000 km'
            WHEN distance_km < 2000 THEN '4. 1000-2000 km'
            ELSE '5. 2000+ km' END AS distance_band,
       COUNT(*) AS items,
       ROUND(AVG(freight_value), 2) AS avg_freight,
       ROUND(AVG(delivery_days), 1) AS avg_delivery_days
FROM item_distance
GROUP BY distance_band
ORDER BY distance_band;
/* ANSWER:
   <100 km: R$11.76 freight, 6.5 days | 100-500 km: R$18.4, 11.4 days | 500-1000 km: R$21.1, 14.2 days
   | 1000-2000 km: R$29.2, 17.8 days | 2000+ km: R$35.9, 21.0 days.
   Freight and delivery time rise steadily with distance (correlation about 0.39 for each).
*/

-- 8.3 States whose customers are farthest from sellers
SELECT customer_state, ROUND(AVG(distance_km), 0) AS avg_distance_km
FROM item_distance
GROUP BY customer_state
ORDER BY avg_distance_km DESC
LIMIT 5;
/* ANSWER:
   Farthest from sellers: RR ~3,249 km, AM ~2,646, AC ~2,643, AP ~2,592, PA ~2,290.
   These match the states with the highest freight and longest delivery times.
*/

-- 8.4 Where sellers are located
SELECT seller_state, COUNT(*) AS sellers,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM sellers), 1) AS pct
FROM sellers
GROUP BY seller_state
ORDER BY sellers DESC
LIMIT 5;
/* ANSWER:
   SP has 59.7% of sellers, PR 11.3%, MG 7.9%. Sellers are concentrated in the South/Southeast,
   which explains the high cost and long delivery times in the North.
*/

-- ---------------------------------------------------------------
-- 9. ACTIONABLE INSIGHTS & RECOMMENDATIONS
-- ---------------------------------------------------------------
/* INSIGHTS
   1. Fast growth: Jan-Aug order value up 136.98% from 2017 to 2018. Orders peaked in Nov 2017 (Black Friday)
      and held at 6-7k a month in 2018.
   2. Concentrated demand: SP has 42% of customers; SP+RJ+MG have 66%. 60% of sellers are in SP.
   3. Distance drives cost and speed: freight ranges from R$15 (SP) to R$43 (RR); delivery from 8 days (SP)
      to 29 days (RR).
   4. Estimated delivery dates are padded by about 11 days on average, and by up to 20 days in northern states.
   5. Late orders (7.9%) get 2.57 stars vs 4.21 for on-time orders.
   6. Customers mostly shop in the afternoon; 74% of payments are by credit card, and about half of orders use 2+ installments.

   RECOMMENDATIONS
   1. Open regional warehouses or carrier partnerships in the North/Northeast, and recruit local sellers there,
      to cut freight and delivery time.
   2. Set delivery estimates per state from actual delivery times: shorter, accurate dates boost sales.
   3. Prioritise on-time delivery: track orders at risk of being late, notify customers early, and offer vouchers to protect ratings.
   4. Grow outside SP with regional marketing and free-shipping thresholds in under-served states.
   5. Run promotions from the afternoon into the evening; plan stock and logistics capacity for Black Friday.
   6. Offer interest-free installments on top categories (Health & Beauty, Watches & Gifts, Bed Table Bath) and
      keep supporting UPI/debit card.
*/
