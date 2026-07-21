-- DDL
-- CREATE TABLE ods.dim_bike_station (
--     station_cd             VARCHAR(50),          -- stationid 변경 및 가변문자열 최적화
--     station_nm             TEXT,                 -- stationname 변경 및 축약 표준 적용
--     station_lat            NUMERIC(10, 8),       -- stationlatitude 축약 및 고정소수점 변환
--     station_lon            NUMERIC(11, 8),       -- stationlongitude 축약 및 고정소수점 변환
--     rack_tot_cnt           INTEGER,              -- racktotcnt 변경 및 정수형 변환
--     parking_bike_tot_cnt   INTEGER,              -- parkingbiketotcnt 변경 및 정수형 변환
--     shared                 INTEGER,              -- shared 소문자 유지 및 정수형 변환
--     created_at             TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 최초 적재 시간
--     last_updated           TIMESTAMP DEFAULT CURRENT_TIMESTAMP, -- 최종 변경 시간
--     is_deleted             BOOLEAN DEFAULT FALSE                -- 소프트 딜리트 여부
-- );

MERGE INTO {target_table} AS target
USING {source_table} AS source
ON (target.station_cd = source.stationid)

WHEN MATCHED THEN
    UPDATE SET
      station_nm = source.stationname
    , station_lat = source.stationlatitude::NUMERIC(10, 8)
    , station_lon = source.stationlongitude::NUMERIC(11, 8)
    , rack_tot_cnt = NULLIF(source.racktotcnt, '')::INTEGER
    , parking_bike_tot_cnt = NULLIF(source.parkingbiketotcnt, '')::INTEGER
    , shared = NULLIF(source.shared, '')::INTEGER
    , last_updated =  CURRENT_TIMESTAMP
    , is_deleted = FALSE
WHEN NOT MATCHED THEN
    INSERT (
    station_cd
    , station_nm
    , station_lat
    , station_lon
    , rack_tot_cnt
    , parking_bike_tot_cnt
    , shared
    , created_at
    , last_updated
    , is_deleted
    )
    VALUES (
      source.stationid
    , source.stationname
    , source.stationlatitude::NUMERIC(10, 8)
    , source.stationlongitude::NUMERIC(11, 8)
    , NULLIF(source.racktotcnt, '')::INTEGER
    , NULLIF(source.parkingbiketotcnt, '')::INTEGER
    , NULLIF(source.shared, '')::INTEGER
    , CURRENT_TIMESTAMP
    , CURRENT_TIMESTAMP
    , FALSE
    );
-- =======================================================================
-- [2단계] 소프트 딜리트 (위의 MERGE 문이 완전히 끝난 뒤 이어서 실행됨)
-- =======================================================================
UPDATE {target_table} AS target
SET is_deleted = TRUE,
    last_updated = CURRENT_TIMESTAMP
WHERE target.is_deleted = FALSE
  AND target.station_cd NOT IN (
      SELECT stationid FROM {source_table}
  );