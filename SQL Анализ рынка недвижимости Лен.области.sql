--Задача 1. Время активности объявлений

WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Фильтрация объявлений по выбросам
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Категоризация по городам
category AS (
    SELECT 
        CASE 
            WHEN city_id = '6X8I' THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS city_category,
        f.id,
        f.total_area,
        f.rooms,
        f.balcony,
        f.ceiling_height,
        f.city_id
    FROM real_estate.flats AS f 
),
-- Категоризация по дням активности
period AS (
    SELECT 
        a.id,
        CASE 
            WHEN days_exposition > 1 AND days_exposition <= 30 THEN 'Месяц'
            WHEN days_exposition > 30 AND days_exposition <= 90 THEN 'Квартал'
            WHEN days_exposition > 90 AND days_exposition <= 180 THEN 'Полгода'
            WHEN days_exposition > 180 THEN 'Больше полугода'
            ELSE 'Уже продано'
        END AS period_of_sell
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f ON a.id = f.id
),
-- Подготовка итоговых данных
final_data AS (
    SELECT 
        c.city_category,
        p.period_of_sell,
        COUNT(a.id) AS ads_count,
        ROUND(AVG(a.last_price::numeric/f.total_area::numeric),0) AS avg_price_qm,
        ROUND(AVG(f.total_area::integer),2) AS avg_area,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY (f.rooms)) AS rooms_number_med,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY (f.balcony)) AS balconies_number_med,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY (f.floor)) AS floors_number_med,
        ROUND(AVG(f.ceiling_height::numeric),0) AS avg_ceil_hight,
        ROUND((COUNT(CASE WHEN f.rooms = 0 OR f.rooms IS NULL THEN 1 END)::numeric / COUNT(f.id)::NUMERIC)*100,2) AS percent_studio,
        ROUND((COUNT(CASE WHEN f.is_apartment = 1 THEN 1 END)::numeric / COUNT(*)::numeric)*100,2) AS percent_apart,
        ROUND((COUNT(CASE WHEN f.open_plan  = 1 THEN 1 END)::numeric / COUNT(*)::numeric)*100,2) AS percent_open_plan,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY (f.parks_around3000)) AS parks_number_med,
        PERCENTILE_DISC(0.5) WITHIN GROUP (ORDER BY (f.ponds_around3000)) AS ponds_number_med,
        round(avg(f.airports_nearest::numeric),2) AS avg_airport_dist
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f ON a.id = f.id
    JOIN period AS p ON a.id = p.id
    JOIN category AS c ON f.id = c.id
    JOIN real_estate.TYPE AS t ON t.type_id = f.type_id
    WHERE a.id IN (SELECT id FROM filtered_id) AND t.TYPE='город' 
    AND (EXTRACT(year FROM a.first_day_exposition) > 2014 AND EXTRACT(year FROM a.first_day_exposition) < 2019)
    GROUP BY c.city_category, p.period_of_sell
),
-- Суммарное количество объявлений по регионам
total_ads_count AS (
    SELECT 
        city_category,
        SUM(ads_count) AS total_ads
    FROM final_data AS fd
    GROUP BY city_category
)
-- Финальный запрос с расчетом доли
SELECT 
    fd.city_category,
    fd.period_of_sell,
    ROUND(fd.ads_count::numeric / total_ads.total_ads * 100, 0) AS ads_share, -- Доля по регионам
    fd.ads_count,
    fd.avg_price_qm,
    fd.avg_area,
    fd.rooms_number_med,
    fd.balconies_number_med,
    fd.floors_number_med,
    fd.avg_ceil_hight,
    fd.percent_studio,
    fd.PERCENT_apart,
    fd.percent_open_plan,
    fd.parks_number_med,
    fd.ponds_number_med,
    fd.avg_airport_dist
FROM final_data AS fd
JOIN total_ads_count total_ads ON fd.city_category = total_ads.city_category
ORDER BY fd.city_category, 
         CASE fd.period_of_sell
             WHEN 'Месяц' THEN 1
             WHEN 'Квартал' THEN 2
             WHEN 'Полгода' THEN 3
             WHEN 'Больше полугода' THEN 4
             ELSE 5
         END;

--Задача 2. Сезонность объявлений
--Месяц публикации
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Фильтрация объявлений по выбросам
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
)
-- Основной запрос с агрегацией
SELECT 
CASE 
	WHEN 
    EXTRACT(month FROM a.first_day_exposition)=1 THEN 'Январь'
    WHEN EXTRACT(month FROM a.first_day_exposition)=2 THEN 'Февраль'
    WHEN EXTRACT(month FROM a.first_day_exposition)=3 THEN 'Март'
    WHEN EXTRACT(month FROM a.first_day_exposition)=4 THEN 'Апрель'
    WHEN EXTRACT(month FROM a.first_day_exposition)=5 THEN 'Май'
    WHEN EXTRACT(month FROM a.first_day_exposition)=6 THEN 'Июнь'
    WHEN EXTRACT(month FROM a.first_day_exposition)=7 THEN 'Июль'
    WHEN EXTRACT(month FROM a.first_day_exposition)=8 THEN 'Август'
    WHEN EXTRACT(month FROM a.first_day_exposition)=9 THEN 'Сентябрь'
    WHEN EXTRACT(month FROM a.first_day_exposition)=10 THEN 'Октябрь'
    WHEN EXTRACT(month FROM a.first_day_exposition)=11 THEN 'Ноябрь'
    ELSE 'Декабрь'
    END AS first_date,
    count(a.id) AS number_of_publ_ads,
    AVG(f.total_area) AS avg_total_area,
    AVG(a.last_price / f.total_area) AS avg_price_qm
FROM real_estate.advertisement AS a
JOIN real_estate.flats AS f ON a.id = f.id
JOIN real_estate."type" AS t ON f.type_id=t.type_id
WHERE a.id IN (SELECT id FROM filtered_id)
AND t.TYPE='город' 
AND (EXTRACT(year FROM a.first_day_exposition) > 2014 AND EXTRACT(year FROM a.first_day_exposition) < 2019)
GROUP BY EXTRACT(month FROM a.first_day_exposition)
ORDER BY number_of_publ_ads DESC;

--Месяц снятия с продажи
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Фильтрация объявлений по выбросам
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Основной запрос с агрегацией и вычислением месяца снятия объявления
final_data AS (
    SELECT 
        CASE
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 1 THEN 'Январь'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 2 THEN 'Февраль'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 3 THEN 'Март'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 4 THEN 'Апрель'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 5 THEN 'Май'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 6 THEN 'Июнь'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 7 THEN 'Июль'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 8 THEN 'Август'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 9 THEN 'Сетябрь'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 10 THEN 'Октябрь'
        WHEN EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL)) = 11 THEN 'Ноябрь'
        ELSE 'Декабрь'
        END AS last_month,
        COUNT(a.id) AS number_of_bought_ads,
        AVG(f.total_area) AS avg_total_area,
        AVG(a.last_price / f.total_area) AS avg_price_qm
    FROM real_estate.advertisement AS a
    JOIN real_estate.flats AS f ON a.id = f.id
    JOIN real_estate."type" AS t ON f.type_id=t.type_id
    WHERE a.id IN (SELECT id FROM filtered_id) 
    AND t.TYPE='город' 
    AND (EXTRACT(year FROM a.first_day_exposition) > 2014 AND EXTRACT(year FROM a.first_day_exposition) < 2019)
    AND a.days_exposition IS NOT NULL 
    GROUP BY EXTRACT(MONTH FROM (a.first_day_exposition + (a.days_exposition || ' days')::INTERVAL))
)
-- Финальный запрос для вывода результата
SELECT *
FROM final_data
ORDER BY number_of_bought_ads DESC;

--Задача 3. Анализ рынка недвижимости Ленобласти
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Фильтрация объявлений по выбросам
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
)
-- Основной запрос
SELECT 
    c.city AS city_name,
    count(f.id) AS number_of_flats,
    COUNT(CASE WHEN a.days_exposition IS NOT NULL THEN 1 END) AS number_of_sold_flats,
    ROUND(COUNT(a.days_exposition)::numeric / count(f.id), 2)*100 AS sold_flats_percentage,
    round(AVG(f.total_area::integer), 2) AS avg_total_area,
    round(AVG(a.last_price::integer/f.total_area::integer), 2) AS avg_price_qm,
    round(avg(a.days_exposition::integer), 0) AS avg_days
FROM real_estate.city AS c
RIGHT JOIN real_estate.flats AS f USING (city_id) 
JOIN real_estate.advertisement AS a USING (id)
WHERE c.city <> 'Санкт-Петербург'
  AND a.id IN (SELECT id FROM filtered_id) -- Фильтрация по данным без выбросов
GROUP BY c.city
ORDER BY number_of_flats DESC
LIMIT 15;