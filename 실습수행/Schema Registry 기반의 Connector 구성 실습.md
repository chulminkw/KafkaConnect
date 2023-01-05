# Schema Registry 기반의 Connector 구성 실습

### Schema Registry 실행 스크립트 작성

- schema-registry-start 쉘을 [schema-registry.properties](http://schema-registry.properties) 설정으로 실행

```bash
vi registry_start.sh
$CONFLUENT_HOME/bin/schema-registry-start $CONFLUENT_HOME/etc/schema-registry/schema-registry.properties
```

- registry_start.sh 을 수행하여 schema registry 기동

### Avro 메시지 전송 및 읽기

- kafka-avro-console-producer를 이용하여 avro 메시지 보내기

```bash
kafka-avro-console-producer  --broker-list localhost:9092 --topic avro_test \
--property value.schema='{
	"type": "record", 
	"name": "customer_short",
  "fields": [
      {"name": "customer_id", "type": "int" },
      {"name": "customer_name", "type": "string"}
  ]
}' \
--property schema.registry.url=http://localhost:8081
```

- kafka-avro-console-producer를 이용하여 avro 메시지 읽기

```bash
kafka-avro-console-consumer  --bootstrap-server localhost:9092 --topic avro_test \
--property schema.registry.url=http://localhost:8081 --from-beginning
```

- schema registry에 등록된 정보 확인하기

```bash
http http://localhost:8081/schemas
```

### MySQL용 Debezium CDC Source Connector를 Schema Registry를 적용하여 생성

- 기존 Source Connector를 모두 삭제
- oc와 oc_sink 주요 테이블의 데이터를 모두 Truncate

```sql
use oc;

truncate table oc.customers;
truncate table oc.products;
truncate table oc.orders;
truncate table oc.order_items;
truncate table oc.orders_datetime_tab;

use oc_sink;

truncate table oc_sink.customers_sink;
truncate table oc_sink.products_sink;
truncate table oc_sink.orders_sink;
truncate table oc_sink.order_items_sink;
truncate table oc_sink.orders_datetime_tab_sink;
```

- mysql_cdc_oc_source_avro_01.json 파일에 아래 설정을 저장. Key와 Value모두 Avro 형태의 Converter를 적용하고, Schema는 Schema Registry에 등록

```json
{
    "name": "mysql_cdc_oc_source_avro_01",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "20000",
        "database.server.name": "mysqlavro",
        "database.include.list": "oc",
        "table.include.list": "oc.customers, oc.products, oc.orders, oc.order_items, oc.orders_datetime_tab",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",
	"database.allowPublicKeyRetrieval": "true",

        "time.precision.mode": "connect",
        "database.connectionTimezone": "Asia/Seoul",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- 아래 명령어로 생성한 json 파일을 등록하여 새로운 CDC Connector 생성.

```sql
register_connector mysql_cdc_oc_source_avro_01.json
```

- oc의 주요 테이블에 데이터 확인

```sql
use oc;

insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01');
insert into customers values (2, 'testaddress_02@testdomain', 'testuser_02');
insert into orders values(1, now(), 1, 'delivered', 1);
insert into products values(1, 'testproduct', 'testcategory', 100);
insert into order_items values(1, 1, 1, 100, 1);

update customers set full_name='updateduser_01' where customer_id = 2;

delete from customers where customer_id = 2;

insert into orders_datetime_tab values (1, now(), now(), 1, 'delivered', 1);
```

- customers 토픽에서 메시지 확인

```sql
show_topic_messages avro mysqlavro.oc.customers;
```

### Schema Registry에 등록된 정보 확인

- 내부 토픽 _schemas 조회

```sql
kafkacat -b localhost:9092 -C -t _schemas -u -q |jq '.'
```

- Schema Registry에 등록된 모든 Schema 정보 확인

```sql
http GET http://localhost:8081/schemas
```

- Schema Registry에 등록된 모든 subjects 정보 확인. subject명은  key와 value 별로 생성되며 기본적으로 Topic명 + ‘-key’ 또는 ‘-value’ 로 명명됨.

```sql
http GET http://localhost:8081/subjects
```

- 특정 id를 가지는 schema 정보 확인.

```sql
http GET http://localhost:8081/schemas/ids/1
```

- 특정 subject의 버전별 schema 정보 확인.

```sql
http GET http://localhost:8081/subjects/mysqlavro.oc.customers-value/versions/1
```

- 전역으로 등록된 config 정보 확인.

```sql
http GET http://localhost:8081/config
```

- 개별 subject별 config 정보 확인.

```sql
http GET http://localhost:8081/config/mysqlavro.oc.customers-value
```

### JDBC Sink Connector를 Schema Registry를 적용하여 MySQL Target DB에 데이터 입력

- Schema가 없는 데이터를 토픽에서 읽어서  Schema Registry를 통해서 스키마 정보 추출 후 JDBC를 통해 Target DB에 입력할 수 있도록 새로운 Connector 생성
- 아래 설정을 mysql_jdbc_oc_sink_customers_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_customers_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.customers",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.customers_sink",
        "insert.mode": "upsert",
        "pk.fields": "customer_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"

    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_products_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_products_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.products",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.products_sink",
        "insert.mode": "upsert",
        "pk.fields": "product_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"

    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_orders_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_orders_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.orders",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081",

        "db.timezone": "Asia/Seoul",

        "transforms": "convertTS",
        "transforms.convertTS.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
        "transforms.convertTS.field": "order_datetime",
        "transforms.convertTS.format": "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "transforms.convertTS.target.type": "Timestamp"

    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_order_items_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_order_items_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.order_items",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.order_items_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id, line_item_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"

    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_orders_datetime_tab_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_orders_datetime_tab_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.orders_datetime_tab",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_datetime_tab_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"

    }
}
```

- 위에서 설정한 Connector를 모두 생성.

```sql
register_connector mysql_jdbc_oc_sink_customers_avro_01.json
register_connector mysql_jdbc_oc_sink_products_avro_01.json
register_connector mysql_jdbc_oc_sink_orders_avro_01.json
register_connector mysql_jdbc_oc_sink_order_items_avro_01.json
register_connector mysql_jdbc_oc_sink_orders_datetime_tab_avro_01.json
```

- Source 테이블의 변경 사항이 Sink 테이블로 반영 되었는지 확인.

### Source 테이블의 컬럼 추가/삭제 및 컬럼 타입 변경에 따른 Schema Registry의 스키마 호환성 체크

- 아래와 같이 테스트용 테이블 생성

```sql
use oc;

drop table if exists customers_redef_sr;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_redef_sr (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB ;

insert into customers_redef_sr (customer_id, email_address, full_name) values (1, 'test', 'test');

use oc_sink;

drop table if exists customers_redef_sr_sink;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_redef_sr_sink (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB ;
```

- Schema Registry 기반의 Source Connector 생성.  mysql_cdc_oc_source_avro_redef_01.json으로 아래 설정 저장.

```sql
{
    "name": "mysql_cdc_oc_source_avro_redef_01",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "20001",
        "database.server.name": "mysqlavroredef01",
        "database.include.list": "oc",
        "table.include.list": "oc.customers_redef_sr",
        "database.allowPublicKeyRetrieval": "true",

        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",

        "time.precision.mode": "connect",
        "database.connectionTimezone": "Asia/Seoul",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- Schema Registry 기반의 JDBC Sink Connector 생성.  mysql_jdbc_oc_sink_customers_redef_avro_01.json으로 아래 설정 저장.

```sql
{
    "name": "mysql_jdbc_oc_sink_customers_redef_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavroredef01.oc.customers_redef_sr",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.customers_redef_sr_sink",
        "insert.mode": "upsert",
        "pk.fields": "customer_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "auto.evolve": "true",
        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"
    }
}
```

- Source 와 Sink Connector 생성 등록 및 토픽 메시지 확인.

```sql
register_connector mysql_cdc_oc_source_avro_redef_01.json
register_connector mysql_jdbc_oc_sink_customers_redef_avro_01.json

show_topic_messages avro mysqlavroredef01.oc.customers_redef_sr
```

- Schema Registry에 등록된 global compatibility와 subject 확인

```sql
http http://localhost:8081/config

http http://localhost:8081/schemas
```

### Source 테이블에 컬럼 추가/삭제/타입 변경/컬럼명 변경 수행.

- oc.customers_redef 테이블에 Nullable 정수형 컬럼 추가및 데이터 입력

```sql
use oc;

alter table customers_redef_sr add column (age int);
describe customers_redef_sr;
insert into customers_redef_sr (customer_id, email_address, full_name, age) 
values (2, 'test', 'test', 40);
```

- oc.customers_redef 테이블에 age 컬럼의 default가 Null값이 되도록 데이터 입력

```sql
use oc;

insert into customers_redef_sr (customer_id, email_address, full_name) 
values (3, 'test', 'test');
```

- 소스 테이블에 Default를 설정하지 않은 Not Null 정수형 컬럼 추가 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
use oc;

alter table customers_redef_sr add column (salary_01 int not null);
describe customers_redef_sr;

-- 아래는 not null 컬럼에 default 값이 설정 되어 있지 않으므로 오류 발생. 
insert into customers_redef_sr (customer_id, email_address, full_name, age) 
values (4, 'test', 'test', 30);

insert into customers_redef_sr (customer_id, email_address, full_name, age, salary_01) 
values (4, 'test', 'test', 30, 1000);

```

- 소스 테이블에 Default를 설정한 Not Null 정수형 컬럼 추가 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
use oc;

alter table customers_redef_sr add column (salary_02 int not null default 0);
describe customers_redef_sr;

insert into customers_redef_sr (customer_id, email_address, full_name, age, salary_01) 
values (5, 'test', 'test', 30, 1000);

insert into customers_redef_sr (customer_id, email_address, full_name, age, salary_01, salary_02) 
values (6, 'test', 'test', 30, 1000, 2000);
```

- 소스 테이블 컬럼 삭제

```sql
use oc;

alter table customers_redef_sr drop column salary_02;
describe customers_redef_sr;

insert into customers_redef_sr (customer_id, email_address, full_name, age, salary_01) 
values (7, 'test', 'test', 30, 1000);
```

- 타겟 테이블 컬럼 삭제

```sql
use oc_sink;

alter table customers_redef_sr_sink drop column salary_02;
describe customers_redef_sr_sink;

```

- 소스 테이블 컬럼 타입 변경.

```sql
use oc;

alter table customers_redef_sr modify column salary_01 decimal(10, 3);

describe customers_redef_sr;

insert into customers_redef_sr (customer_id, email_address, full_name, age, salary_01) 
values (8, 'test', 'test', 30, 1000.999);
```

- 해당 토픽 subject의 스키마 호환성 변경.

```sql
curl -X PUT -H "Content-Type: application/vnd.schemaregistry.v1+json" --data '{"compatibility": "NONE"}' http://localhost:8081/config/mysqlavroredef01.oc.customers_redef_sr-value
```

- 소스 테이블 컬럼명 변경

```sql
use oc;

alter table customers_redef_sr rename column salary_01 to new_salary_01;
describe customers_redef_sr;

insert into customers_redef_sr (customer_id, email_address, full_name, age, new_salary_01) 
values (9, 'test', 'test', 30, 1000);
```
