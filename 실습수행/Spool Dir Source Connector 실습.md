# Spool Dir Source Connector 실습

### 특정 디렉토리에 CSV/TSV 등의 형태로 만들어진 파일들을 Kafka broker로 전송하는 Spool Dir Source Connector를 생성

### Spool Dir Source Connector를 plugin.path에 로딩.

- Confluent Hub에서 Spool Dir Source Connector zip 파일을 다운로드 받음

[https://www.confluent.io/hub/jcustenborder/kafka-connect-spooldir](https://www.confluent.io/hub/jcustenborder/kafka-connect-spooldir)

- 다운로드 받은 Connector zip 파일을 실습 VM의 홈 디렉토리에 이동 후 압축 해제하고 lib 디렉토리명을 spooldir_source로 지정하고 ~/connector_plugins 디렉토리 밑의 서브 디렉토리로 복사
- Connect 재 기동 필요. 기존 Connect Worker 프로세스를 죽이고 다시 connect_start.sh로 기동

### Connector 클래스의 plugin.path 로딩 확인.

- curl 과  jq 설치

```bash
sudo apt-get install curl
sudo apt-get install jq
```

- 재 기동 후 아래 curl 명령어로 Connector가 제대로 Connect로 로딩 되었는지 확인

```bash
curl –X GET –H “Content-Type: application/json” http://localhost:8083/connector-plugins
```

### Spool Dir Source Connector 환경 설정 후 Connector 생성.

- 아래 config 설정을 /home/min/connector_configs 디렉토리에 spooldir_source.json 파일로 저장.

```json
{
  "name": "csv_spooldir_source",
  "config": {
    "tasks.max": "3",
    "connector.class": "com.github.jcustenborder.kafka.connect.spooldir.SpoolDirCsvSourceConnector",
    "input.path": "/home/min/spool_test_dir",
    "input.file.pattern": "^.*\\.csv",
    "error.path": "/home/min/spool_test_dir/error",
    "finished.path": "/home/min/spool_test_dir/finished",
    "empty.poll.wait.ms": 30000,
    "halt.on.error": "false",
    "topic": "spooldir-test-topic",
    "csv.first.row.as.header": "true",
    "schema.generation.enabled": "true"
   }
}
```

- csv 파일들을 input으로 저장하는 디렉토리(input.path) 생성 및 error.path 생성. finished.path도 생성해야 하나 테스트를 위해 아직 생성하지 않음

```bash
cd ~
mkdir spool_test_dir
cd ~/spool_test_dir
mkdir error
```

- sample csv 파일인 csv-spooldir-source.csv 파일을 csv-spooldir-source-01.csv파일로 다운로드 받은 후 input.path인 실습 VM의 ~/spool_test_dir 디렉토리에 저장

```sql
cd 
wget https://raw.githubusercontent.com/chulminkw/KafkaConnect/main/sample_data/csv-spooldir-source.csv -O csv-spooldir-source-01.csv
cp csv-spooldir-source-01.csv ~/spool_test_dir
```

- REST API를 이용하여 spooldir_source.json 파일로 설정된 Config를 Connect로 등록하여 신규 Spool Dir Source connector 생성.

```bash
cd ~/connector_configs
curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors --data @spooldir_source.json
```

- 오류가 발생하는지 반드시 Connect log를 확인함. finished.path를 설정하지 않아서 오류가 발생함. 아래와 같이 해당 connector의 status로도 확인 가능.

```sql
curl -X GET http://localhost:8083/connectors
curl -X GET http://localhost:8083/connectors/csv_spooldir_source/status | jq '.'
```

- finished.path 디렉토리를 spool_test_dir 밑에 finished로 생성.

```bash
cd ~/spool_test_dir
mkdir finished
```

- 오류가 발생한 Connector를 삭제한 후 다시 재 생성

```bash
cd ~/connector_configs
curl -X DELETE http://localhost:8083/connectors/csv_spooldir_source
curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors --data @spooldir_source.json

```

- 제대로 동작하는지 Connect log 또는 REST API로 확인

```bash
curl -X GET http://localhost:8083/connectors/csv_spooldir_source/status | jq '.'
```

- Kafka broker에 제대로 전송되었는지 토픽 및 consumer로 확인

```bash
kafka-topics --bootstrap-server localhost:9092 --list
kafka-console-consumer --bootstrap-server localhost:9092 --topic spooldir-test-topic --from-beginning --property print.key=true
```

### Connector 등록 생성 시 수행 프로세스

- Connect Worker JVM에서 Connector 수행 Thread와 Task Thread 모니터

```bash
ps -ef | grep java
jstack pid
```

### Connect 내부 토픽

- 아래 명령어로 connect-offsets 토픽 메시지 내용 살펴 보기.

```bash
kafka-console-consumer --bootstrap-server localhost:9092 --topic connect-offsets --from-beginning --property print.key=true | jq '.'
```

- spool dir source connector가 active로 기동되어 있는지 확인.
- spooldir-test-topic 토픽 메시지 확인

```bash
kafka-console-consumer --bootstrap-server localhost:9092 --topic spooldir-test-topic --from-beginning --property print.key=true | jq '.'
```

- sample csv 파일인 csv-spooldir-source.csv 파일을 csv-spooldir-source-01.csv파일로 다시 다운로드 받은 후 input.path인 실습 VM의 ~/spool_test_dir 디렉토리로 이동 후 토픽 메시지 확인.

```sql
cd 
wget https://raw.githubusercontent.com/chulminkw/KafkaConnect/main/sample_data/csv-spooldir-source.csv -O csv-spooldir-source-01.csv
cp csv-spooldir-source-01.csv ~/spool_test_dir
```

- sample csv 파일인 csv-spooldir-source.csv 파일을 csv-spooldir-source-02.csv파일로 다시 다운로드 받은 후 input.path인 실습 VM의 ~/spool_test_dir 디렉토리로 이동 후 토픽 메시지 확인.

```sql
cd 
wget https://raw.githubusercontent.com/chulminkw/KafkaConnect/main/sample_data/csv-spooldir-source.csv -O csv-spooldir-source-02.csv
cp csv-spooldir-source-01.csv ~/spool_test_dir
```

### httpie를 이용하여 REST API 호출

- httpie 설치

```sql
sudo apt-get install httpie
```

- connector 리스트 확인

```sql
http GET http://localhost:8083/connectors
```

- connector 등록하기

```sql
http POST http://localhost:8083/connectors @spooldir_source.json
```

- connector 삭제하기

```sql
http DELETE http://localhost:8083/connectors/csv_spooldir_source
```

### Kafkacat 실습

- kafkacat 설치

```sql
sudo apt-get install kafkacat
```

- -L 옵션으로 전체 토픽에 대한 메타 정보 확인

```sql
kafkacat -b localhost:9092 -L
```

- 특정 토픽의 메시지 읽어오기(키값은 나오지 않음)

```sql
kafkacat -b localhost:9092 -t spooldir-test-topic
```

- -C 옵션부여하여 명확하게 Consumer 모드로 Topic의 메시지 읽어오기

```sql
kafkacat -b localhost:9092 -t spooldir-test-topic -C
```

- 특정 토픽의 메시지를 읽어오되 키(Key)값도 함께 표시(키 seperator는 #)

```sql
kafkacat -b localhost:9092 -t spooldir-test-topic -C -K#
```

- 특정 토픽의 메시지를 읽어오되 json 포맷으로 출력(key, value값 자동 출력됨)

```sql
kafkacat -b localhost:9092 -t spooldir-test-topic -C -J -u -q | jq '.'
```

- 내부 토픽인 connect-offsets 토픽 읽기

```sql
kafkacat -b localhost:9092 -t connect-offsets -C -K#
```

- 내부 토픽 connect-offsets 의 특정 파티션의 메시지 읽기

```sql
kafkacat -b localhost:9092 -t connect-offsets -C -p 17 -K#
```

- 토픽 메시지를 특정 포맷으로 출력하기

```sql
kafkacat -b localhost:9092 -t connect-offsets -C -f '\nKey: %k\nValue: %s\nPartition: %p\nOffset: %o\n\n'
```

- kafkacat 테스트용 샘플 토픽 생성

```sql
kafka-topics --bootstrap-server localhost:9092 --create --topic kcat-test-topic --partitions 3
```

- Producer 모드로 메시지 전송 후 메시지 확인

```sql
kafkacat -b localhost:9092 -t kcat-test-topic -P -K#
kafkacat -b localhost:9092 -t kcat-test-topic -C -K#
```

### connect-offsets 토픽에서 특정 connector의 offset 번호 reset하기

- connect-offsets 토픽에서 connector별 key값과 partition 확인

```bash
kafkacat -b localhost:9092 -t connect-offsets -C -f '\nKey: %k\nValue: %s\nPartition: %p\nOffset: %o\n\n' -u -q
```

- offset Reset을 적용. 대상 connector에 해당하는 key값의 value에 Null을 적용. 최종 메시지가 있는 partition을 찾아서 해당 partition에 Null 메시지를 적용해야 함

```sql
echo '["csv_spooldir_source",{"fileName":"csv-spooldir-source-01.csv"}]#' | \
    kafkacat -b localhost:9092 -t connect-offsets -P -Z -K# -p 17
```
