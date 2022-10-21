
## Spool Dir Source Connectors를 Connect에 신규 생성
 
특정 디렉토리에 CSV/TSV 등의 형태로 만들어진 파일들을 Kafka broker로 전송하는 Spool Dir Source Connector를 생성  
 
## 수행 순서
**- Confluent Hub에서 Spool Dir Source Connector zip 파일을 다운로드 받음**

https://www.confluent.io/hub/jcustenborder/kafka-connect-spooldir 

 
**- 다운로드 받은 Connector zip 파일을 실습 VM의 홈 디렉토리에 이동 후 압축 해제하고 lib 디렉토리명을 spooldir_source로 지정하고 ~/connector_plugins 디렉토리 밑의 서브 디렉토리로 복사**

 
**- Connect 재 기동 필요. 기존 Connect Worker 프로세스를 죽이고 다시 connect_start.sh로 기동**

 
**- 재 기동 후 아래 curl 명령어로 Connector가 제대로 Connect로 로딩 되었는지 확인**

```js
curl –X GET –H “Content-Type: application/json” http://localhost:8083/connector-plugins
```

**- Connect에 등록할 Spool Dir Source Connector 환경 설정 json을 아래에서 다운로드 받아서 실습 vm의 ~/connector_configs에 spooldir_source.json 파일로 저장함**

[https://github.com/chulminkw/KafkaConnect/blob/main/connector-configs/spooldir_source.json](https://github.com/chulminkw/KafkaConnect/blob/main/connector-configs/spooldir_source.json)

**-csv 파일들을 input으로 저장하는 디렉토리(input.path) 생성 및 error.path 생성. finished.path도 생성해야 하나 테스트를 위해 아직 생성하지 않음**

```js
cd ~
mkdir spool_test_dir
cd ~/spool_test_dir
mkdir error
```

**- sample csv 파일인 csv-spooldir-source.csv 파일을 아래에서 다운로드 받은 후 input.path인 실습 VM의 ~/spool_test_dir 디렉토리에 저장**

[https://github.com/chulminkw/KafkaConnect/blob/main/sample_data/csv-spooldir-source.csv](https://github.com/chulminkw/KafkaConnect/blob/main/sample_data/csv-spooldir-source.csv)

**-REST API를 이용하여 Connector 생성 json 파일을 Connect로 전달하여 Spool Dir Source Connector 신규 생성**
```js
<![endif]-->

cd ~/connector_configs

curl -X POST -H "Content-Type: application/json" http://localhost:8083/connectors --data @spooldir_source.json
```