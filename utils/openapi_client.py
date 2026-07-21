from datetime import datetime, timedelta
from pathlib import Path
import os
import time
import pyarrow as pa
import pyarrow.fs as pafs  # 범용 파일시스템 모듈  File System의 약자로, 파일 및 스토리지 입출력
import pyarrow.parquet as pq
import requests

MEMORY_FLUSH_LIMIT = int(os.getenv("DATA_FLUSH_LIMIT", 50000))

class OpenApiClient:
    def __init__(self, api_key: str):
        self.api_key = api_key
        self.base_url = "http://openapi.seoul.go.kr:8088"

    def _send_request(self, url: str) -> dict:
        """원천 API 서버에 안정적으로 3회 재시도 노크를 날리는 네트워크 통신 전담 함수."""
        max_retries = 3
        backoff_factor = 2
        for attempt in range(max_retries):   # 0,1,2
            try:
                response = requests.get(url, timeout=10)
                response.raise_for_status()
                return response.json()
            except (requests.exceptions.RequestException, requests.exceptions.Timeout) as e:
                print(f"[시도 {attempt}] 에러 발생: {e}")
                if attempt < max_retries - 1:        # 3번 시도 1,2,4, {}
                    time.sleep(backoff_factor ** attempt)
        return {}

    def fetch_fact_stream(self, service_name: str, rent_dt: str) -> list:
        """특정 일자의 Fact 테이블를 1,000건씩 제너레이터(Stream)로 뱉어내는 함수"""
        start_index = 1
        api_page_size = 1000

        while True:
            end_index = start_index + api_page_size - 1
            url = f"{self.base_url}/{self.api_key}/json/{service_name}/{start_index}/{end_index}/{rent_dt}"

            data = self._send_request(url)
            if not data:
                break

            root_key = list(data.keys())[0]
            if root_key == "RESULT":
                break  # 해당 날짜의 API 끝에 도달했거나 더 이상 데이터가 없으면 탈출!

            result_body = data[root_key]
            total_count = int(result_body.get("list_total_count", 0))
            rows = result_body.get("row", [])

            if not rows:
                break

            yield rows  # 1,000건만 밖으로 던지고 일시정지!

            if end_index >= total_count: #
                break
            start_index += api_page_size

    def fetch_dimension(self, service_name: str) -> list:
        all_rows = []
        start_index = 1
        page_size = 1000

        print(f"[Dimension] {service_name} 수집 시작")
        while True:
            end_index = start_index + page_size - 1
            url = f"{self.base_url}/{self.api_key}/json/{service_name}/{start_index}/{end_index}"

            try:
                data = self._send_request(url)
                if not data:
                    break
            except Exception as e:
                print(f" API 요청 중 예외 발생: {e}")
                break

            if "RESULT" in data:
                print(f" API 서버에서 에러를 반환했습니다. 에러 내용: {data['RESULT']}")
                break

            actual_key = list(data.keys())[0]
            result_body = data[actual_key]

            if not isinstance(result_body, dict):
                print(f" result_body가 딕셔너리 구조가 아닙니다: {type(result_body)}")
                break

            total_count = int(result_body.get("list_total_count", 0))
            rows = result_body.get("row", [])

            if not rows:
                print(f" 'row' 키 안의 데이터 리스트가 비어있습니다. result_body: {result_body}")
                break

            all_rows.extend(rows)   ## rows 자체가 [] 로 되어있기에 append로 받으면 이중 리스트 구조가 된다 그래서 extend 함수로 리스트를 언패킹 해준 후 넣어야한다

            if len(rows) < page_size:
                print(f"ℹ️ 마지막 페이지에 도달했습니다. (가져온 행: {len(rows)}개)")
                break

            start_index += page_size

        print(f"✅ 디멘전 수집 완료: 총 {len(all_rows)}개 행\n")
        return all_rows

    def save_fact_period_to_parquet(
            client: OpenApiClient,
            service_name: str,
            start_date: str,
            end_date: str,
            base_path: str
    ):
        """
        OpenApiClient의 제너레이터를 받아 5만 건 단위로 메모리 방어선(Flush)을 구축하고
        S3/로컬 파티션에 Parquet 파일로 밀어 넣는 파이프라인 독립 함수
        """
        result = pafs.FileSystem.from_uri(base_path) # URI 문자열("s3://...")을 재료로 써서 FileSystem 드라이버 객체를 만들어라!" (S3FileSystem, "my-bucket/fact")
        fs = result[0]  # S3FileSystem         반환값:  <pyarrow._fs.S3FileSystem object at 0x0000021A58D8C3F0>,
        clean_path = result[1] # "my-bucket/fact"

        # 시작일부터 종료일까지의 'YYYYMMDD' 타겟 날짜 리스트 선행 빌드
        start_dt = datetime.strptime(start_date, "%Y-%m-%d")
        end_dt = datetime.strptime(end_date, "%Y-%m-%d")

        date_list = []
        curr_dt = start_dt
        while curr_dt <= end_dt:
            date_list.append(curr_dt.strftime("%Y%m%d"))
            curr_dt += timedelta(days=1)

        print(f"\n [Fact Engine 가동] 기간: {start_date} ~ {end_date} ")

        for rent_dt in date_list:
            year, month, day = rent_dt[:4], rent_dt[4:6], rent_dt[6:]
            target_file_path = f"{clean_path}/{service_name}/year={year}/month={month}/day={day}/data.parquet"

            if isinstance(fs, pafs.LocalFileSystem): # 로컬 컴퓨터에서 실행할 때 폴더가 없어서 발생하는 에러(FileNotFoundError)를 막기 위한 방어 코드
                os.makedirs(os.path.dirname(target_file_path), exist_ok=True)  # 중첩된 폴더를 전부 생성

            buffer_rows = []
            writer, stream = None, None

            # 1. client 객체의 제너레이터 스트림을 가져와 순회 API 1,000건씩 가져와서 메모리 바구니에 담기
            for rows_chunk in client.fetch_fact_stream(service_name, rent_dt):
                buffer_rows.extend(rows_chunk)

                # 2. 5만 건 임계치 도달 시 메모리가 터지기 전에 디스크/클라우드로 즉시 밀어내기 (Flush)
                if len(buffer_rows) >= MEMORY_FLUSH_LIMIT:
                    """
                    pa.Table : 파이썬 리스트(pylist)에 담긴 5만 건을, Parquet으로 저장할 수 있는 PyArrow 표
                    오늘 이 파일에 쓰기(Write)를 '처음' 시작하는 거냐?"를 묻는 조건문
                    """
                    # 1) 파이썬 list를 C++/Arrow 기반의 표(Table) 객체로 변환
                    batch_table = pa.Table.from_pylist(buffer_rows)
                    # 2) [최초 1회만 실행] 파일 스트림과 Parquet Writer 객체 개설

                    if writer is None: # "파케트 파일 생성기(writer)가 아직 만들어지지 않았냐? (오늘 파일 쓰기가 완전 처음이냐?)"를 묻는 조건문.
                        stream = fs.open_output_stream(target_file_path) # 파일 쓰기 빨대 꽂기 (I/O Stream)
                        writer = pq.ParquetWriter(stream, batch_table.schema) # 스키마 정보와 함께 쓰기 도구 생성

                    # 3) 파일에 5만 건 즉시 기록 (Append)
                    writer.write_table(batch_table)
                    print(f" [Buffer Flush] {rent_dt} 일자 실시간 {len(buffer_rows)}행 스토리지 분사 완료.")
                    # 4) 메모리 비우기 (OOM 방지 핵심!)
                    buffer_rows.clear()

            # 잔여 찌꺼기 처리
            if buffer_rows:  # 루프가 끝났는데 바구니에 남은 데이터가 있다면 (예: 12,340건)
                batch_table = pa.Table.from_pylist(buffer_rows)

                # 만약 데이터가 총 5만 건도 안 되어서(예: 2만 건) 지연 생성이 안 되었다면 여기서 최초 개설!
                if writer is None:
                    stream = fs.open_output_stream(target_file_path)
                    writer = pq.ParquetWriter(stream, batch_table.schema)
                writer.write_table(batch_table) # 남은 찌꺼기 마저 기록
                buffer_rows.clear()

            # 4단계: 자원 반납 및 마감 (Close)
            if writer:
                writer.close() # Parquet 메타데이터(Footer)를 마무리 짓고 파일 닫기
            if stream:
                stream.close() # OS/네트워크 스트림 자원 완전히 해제
            print(f" ✅ {rent_dt} 일자 하이브 파티션 최종 마감 및 메모리(Heap) 소멸 완료.")

        print("\n 모든 기간의 트랜잭션(Fact) 데이터 [Extract ➡️ Load] 스트리밍 적재가 대성공으로 종료되었습니다.")