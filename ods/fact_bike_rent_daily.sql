--  DDL
-- ODS부터는 먹등성을 고려한 DROP TABLE을 하지 않는다

-- CREATE SCHEMA IF NOT EXISTS ods;
-- CREATE TABLE ods.fact_bike_rent_daily (
--     rent_id TEXT,
--     rent_nm TEXT,
--     rent_dt DATE,
--     rent_type TEXT,
--     gender_cd TEXT,
--     age_type TEXT,
--     use_cnt INTEGER,       -- 이용건수 (정수)
--     exer_amt DOUBLE PRECISION,   -- 운동량 (실수)
--     carbon_amt DOUBLE PRECISION, -- 탄소절감량 (실수)
--     move_meter DOUBLE PRECISION, -- 이용거리 (실수)
--     move_time INTEGER,     -- 이용시간 (정수)
--     start_index BIGINT,
--     end_index BIGINT,
--     rnum INTEGER,
--     last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- );

INSERT INTO {target_table} (
  rent_id
, rent_nm
, rent_dt
, rent_type
, gender_cd
, age_type
, use_cnt
, exer_amt
, carbon_amt
, move_meter
, move_time
, start_index
, end_index
, rnum
, last_updated -- 💡 1. 여기에 컬럼을 명시하셨으니
)
select
  rent_id
, rent_nm
, rent_dt::DATE -- 💡 TEXT -> DATE 타입 변환
, rent_type
, gender_cd
, age_type
-- 💡 2. NULLIF가 공백('')을 만나면 0이 아닌 진짜 NULL로 바꾼 뒤 타입을 바꿉니다!
, NULLIF(use_cnt, '')::INTEGER
, NULLIF(exer_amt, '')::DOUBLE PRECISION
, NULLIF(carbon_amt, '')::DOUBLE PRECISION
, NULLIF(move_meter, '')::DOUBLE PRECISION
, NULLIF(move_time, '')::INTEGER
, start_index
, end_index
, NULLIF(rnum, '')::INTEGER
, CURRENT_TIMESTAMP -- 💡 3. SELECT 절에서는 DEFAULT 없이 이렇게만 쓰면 현재 시간이 들어갑니다!
FROM {source_table};