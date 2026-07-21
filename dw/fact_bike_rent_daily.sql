WITH cleaned_ods AS (
    SELECT
        -- ODS의 rent_dt(TEXT)를 DW의 DATE 타입으로 형변환
        rent_dt::DATE AS rent_dt,
        rent_id,
        rent_nm,

        -- ① 권종 세탁: 공백이나 NULL 방어
        CASE
            WHEN TRIM(rent_type) = '' OR rent_type IS NULL THEN '권종확인불가'
            ELSE TRIM(rent_type)
        END AS rent_type,

        -- ② 성별 세탁: 대소문자(F, f, M, m) 통합 및 한국어 표기
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

        -- 🚨 [핵심!] TEXT 컬럼을 숫자 타입으로 형변환하여 SUM() 에러 완벽 방어!
        NULLIF(use_cnt, '')::INTEGER          AS use_cnt,
        NULLIF(exer_amt, '')::DOUBLE PRECISION AS exer_amt,
        NULLIF(carbon_amt, '')::DOUBLE PRECISION AS carbon_amt,
        NULLIF(move_meter, '')::DOUBLE PRECISION AS move_meter,
        NULLIF(move_time, '')::INTEGER        AS move_time
    FROM {source_table}
    WHERE rent_dt BETWEEN '{start_date}' AND '{end_date}'
)

-- 💡 2단계: 세탁된 숫자를 바탕으로 DW Fact 테이블에 집계 적재
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
    CURRENT_TIMESTAMP AS last_updated
FROM cleaned_ods
GROUP BY
    rent_dt,
    rent_id,
    rent_type,
    gender_cd,
    age_type;