--  DDL
-- ODS 부터는 먹등성을 고려한 DROP TABLE을 하지 않는다

-- CREATE SCHEMA IF NOT EXISTS dw;

-- CREATE TABLE dw.fact_bike_rent_daily (
--     rent_id TEXT,
--     rent_no TEXT,
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
--     rnum INTEGER,
--     last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
-- );

-- 💡 1단계 (WITH절): 원천의 더러운 값들을 1차로 깨끗하게 세탁하는 가상 공장
WITH cleaned_ods AS (
    SELECT
        rent_dt
      , rent_id
      , rent_nm
      -- ① 권종 세탁: 공백이나 NULL 방어
      , CASE
            WHEN TRIM(rent_type) = '' OR rent_type IS NULL THEN '권종확인불가'
            ELSE TRIM(rent_type)
        END AS rent_type
      -- ② 성별 세탁: 대소문자(F,f,M,m) 통합 및 공백을 명시적 텍스트로 치환!
      , CASE
            WHEN UPPER(TRIM(gender_cd)) = 'F' THEN '여성'
            WHEN UPPER(TRIM(gender_cd)) = 'M' THEN '남성'
            ELSE '성별확인불가'
        END AS gender_cd
      -- ③ 연령 세탁: '기타' 및 공백을 전부 하나로 통합!
      , CASE
            WHEN TRIM(age_type) IN ('', '기타') OR age_type IS NULL THEN '연령확인불가'
            ELSE TRIM(age_type)
        END AS age_type
      , use_cnt
      , exer_amt
      , carbon_amt
      , move_meter
      , move_time
    FROM {source_table}
    WHERE rent_dt BETWEEN '{start_date}' AND '{end_date}'
)

-- 💡 2단계: 세탁된 데이터를 바탕으로 5개 차원을 묶어 중복을 완벽히 제거하며 DW에 적재!
INSERT INTO {target_table} (
  rent_dt
, rent_id
, rent_no
, rent_nm
, rent_type
, gender_cd
, age_type
, use_cnt
, exer_amt
, carbon_amt
, move_meter
, move_time
, last_updated
)
SELECT
  rent_dt
, rent_id
-- 🌟 질문자님의 천재적인 생각대로 rent_nm은 max()로 받아내어 분리 파싱합니다!
, CAST(SPLIT_PART(max(rent_nm), '.', 1) AS INTEGER) AS rent_no
, TRIM(SPLIT_PART(max(rent_nm), '.', 2)) AS rent_nm
, rent_type
, gender_cd
, age_type
, SUM(use_cnt)
, SUM(exer_amt)
, SUM(carbon_amt)
, SUM(move_meter)
, SUM(move_time)
, CURRENT_TIMESTAMP
FROM cleaned_ods
GROUP BY
  rent_dt
, rent_id
, rent_type
, gender_cd
, age_type;

