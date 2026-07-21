-- DDL

-- DROP TABLE IF EXISTS dw.dim_bike_station;
-- CREATE TABLE dw.dim_bike_station (
--     station_cd             VARCHAR(50),          -- stationid 변경 및 가변문자열 최적화
--     station_no             INTEGER,
--     station_nm             TEXT,                 -- stationname 변경 및 축약 표준 적용
--     station_lat            NUMERIC(10, 8),       -- stationlatitude 축약 및 고정소수점 변환
--     station_lon            NUMERIC(11, 8),       -- stationlongitude 축약 및 고정소수점 변환
--     rack_tot_cnt           INTEGER,              -- racktotcnt 변경 및 정수형 변환
--     parking_bike_tot_cnt   INTEGER,              -- parkingbiketotcnt 변경 및 정수형 변환
--     shared                 INTEGER,              -- shared 소문자 유지 및 정수형 변환
--     created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 최초 적재 시간
--     last_updated           TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 최종 변경 시간
--     is_deleted             BOOLEAN DEFAULT FALSE,               -- 소프트 딜리트 여부
--
--     CONSTRAINT pk_dim_bike_station PRIMARY KEY (station_cd),
--     CONSTRAINT uq_dim_bike_station_no UNIQUE (station_no)
-- );

MERGE INTO {target_table} AS target
USING {source_table} AS source
ON (target.station_cd = source.station_cd)  -- 💡 sourceid가 아니라 세탁된 station_cd 사용!

WHEN MATCHED THEN
    UPDATE SET
        station_no           = CAST(SPLIT_PART(source.station_nm, '_', 1) AS INTEGER),
        station_nm           = TRIM(SPLIT_PART(source.station_nm, '.', 2)),
        station_lat          = source.station_lat,
        station_lon          = source.station_lon,
        rack_tot_cnt         = source.rack_tot_cnt,
        parking_bike_tot_cnt = source.parking_bike_tot_cnt,
        shared               = source.shared,
        last_updated         = CURRENT_TIMESTAMP,
        is_deleted           = FALSE

WHEN NOT MATCHED THEN
    INSERT (
        station_cd,
        station_no,
        station_nm,
        station_lat,
        station_lon,
        rack_tot_cnt,
        parking_bike_tot_cnt,
        shared,
        created_at,
        last_updated,
        is_deleted
    )
    VALUES (
        source.station_cd,
        CAST(SPLIT_PART(source.station_nm, '.', 1) AS INTEGER),
        TRIM(SPLIT_PART(source.station_nm, '.', 2)),
        source.station_lat,
        source.station_lon,
        source.rack_tot_cnt,
        source.parking_bike_tot_cnt,
        source.shared,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP,
        FALSE
    );


-- =======================================================================
-- [2단계] DW 소프트 딜리트 (소프트웨어 안티 조인)
-- =======================================================================
UPDATE {target_table} AS target
SET is_deleted = TRUE,
    last_updated = CURRENT_TIMESTAMP
WHERE target.is_deleted = FALSE
  AND target.station_cd NOT IN (
      SELECT station_cd FROM {source_table}  -- 💡 stationid가 아니라 station_cd 사용!
  );