# JDBC Source Connector 실습

### JDBC Source/Sink Connector Plugin을 Connect에 설치하기

- JDBC Source/Sink Connector 로컬 PC에 Download

[JDBC Connector (Source and Sink)](https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc)

- MySQL JDBC Driver 로컬 PC에 Download. 오라클 사이트나 maven에서 jar download

[https://mvnrepository.com/artifact/mysql/mysql-connector-java/8.0.30](https://mvnrepository.com/artifact/mysql/mysql-connector-java/8.0.30)

- 로컬 PC에 다운로드 받은 JDBC Connector와 MySQL JDBC Driver를 실습 vm로 옮김
- upload된 JDBC Connector의 압축을 풀고 lib 디렉토리를 jdbc_connector로 이름 변경

```sql
unzip confluentinc-kafka-connect-jdbc-10.6.0.zip
cd confluentinc-kafka-connect-jdbc-10.6.0
mv lib jdbc_connector
```

- jdbc_connector 디렉토리를 plugin.path 디렉토리로 이동

```sql
# ~/confluentinc-kafka-connect-jdbc-10.6.0 디렉토리에 아래 수행.
cp -r jdbc_connector ~/connector_plugins
```

- mysql jdbc driver를 plugin.path 디렉토리로 이동

```sql
cd ~/mysql-connector-java-8.0.30.jar ~/connector_plugins
```

- Connect를 재기동하고 REST API로 해당 plugin class가 제대로 Connect에 로딩 되었는지 확인

```sql
# 아래 명령어는 반드시 Connect를 재 기동후 수행
http http://localhost:8083/connector-plugins
```

### JDBC Source Connector JSON 환경파일 생성 및 등록

- connect_dev 사용자로 om 데이터베이스에 있는 customers 테이블에 데이터가 입력 될 경우 Kafka broker로 메시지를 보내는 Source Connector 생성하기
- connector이름은 mysql_jdbc_om_source로 정하고 mode는 incrementing으로 설정.
- vi ~/connector_configs/mysql_jdbc_om_source.json 파일을 열어서 아래 json 파일을 입력함.

```json
{
    "name": "mysql_jdbc_om_source_00",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_",
        "topic.creation.default.replication.factor": 1,
        "topic.creation.default.partitions": 1, 
        "table.whitelist": "customers",
        "poll.interval.ms": 10000,
        "mode": "incrementing",
        "incrementing.column.name": "customer_id"
    }
}
```

- Connect에 REST API로 mysql_jdbc_om_source.json을 등록하여 JDBC Source Connector 신규 생성

```sql
cd ~/connector_configs
http POST http://localhost:8083/connectors @mysql_jdbc_om_source.json
```

### JDBC Source Connector 테스트 - Incrementing(Insert 테스트)

- customers에 첫번째 샘플 데이터 입력

```bash
insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01', now());
```

- topic 리스트 확인 및 consumer로 메시지 확인

```sql
kafka-topics --bootstrap-server localhost:9092 --list

kafka-console-consumer --bootstrap-server localhost:9092 --topic mysql_om_customers --from-beginning
--property --print.key=true
```

- customers에 두번째 샘플 데이터 입력하고 consumer에서 메시지 확인.

```bash
insert into customers (email_address, full_name, system_upd) 
values ('testaddress_02@testdomain', 'testuser_02', now());
```

### JDBC Source Connector 테스트 - timestamp+incrementing(Insert/Update)

- vi ~/connector_configs/mysql_jdbc_om_source_upd.json를 아래로 생성

```json
{
    "name": "mysql_jdbc_om_source_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_upd_",
        "topic.creation.default.replication.factor": 1,
        "topic.creation.default.partitions": 1, 
        "table.whitelist": "customers",
        "poll.interval.ms": 10000,
        "mode": "timestamp+incrementing",
        "incrementing.column.name": "customer_id",
        "timestamp.column.name": "system_upd"
    }
}
```

- 기존에 생성/등록된 mysql_jdbc_om_source_00 Connector를 삭제하고 mysql_jdbc_om_source_01로 새롭게 생성 등록

```sql
cd ~/connector_configs
http DELETE http://localhost:8083/connectors/mysql_jdbc_om_source_00
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_upd.json
```

- Insert 데이터가 제대로 동작하는지 확인

```sql
insert into customers (email_address, full_name, system_upd) 
values ('testaddress_03@testdomain', 'testuser_03', now());
```

- 아래와 같이 Update 수행 후 동작 확인

```sql
update customers set full_name='updated_name' where customer_id = 3
```

- 아래와 같이 Update 수행 후 동작 확인

```sql
update customers set full_name='updated_name', system_upd=now() where customer_id=3;
```

### 여러개의 테이블들을 Source Connector에 설정

- 새로운 connector이름인 mysql_jdbc_om_source_02로 아래와 같이 환경을 설정하고 connector_configs 디렉토리 밑에 mysql_jdbc_om_source_mt.json 파일명으로 설정 저장

```json
{
    "name": "mysql_jdbc_om_source_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_bulk_",
        "poll.interval.ms": 10000,
        "mode": "bulk",
        "table.blacklist": "customers",
        "catalog.pattern": "om"
    }
}
```

- Connect에 위 설정을 등록하여 여러개의 테이블을 읽어들이는 Source Connector 생성

```sql
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_mt.json
```

- orders, products, order_items 테이블에 새로운 데이터를 입력

```sql
use om;

insert into orders values(1, now(), 1, 'delivered', 1, now());
insert into products values(1, 'testproduct', 'testcategory', 100, now());
insert into order_items values(1, 1, 1, 100, 1, now());
```

- 생성된 Topic들을 확인하고 Topic의 메시지 확인

```sql
kafkacat -b localhost:9092 -t mysql_om_bulk_orders -C -J  -e | grep -v '% Reached' |jq '.'
```

### SMT를 이용하여 테이블의 PK를 Key값으로 설정하기

- JDBC Source Connector는 Topic 메시지의 Key값을 생성하기 위해서는 SMT(Single Message Transform) 설정 필요
- ValueToKey와 ExtractField 를 이용하여 Topic 메시지의 Key값 생성
- 새로운 connector이름인 mysql_jdbc_om_source_03로 아래와 같이 환경을 설정하고 connector_configs 디렉토리 밑에 mysql_jdbc_om_source_smt.json 파일명으로 아래 설정 저장

```json
{
    "name": "mysql_jdbc_om_source_03",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_smt_",
        "table.whitelist": "customers",
        "poll.interval.ms": 10000,
        "mode": "timestamp+incrementing",
        "incrementing.column.name": "customer_id",
        "timestamp.column.name": "system_upd",
        "transforms": "create_key, extract_key",
        "transforms.create_key.type": "org.apache.kafka.connect.transforms.ValueToKey",
        "transforms.create_key.fields": "customer_id",
        "transforms.extract_key.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
        "transforms.extract_key.field": "customer_id"
    }
}
```

- mysql_om_smt_customers 토픽이 생성되었음을 확인하고 해당 topic의 메시지 확인

```bash
kafkacat -b localhost:9092 -t mysql_om_smt_customers -C -J -e | grep -v "% Reached" | jq '.'
```

### 여러개의 컬럼으로 구성된 PK를 Key값으로 설정하기

- ValueToKey에 PK가 되는 컬럼명을 fields로 적용. ExtractField는 적용하지 않아야 함.
- 일반적으로 incrementing mode로 설정이 어려움. timestamp 모드로 설정 필요
- 아래 설정을 mysql_jdbc_om_source_mkey.json 파일로 설정

```json
{
    "name": "mysql_jdbc_om_source_04",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_mkey_",
        "table.whitelist": "order_items",
        "poll.interval.ms": 10000,
        "mode": "timestamp",
        "timestamp.column.name": "system_upd",
        "transforms": "create_key",
        "transforms.create_key.type": "org.apache.kafka.connect.transforms.ValueToKey",
        "transforms.create_key.fields": "order_id, line_item_id"
     }
}
```

- 신규 Connector로 등록

```sql
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_mkey.json
```

- 토픽 메시지 확인

```bash
kafkacat -b localhost:9092 -t mysql_om_mkey_order_items -C -J -e | grep -v "% Reached" | jq '.'

#또는

kafka-console-consumer --bootstrap-server localhost:9092 --topic mysql_om_mkey_order_items --property print.key=true --from-beginning | jq '.'
```

### Topic 메시지 전송 시 schema 출력을 없애기

- key.converter.schemas.enable을 false로, value.converter.schemas.enable 역시 false로 설정하면 토픽 메시지로 schema 값이 출력되지 않음.
- 아래 설정을 mysql_jdbc_om_source_noschema.json 파일로 저장.

```json
{
    "name": "mysql_jdbc_om_source_06",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_smt_noschema_",
        "table.whitelist": "customers",
        "poll.interval.ms": 10000,
        "mode": "timestamp+incrementing",
        "incrementing.column.name": "customer_id",
        "timestamp.column.name": "system_upd",

        "transforms": "create_key, extract_key",
        "transforms.create_key.type": "org.apache.kafka.connect.transforms.ValueToKey",
        "transforms.create_key.fields": "customer_id",
        "transforms.extract_key.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
        "transforms.extract_key.field": "customer_id",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",
        "key.converter.schemas.enable": "false",
        "value.converter.schemas.enable": "false"
    }
}
```

- 신규 Connector로 등록

```sql
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_noschema.json
```

- 토픽 메시지 확인

```sql
kafkacat -b localhost:9092 -t mysql_om_smt_noschema_customers -C -J -e | grep -v "% Reached" | jq '.'

#또는

kafka-console-consumer --bootstrap-server localhost:9092 --topic mysql_om_smt_noschema_customers --property print.key=true | jq '.'
```
