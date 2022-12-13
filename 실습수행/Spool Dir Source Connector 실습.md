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

- sample csv 파일인 csv-spooldir-source.csv 파일을 다운로드 받은 후 input.path인 실습 VM의 ~/spool_test_dir 디렉토리에 저장

```sql
cd 
wget https://raw.githubusercontent.com/chulminkw/KafkaConnect/main/sample_data/csv-spooldir-source.csv -O csv-spooldir-source-01.csv
cp csv-spooldir-source.csv ~/spool_test_dir
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
