# 서울시 공공자전거(따릉이) 데이터 수집 및 정제 파이프라인

> [!Note]
> **주의 사항:** 본 서브 프로젝트는 데이터 처리 속도 최적화를 위해 **Python 3.14** 및 **Polars** 라이브러리를 사용합니다. 반드시 `src/notebook/seoul-public-bike` 폴더 내에서 Poetry 가상환경을 활성화한 후 실행해야 합니다.
> 
## 프로젝트 개요
본 프로젝트는 서울시 공공자전거(따릉이)의 대여소 정보 및 일별 이용 데이터를 자동으로 수집하여 AWS S3에 임시 적재(Staging)한 후, 
PostgreSQL 데이터 웨어하우스 내에서 ODS ➔ DW ➔ DM 레이어 단계별로 정제·가공하는  **데이터 파이프라인(ELT) 시스템**입니다.

분석가와 서비스가 정제된 데이터를 즉시 활용할 수 있도록 정형화된 데이터 마트를 안정적으로 생산하는 것을 목표로 합니다.

- **데이터 소스:**
  - 마스터 데이터: [서울시 공공자전거 대여소 정보](https://data.seoul.go.kr/dataList/OA-15246/F/1/datasetView.do)
  - 트랜잭션 데이터: [서울시 공공자전거 이용정보(일별)](https://data.seoul.go.kr/dataList/OA-15493/A/1/datasetView.do)
- **중간 저장소 (Staging):** AWS S3 (가공 전 임시 적재 및 백업)
- **최종 목적지:** PostgreSQL 데이터 웨어하우스 (ODS ➔ DW ➔ DM 구조)

---

## 데이터 파이프라인 흐름 (Data Flow)
본 파이프라인은 원천 데이터 수집부터 최종 분석용 데이터 마트 생성까지 총 4단계로 흐릅니다.

1. **Collect & Stage (수집 및 임시 저장):** API를 통해 가져온 따릉이 데이터의 부피를 줄여(Parquet 포맷) AWS S3 임시 창고에 먼저 저장합니다.
2. **ODS (Operational Data Store):** S3의 원천 데이터를 PostgreSQL의 ODS 영역으로 가공 없이 날것 그대로 로드합니다.
3. **DW (Data Warehouse):** ODS의 데이터를 정제, 결합하고 비즈니스 규칙에 맞게 다듬어 통합 데이터 저장소(DW)를 구축합니다.
4. **DM (Data Mart):** 최종 분석/대시보드 으로 바로 가져다 쓸 수 있도록 요약·집계된 완제품 데이터(DM)를 생산합니다.

---


## 개발 환경 및 기술 스택
다른 팀원들과의 가상환경 충돌을 방지하기 위해 **본 서브 디렉토리는 독립된 환경(Poetry)**으로 관리됩니다.

- **Language:** Python `3.14`
- **DBMS:** PostgreSQL `8`
- **Environment Manager:** Poetry
---