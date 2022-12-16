# Debezium MySQL CDC Source Connector 실습 - 03

### Topic 이름의 dot(.)을 dash로 변경하기

- mysqlrename-oc-customers 토픽명으로 partition 개수가 3개인 토픽을 생성.

```sql
kafka-topics --bootstrap-server localhost:9092 --create --topic mysqlrename-oc-customers --partitions 3
```

- 기존 [database.server.name](http://database.server.name) = mysqlrename, database.include.list=oc, table.include.list=oc.customers 일 경우 topic명은 mysqlrename.oc.customers로 생성됨. 이를 mysqlren-oc-customers 로 토픽명 변경
- 정규 표현식의 dot(.)는 특수문자이므로 이를 단순 문자로 인식하기 위해 \ 추가. json에서 \을 인식시키기 위해 \\ 로 변경
- 아래 설정을 mysql_cdc_oc_source_rename_topic.json 파일명으로 저장.

```json
{
    "name": "mysql_cdc_oc_source_rename_topic",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "12001",
        "database.server.name": "mysqlrename",
        "database.include.list": "oc",
        "table.include.list": "oc.customers",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",

        "database.allowPublicKeyRetrieval": "true",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "transforms": "rename_topic, unwrap",
        "transforms.rename_topic.type": "org.apache.kafka.connect.transforms.RegexRouter",
        "transforms.rename_topic.regex": "(.*)\\.(.*)\\.(.*)",
        "transforms.rename_topic.replacement": "$1-$2-$3",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- 위에서 생성한 mysql_cdc_oc_source_rename_topic.json 을 connector로 생성 등록하고 mysqlrename-oc-customers 토픽 생성 및 토픽 메시지 확인.

### auto.evolove=true 설정시 Source 테이블의 컬럼 추가/변경/삭제에 따른 JDBC Sink Connector의 Target 테이블 변경

- 아래와 같이 테스트용 테이블 생성

```sql
use oc;

drop table if exists customers_redef;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_redef (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB ;

insert into customers_redef (customer_id, email_address, full_name) values (1, 'test', 'test');

use oc_sink;

drop table if exists customers_redef_sink;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_redef_sink (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB ;

```

- 아래와 같은 설정으로 mysql_cdc_oc_source_redef.json 생성.

```json
{
    "name": "mysql_cdc_oc_source_redef",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.allowPublicKeyRetrieval": "true",

        "database.server.id": "12002",
        "database.server.name": "mysqlredef01",
        "database.include.list": "oc",
        "table.include.list": "oc.customers_redef", 
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "time.precision.mode": "connect",
        "database.connectionTimezone": "Asia/Seoul",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- auto.evolve=true 설정으로 mysql_jdbc_oc_sink_customers_redef.json 생성.

```json
{
    "name": "mysql_jdbc_oc_sink_customers_redef",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlredef01.oc.customers_redef",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.customers_redef_sink",
        "insert.mode": "upsert",
        "pk.fields": "customer_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "auto.evolve": "true", 

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- connector 생성 등록,  topic 메시지 및 Target 테이블 확인.

```bash
register_connector mysql_cdc_oc_source_redef.json
register_connector mysql_jdbc_oc_sink_customers_redef.json

# 토픽 메시지 확인
show_topic_messages json mysqlred.oc.customers_redef
```

### Source 테이블에 숫자형, date, datetime 컬럼 추가

- oc.customers_redef 테이블에 정수형 컬럼 추가(default Null) 및 데이터 입력

```sql
use oc;

alter table customers_redef add column (age int);
describe customers_redef;
insert into customers_redef (customer_id, email_address, full_name, age) 
values (2, 'test', 'test', 40);
```

- 토픽 메시지 및 Target 테이블 변경 확인

```bash
show_topic_messages json mysqlred01.oc.customers_redef
```

- Debezium Source Connector에서 DDL 변경사항을 저장하는 내부 토픽 내용 확인.

```bash
kafkacat -b localhost:9092 -C -t schema-changes.mysql.oc -q -u | jq '.'
```

- oc.customers_redef 테이블에 Not Null 정수형 컬럼 추가 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
use oc;

alter table customers_redef add column (salary int not null default 0);
describe customers_redef;
insert into customers_redef (customer_id, email_address, full_name, age, salary) 
values (3, 'test', 'test', 30, 10000);
```

- oc.customers_redef 테이블에  Not Null date/datetime 컬럼 추가 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
use oc;

-- birth_date 컬럼 추가및 데이터 입력 
alter table customers_redef add column (birth_date date not null default '2022-11-25' );

describe customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary, birth_date)
values (4, 'test', 'test', 50, 15000, now());

alter table customers_redef add column (birth_datetime datetime not null default '2022-11-25 13:00:00');

describe customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary, birth_date, birth_datetime) 
values (5, 'test', 'test', 45, 12000, now(), now());
```

### Source 테이블에 varchar 컬럼 추가

- oc.customers_redef 테이블에 varchar 컬럼 추가(Null) 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
use oc;

alter table customers_redef add column (address_01 varchar(100));

describe customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary, address_01) 
values (6, 'test', 'test', 30, 10000, 'test address 01');
```

- oc.customers_redef 테이블에 varchar 컬럼 추가(Not Null) 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
use oc;

alter table customers_redef add column (address_02 varchar(100) not null default 'default address');

describe customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary, address_01) 
values (7, 'test', 'test', 32, 10000, 'another test address');
```

- Connector 상태 확인 및 Target 테이블 값 확인.

```sql
http GET http://localhost:8083/connectors/mysql_jdbc_oc_sink_customers_redef/status
```

```sql
use oc_sink;

select * from oc_sink.customers_redef_sink;
```

- __connect_offsets에서 sink connector가 현재까지 처리한 offset 확인.

```sql
echo "exclude.internal.topics=false" > consumer_temp.config
kafka-console-consumer --consumer.config /home/min/consumer_temp.config  --bootstrap-server localhost:9092 --topic __consumer_offsets  --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" --from-beginning | grep 'mysql_jdbc_oc_sink_customers_redef'
```

- Target 테이블 oc_sink.customers_redef_sink의 address_02 컬럼을 varchar(100) default 값 설정. address_01 컬럼도 text에서 varchar(100)으로 변경

```sql
use oc_sink;

alter table oc_sink.customers_redef_sink add column (address_02 varchar(100) not null default 'default address');

alter table oc_sink.customers_redef_sink modify column address_01 varchar(100);

describe customers_redef_sink;
```

- mysql_jdbc_oc_sink_customers_redef Sink Connector 재 기동 수행.

```sql
http POST http://localhost:8083/connectors/mysql_jdbc_oc_sink_customers_redef/restart
http GET http://localhost:8083/connectors/mysql_jdbc_oc_sink_customers_redef/status

delete_connector mysql_jdbc_oc_sink_customers_redef
register_connector mysql_jdbc_oc_sink_customers_redef.json
```

### Source 테이블의 컬럼 타입 변경

- oc.customers_redef 테이블의 address_01 컬럼을 varchar(100)에서 varchar(200)으로 타입 변경.

```sql
use oc;

alter table customers_redef modify column address_01 varchar(200);

describe customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary, birth_date, birth_datetime, address_01, address_02) 
values (8, 'test', 'test', 25, 5000, now(), now(), 'test_address_01', 'test_address_02');
```

- oc.customers_redef 테이블의 salary를 int에서 decimal(10, 3)로 컬럼 변경 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
use oc;

alter table customers_redef modify column salary decimal(10,3);

describe customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary, birth_date, birth_datetime, address_01, address_02) 
values (9, 'test', 'test', 25, 5000.999, now(), now(), 'test_address_01', 'test_address_02');
```

- sink connector 기동 정지.

```sql
http PUT http://localhost:8083/connectors/mysql_jdbc_oc_sink_customers_redef/pause
http GET http://localhost:8083/connectors/mysql_jdbc_oc_sink_customers_redef/status
```

- 수동으로 oc_sink.customers_redef_sink 테이블의 salary를 decimal(10, 3)으로 수정.  address_01도 varchar(200)으로 변경. 소스 테이블에 레코드 추가 테스트.

```sql
use oc_sink;

alter table customers_redef_sink modify column salary decimal(10,3);
alter table customers_redef_sink modify column address_01 varchar(200);

describe customers_redef_sink;

use oc;

insert into customers_redef (customer_id, email_address, full_name, age, salary, birth_date, birth_datetime, address_01, address_02) 
values (10, 'test', 'test', 25, 5000.999, now(), now(), 'test_address_01', 'test_address_02');

select * from customers_redef;
```

- sink connector 재 기동.

```sql
http PUT http://localhost:8083/connectors/mysql_jdbc_oc_sink_customers_redef/resume
http GET http://localhost:8083/connectors/mysql_jdbc_oc_sink_customers_redef/status
```

- 타겟 테이블의 데이터 확인.

```sql
use oc_sink;

select * from customers_redef_sink;
```

### Source 테이블의 컬럼 삭제

- oc.customers_redef 테이블의 address_02 컬럼 삭제후 connector 상태, 토픽 메시지, 타겟 테이블 값 확인.

```sql
use oc;

alter table customers_redef drop column address_02;

describe customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary, birth_date, birth_datetime, address_01) 
values (11, 'test', 'test', 25, 5000.999, now(), now(), 'test_address_01');
```

- oc_sink.customers_redef_sink 테이블에서 address_02 컬럼 수동 삭제 후 소스 테이블에 데이터 입력 후 타겟 테이블 값 확인.

```sql
use oc_sink;

alter table customers_redef_sink drop column address_02;

describe customers_redef_sink;

use oc;

insert into customers_redef (customer_id, email_address, full_name, age, salary, birth_date, birth_datetime, address_01) 
values (12, 'test', 'test', 25, 5000.999, now(), now(), 'test_address_01');
```

### Source 테이블의 컬럼명 변경

- oc.customers_redef 테이블의 address_01 컬럼을 new_address_01으로 컬럼명 변경 후 토픽 메시지, 타겟 테이블 값 확인.

```sql
use oc;

alter table customers_redef rename column address_01 to new_address_01;

describe customers_redef;

insert into customers_redef values (13, 'test', 'test', 30, 5001, now(), now(), 'test_addr');
```

### Snapshot 모드를 schema_only로 설정후 데이터 연동

- snapshot.mode=initial 로 default로 설정되어 있으면 connector를 생성하기 이전에 기존 소스 테이블에 생성되어 있는 레코드를 모두 카프카로 보내어서 동기화를 시킴. 기존 테이블의 데이터가 너무 클 경우 snapshot에 매우 오랜 시간이 소모됨.
- Connector가 생성되기 이전의 데이터를 메시지 생성하지 않을 경우 snapshot.mode를 schama_only로 설정하면 connector 생성 이후의 변경 데이터만 메시지로 생성.
- oc.customers_batch 테이블에 데이터가 대량으로 들어있는지 확인.

```sql
use oc;

drop table if exists customers_batch;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_batch (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB ;

```

```sql
use oc;

DELIMITER $$

DROP PROCEDURE IF EXISTS oc.INSERT_CUSTOMERS_BATCH$$

create procedure INSERT_CUSTOMERS_BATCH(
  max_id INTEGER, 
  repeat_cnt INTEGER
)
BEGIN
  DECLARE customer_idx INTEGER;
  DECLARE iter_idx INTEGER;
  
  SET iter_idx = 1; 

  WHILE iter_idx <= repeat_cnt DO
    SET customer_idx = max_id + iter_idx;
      
    insert into oc.customers_batch values (customer_idx, concat('testuser_', 
                     customer_idx),  concat('testuser_', customer_idx));

    SET iter_idx = iter_idx + 1;
  END WHILE;
END$$

DELIMITER ;
```

- 1000건의 데이터를 customers_batch 테이블에 입력

```sql
truncate table customers_batch;

call INSERT_CUSTOMERS_BATCH(0, 1000);
```

- snapshot.mode를 schema_only로 설정한 아래 config를 mysql_cdc_oc_source_schema_only.json으로 저장하고 새로운 connector 등록 생성.

```json
{
    "name": "mysql_cdc_oc_source_schema_only",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "13000",
        "database.server.name": "mysqlsonly",
        "database.include.list": "oc",
        "table.include.list": "oc.customers_batch",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",
        "database.allowPublicKeyRetrieval": "true",

        "snapshot.mode": "schema_only",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- mysqlsonly.oc.customers_batch 토픽명으로 토픽이 생성되는지 확인(토픽이 생성되지 않음)
- connect-offsets 토픽에서 mysql_cdc_oc_source_schema_only Connector의 offsets 정보 확인.

```sql
kafkacat -b localhost:9092 -C -t connect-offsets -J -u -q |jq -c '{key , payload}' | grep 'mysql_cdc_oc_source_schema_only'
```

- 추가적으로 5개의 레코드를 customers_batch에 입력하고 토픽 메시지 내용 확인.

```sql
call INSERT_CUSTOMERS_BATCH(1001, 5);
```