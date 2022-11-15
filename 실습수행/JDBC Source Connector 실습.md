# JDBC Source Connector 실습

### JDBC Source/Sink Connector Plugin을 Connect에 설치하기

- JDBC Source/Sink Connector 로컬 PC에 Download

[JDBC Connector (Source and Sink)](https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc)

- MySQL JDBC Driver 로컬 PC에 Download. 오라클 사이트나 maven에서 jar download

[https://mvnrepository.com/artifact/mysql/mysql-connector-java/8.0.](https://mvnrepository.com/artifact/mysql/mysql-connector-java/8.0.30)29

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
cd ~/mysql-connector-java-8.0.29.jar ~/connector_plugins
```

- Connect를 재기동하고 REST API로 해당 plugin class가 제대로 Connect에 로딩 되었는지 확인

```sql
# 아래 명령어는 반드시 Connect를 재 기동후 수행
http http://localhost:8083/connector-plugins
```

### incrementing mode용 JDBC Source Connector  생성 및 등록

- connect_dev 사용자로 om 데이터베이스에 있는 customers 테이블에 데이터가 입력 될 경우 Kafka broker로 메시지를 보내는 Source Connector 생성하기
- connector이름은 mysql_jdbc_om_source_00로 정하고 mode는 incrementing으로 설정.
- vi ~/connector_configs/mysql_jdbc_om_source_00.json 파일을 열어서 아래 json 파일을 입력함.

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
        "catalog.pattern": "om",  
        "table.whitelist": "om.customers",
        "poll.interval.ms": 10000,
        "mode": "incrementing",
        "incrementing.column.name": "customer_id"
    }
}
```

- Connect에 REST API로 mysql_jdbc_om_source_00.json을 등록하여 JDBC Source Connector 신규 생성

```sql
cd ~/connector_configs
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_00.json
```

### JDBC Source Connector 테스트 - Incrementing(Insert 테스트)

- customers에 첫번째 샘플 데이터 입력

```bash
insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01', now());
```

- topic 리스트 확인 및 consumer로 메시지 확인

```sql
kafka-topics --bootstrap-server localhost:9092 --list

kafkacat -b localhost:9092 -C -t mysql_om_customers -J -q -u | jq '.'
#또는 
kafka-console-consumer --bootstrap-server localhost:9092 --topic mysql_om_customers --from-beginning --property print.key=true | jq '.'
```

- customers에 두번째 샘플 데이터 입력하고 consumer에서 메시지 확인.

```bash
insert into customers (email_address, full_name, system_upd) 
values ('testaddress_02@testdomain', 'testuser_02', now());
```

### timestamp mode용 JDBC Source Connector  생성 및 등록 - (Insert/Update)

- vi ~/connector_configs/mysql_jdbc_om_source_01.json를 아래로 생성

```json
{
    "name": "mysql_jdbc_om_source_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_time_",
        "topic.creation.default.replication.factor": 1,
        "topic.creation.default.partitions": 1, 
        "catalog.pattern": "om",
        "table.whitelist": "om.customers, om.products, om.orders, om.order_items",
        "poll.interval.ms": 10000,
        "mode": "timestamp",
        "timestamp.column.name": "system_upd"
    }
}
```

- 기존에 생성/등록된 mysql_jdbc_om_source_00 Connector를 삭제하고 mysql_jdbc_om_source_01로 새롭게 생성 등록

```sql
cd ~/connector_configs
http DELETE http://localhost:8083/connectors/mysql_jdbc_om_source_00
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_01.json
```

- Insert 데이터가 제대로 동작하는지 확인

```sql
insert into customers (email_address, full_name, system_upd) 
values ('testaddress_03@testdomain', 'testuser_03', now());

insert into orders values(1, now(), 1, 'delivered', 1, now());
insert into products values(1, 'testproduct', 'testcategory', 100, now());
insert into order_items values(1, 1, 1, 100, 1, now());
```

- 아래와 같이 Update 수행 후 동작 확인

```sql
update customers set full_name='updated_name' where customer_id = 3;
```

- 아래와 같이 Update 수행 후 동작 확인

```sql
update customers set full_name='updated_name', system_upd=now() where customer_id=3;
```

### timestamp+incrementing mode용 JDBC Source Connector  생성 및 등록 - (Insert/Update)

- vi ~/connector_configs/mysql_jdbc_om_source_01.json를 아래로 생성

```json
{
    "name": "mysql_jdbc_om_source_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_timeinc_",
        "topic.creation.default.replication.factor": 1,
        "topic.creation.default.partitions": 1, 
        "catalog.pattern": "om",
        "table.whitelist": "om.customers",
        "poll.interval.ms": 10000,
        "mode": "timestamp+incrementing",
        "incrementing.column.name": "customer_id",
        "timestamp.column.name": "system_upd"
    }
}
```

- 기존에 생성/등록된 mysql_jdbc_om_source_01 Connector를 삭제하고 mysql_jdbc_om_source_02로 새롭게 생성 등록

```sql
cd ~/connector_configs
http DELETE http://localhost:8083/connectors/mysql_jdbc_om_source_01
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_02.json
```

- Insert/updated 데이터가 제대로 동작하는지 확인

```sql
insert into customers (email_address, full_name, system_upd) 
values ('testaddress_04@testdomain', 'testuser_04', now());

update customers set full_name='new_updated_name' where customer_id = 4;

update customers set full_name='new_updated_name', system_upd=now() where customer_id=4;
```

### Bulk mode로 JDBC Source Connector 생성

- 새로운 connector이름인 mysql_jdbc_om_source_bulk로 아래와 같이 환경을 설정하고 connector_configs 디렉토리 밑에 mysql_jdbc_om_source_bulk.json 파일명으로 설정 저장

```json
{
    "name": "mysql_jdbc_om_source_bulk",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_om_bulk_",
        "poll.interval.ms": 10000,
        "mode": "bulk",
        "catalog.pattern": "om"
        "table.blacklist": "customers",
    }
}
```

- Connect에 위 설정을 등록하여 여러개의 테이블을 읽어들이는 Source Connector 생성

```sql
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_bulk.json
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
kafkacat -b localhost:9092 -t mysql_om_bulk_orders -C -J  -u -q | jq '.'
```

### JDBC Source Connector의 offset 관리 메커니즘

- connect-offsets 토픽 메시지 확인

```bash
kafka-console-consumer --bootstrap-server localhost:9092 --topic connect-offsets --from-beginning --property print.key=true

#또는
kafkacat -b localhost:9092 -C -t connect-offsets -J -u -q | jq '.'
```

- mysql_om_customers 토픽의 configuration 확인

```bash
kafka-configs --bootstrap-server localhost:9092 --entity-type topics --entity-name mysql_om_customers --all --describe
```

- 기존 생성 Connector 및 토픽 삭제 후 테스트
- om 데이터베이스의 기존 테이블 백업

```bash
use om;

create table customers_bkup
as
select * from customers;

create table orders_bkup
as
select * from orders;

create table products_bkup
as
select * from products;

create table order_items_bkup
as
select * from order_items;

-- 필요에 따라 테이블 drop 수행
drop table if exists customers;
drop table if exists orders;
drop table if exists products;
drop table if exists order_items;
```

- 신규 데이터 입력 후 토픽 메시지 확인
- auto increment 값 확인

```sql
show create table customers;

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

kafka-console-consumer --bootstrap-server localhost:9092 --topic mysql_om_mkey_order_items --from-beginning --property print.key=true | jq '.'
```

### Topic 이름 변경하기

- 기존 mysql_key_테이블명으로 나오는 토픽명에 database명(catalog명)을 추가하여 토픽명 생성.

 

```sql
{
    "name": "mysql_jdbc_om_source_03",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_key_",
        "catalog.patten": "om",
        "table.whitelist": "om.customers",
        "poll.interval.ms": 10000,
        "mode": "timestamp+incrementing",
        "incrementing.column.name": "customer_id",
        "timestamp.column.name": "system_upd",

        "transforms": "create_key, extract_key, rename_topic",
        "transforms.create_key.type": "org.apache.kafka.connect.transforms.ValueToKey",
        "transforms.create_key.fields": "customer_id",
        "transforms.extract_key.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
        "transforms.extract_key.field": "customer_id",

        "transforms.rename_topic.type": "org.apache.kafka.connect.transforms.RegexRouter",
        "transforms.rename_topic.regex": "mysql_key_(.*)",
        "transforms.rename_topic.replacement": "mysql_key_om_$1"

     }
}
```

### Topic 메시지 전송 시 schema 출력을 없애기

- key.converter.schemas.enable을 false로, value.converter.schemas.enable 역시 false로 설정하면 토픽 메시지로 schema 값이 출력되지 않음.
- 아래 설정을 mysql_jdbc_om_source_noschema.json 파일로 저장.

```json
{
    "name": "mysql_jdbc_om_source_05",
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

kafka-console-consumer --bootstrap-server localhost:9092 --topic mysql_om_smt_noschema_customers --property print.key=true --from-beginning | jq '.'
```