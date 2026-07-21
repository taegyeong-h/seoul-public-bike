-- CREATE SCHEMA IF NOT EXISTS dw;
--
-- DROP TABLE IF EXISTS dw.fact_bike_rent_daily;
--
-- CREATE TABLE dw.fact_bike_rent_daily (
--     rent_dt       DATE NOT NULL,
--     rent_id       VARCHAR(50) NOT NULL,
--     rent_no       INTEGER,
--     rent_nm       TEXT,
--     rent_type     VARCHAR(50) NOT NULL,
--     gender_cd     VARCHAR(20) NOT NULL,
--     age_type      VARCHAR(20) NOT NULL,
--     use_cnt       INTEGER DEFAULT 0,
--     exer_amt      DOUBLE PRECISION DEFAULT 0,
--     carbon_amt    DOUBLE PRECISION DEFAULT 0,
--     move_meter    DOUBLE PRECISION DEFAULT 0,
--     move_time     INTEGER DEFAULT 0,
--     created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     last_updated  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--
--     -- 복합 기본키(PK) 설정으로 중복 방지
--     CONSTRAINT pk_fact_bike_rent_daily PRIMARY KEY (rent_dt, rent_id, rent_type, gender_cd, age_type)
-- );


    -- 💡 1단계: ODS 텍스트 데이터를 숫자/날짜 타입으로 캐스팅하고 비즈니스 규격으로 1차 세탁
WITH cleaned_ods AS (
    SELECT
        -- '2025-01-01' 또는 '20250101' 형식 모두 안전하게 DATE 타입으로 변환
        TO_DATE(REPLACE(rent_dt, '-', ''), 'YYYYMMDD') AS rent_dt,
        rent_id,
        rent_nm,

        -- ① 권종 세탁
        CASE
            WHEN TRIM(rent_type) = '' OR rent_type IS NULL THEN '권종확인불가'
            ELSE TRIM(rent_type)
        END AS rent_type,

        -- ② 성별 세탁
        CASE
            WHEN UPPER(TRIM(gender_cd)) = 'F' THEN '여성'
            WHEN UPPER(TRIM(gender_cd)) = 'M' THEN '남성'
            ELSE '성별확인불가'
        END AS gender_cd,

        -- ③ 연령 세탁
        CASE
            WHEN TRIM(age_type) IN ('', '기타') OR age_type IS NULL THEN '연령확인불가'
            ELSE TRIM(age_type)
        END AS age_type,

        -- ④ 수치형 데이터 안전 형변환 (TEXT -> NUMERIC/INTEGER)
        NULLIF(use_cnt, '')::INTEGER          AS use_cnt,
        NULLIF(exer_amt, '')::DOUBLE PRECISION AS exer_amt,
        NULLIF(carbon_amt, '')::DOUBLE PRECISION AS carbon_amt,
        NULLIF(move_meter, '')::DOUBLE PRECISION AS move_meter,
        NULLIF(move_time, '')::INTEGER        AS move_time
    FROM {source_table}
    WHERE REPLACE(rent_dt, '-', '') BETWEEN REPLACE('{start_date}', '-', '') AND REPLACE('{end_date}', '-', '')
)

-- 💡 2단계: 세탁된 데이터를 바탕으로 DW Fact 테이블에 적재
INSERT INTO {target_table} (
    rent_dt,
    rent_id,
    rent_no,
    rent_nm,
    rent_type,
    gender_cd,
    age_type,
    use_cnt,
    exer_amt,
    carbon_amt,
    move_meter,
    move_time,
    created_at,
    last_updated
)
SELECT
    rent_dt,
    rent_id,
    CAST(NULLIF(SPLIT_PART(MAX(rent_nm), '.', 1), '') AS INTEGER) AS rent_no,
    TRIM(SPLIT_PART(MAX(rent_nm), '.', 2))                       AS rent_nm,
    rent_type,
    gender_cd,
    age_type,
    SUM(use_cnt)     AS use_cnt,
    SUM(exer_amt)    AS exer_amt,
    SUM(carbon_amt)  AS carbon_amt,
    SUM(move_meter)  AS move_meter,
    SUM(move_time)   AS move_time,
    CURRENT_TIMESTAMP AS created_at,
    CURRENT_TIMESTAMP AS last_updated
FROM cleaned_ods
GROUP BY
    rent_dt,
    rent_id,
    rent_type,
    gender_cd,
    age_type;














-- MERGE INTO {target_table} AS target
-- USING {source_table} AS source
-- ON (target.station_cd = source.stationid)
--
-- -- 1. 기존에 존재하는 대여소 정보 수정 (UPDATE)
-- WHEN MATCHED THEN
--     UPDATE SET
--         station_no           = CAST(NULLIF(SPLIT_PART(source.stationname, '.', 1), '') AS INTEGER),
--         station_nm           = TRIM(SPLIT_PART(source.stationname, '.', 2)),
--         station_lat          = NULLIF(source.stationlatitude, '')::NUMERIC(10, 8),
--         station_lon          = NULLIF(source.stationlongitude, '')::NUMERIC(11, 8),
--         rack_tot_cnt         = NULLIF(source.racktotcnt, '')::INTEGER,
--         parking_bike_tot_cnt = NULLIF(source.parkingbiketotcnt, '')::INTEGER,
--         shared               = NULLIF(source.shared, '')::INTEGER,
--         last_updated         = CURRENT_TIMESTAMP,
--         is_deleted           = FALSE
--
-- -- 2. 신규 대여소 정보 추가 (INSERT)
-- WHEN NOT MATCHED THEN
--     INSERT (
--         station_cd,
--         station_no,
--         station_nm,
--         station_lat,
--         station_lon,
--         rack_tot_cnt,
--         parking_bike_tot_cnt,
--         shared,
--         created_at,
--         last_updated,
--         is_deleted
--     )
--     VALUES (
--         source.stationid,
--         CAST(NULLIF(SPLIT_PART(source.stationname, '.', 1), '') AS INTEGER),
--         TRIM(SPLIT_PART(source.stationname, '.', 2)),
--         NULLIF(source.stationlatitude, '')::NUMERIC(10, 8),
--         NULLIF(source.stationlongitude, '')::NUMERIC(11, 8),
--         NULLIF(source.racktotcnt, '')::INTEGER,
--         NULLIF(source.parkingbiketotcnt, '')::INTEGER,
--         NULLIF(source.shared, '')::INTEGER,
--         CURRENT_TIMESTAMP,
--         CURRENT_TIMESTAMP,
--         FALSE
--     );
--
--
-- -- =======================================================================
-- -- [2단계] DW 소프트 딜리트 (Soft Delete)
-- --   - 오늘 들어온 ODS 목록에 없는 대여소는 삭제 처리 (is_deleted = TRUE)
-- -- =======================================================================
-- UPDATE {target_table} AS target
-- SET is_deleted = TRUE,
--     last_updated = CURRENT_TIMESTAMP
-- WHERE target.is_deleted = FALSE
--   AND target.station_cd NOT IN (
--       SELECT stationid FROM {source_table}
--   );