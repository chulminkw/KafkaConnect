# Debezium MySQL CDC Source Connector 실습 - 02

### connect-offsets 메시지 확인

- Source Connector에서 기록한 connect-offset 메시지 확인

```sql
kafkacat -b localhost:9092 -C -t connect-offsets -J -u -q |jq '.'
#또는
show_topic_message.sh json connect-offsets
```

### products, order_items 테이블용 JDBC Sink Connector 생성

- 아래 설정을 mysql_jdbc_oc_sink_products_01.json으로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_products_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql01.oc.products",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.products_sink",
        "insert.mode": "upsert",
        "pk.fields": "product_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_order_items_01.json으로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_order_items_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql01.oc.order_items",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.order_items_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id, line_item_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- products_sink,order_items_sink용 JDBC Sink Connector를 생성.

```sql
register_connector mysql_jdbc_oc_sink_products_01.json
register_connector mysql_jdbc_oc_sink_order_items_01.json
```

- 생성 후 sink 테이블에 제대로 데이터가 입력되었는지 확인.

### date, datetime 관련 Debezium 데이터 변환 및 JDBC Sink 테스트

- date와 datetime 컬럼 타입을 테스트해보기 위해 orders_datetime_tab 테이블을 oc DB에 생성

```sql
use oc;

drop table if exists orders_datetime_tab;

CREATE TABLE orders_datetime_tab (
	order_id int NOT NULL PRIMARY KEY,
	order_date date NOT NULL,
	order_datetime datetime NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ENGINE=InnoDB ;

insert into orders_datetime_tab values (1, now(), now(), 1, 'delivered', 1);
```

- oc_sink db에 orders_datetime_tab_sink 테이블 생성

```sql
use oc_sink;

drop table if exists orders_datetime_tab_sink;

CREATE TABLE orders_datetime_tab_sink (
	order_id int NOT NULL PRIMARY KEY,
	order_date date NOT NULL,
	order_datetime datetime NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ENGINE=InnoDB ;
```

- Debezium Source Connector로 생성하기 위해 mysql_cdc_oc_source_datetime_tab_01.json으로 아래 저장.

```sql
{
    "name": "mysql_cdc_oc_source_datetime_tab_01",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.allowPublicKeyRetrieval": "true",

        "database.server.id": "10020",
        "database.server.name": "test01",
        "database.include.list": "oc",
        "table.include.list": "oc.orders_datetime_tab",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",
     
        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- Source Connector 생성 등록

```sql
register_connector mysql_cdc_oc_source_datetime_tab_01.json
```

- 생성된 topic 메시지 확인

```sql
show_topic_messages json test01.oc.orders_datetime_tab
```

- test01.oc.orders_datetime_tab을 Target DB로 입력하기 위해 mysql_jdbc_oc_sink_datetime_tab_01.json 파일로 아래 JDBC Sink Connector 신규 환경 설정

```json
{
    "name": "mysql_jdbc_oc_sink_datetime_tab_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "test01.oc.orders_datetime_tab",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_datetime_tab_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- jdbc sink connector 등록하고 성공적으로 등록되는지 Connect 메시지 확인.

```sql
register_connector mysql_jdbc_oc_sink_datetime_tab_01.json
```

- 기존 source와 sink connector 삭제

```sql
delete_connector mysql_cdc_oc_source_datetime_tab_01
delete_connector mysql_jdbc_oc_sink_datetime_tab_01
```

- “time.precision.mode": "connect" 설정을 추가하여 mysql_cdc_oc_source_datetime_tab_02.json으로 새로운 source connector 생성.

```json
{
    "name": "mysql_cdc_oc_source_datetime_tab_02",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.allowPublicKeyRetrieval": "true",

        "database.server.id": "10021",
        "database.server.name": "test02",
        "database.include.list": "oc",
        "table.include.list": "oc.orders_datetime_tab",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",
        
        "time.precision.mode": "connect",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- mysql_cdc_oc_source_datetime_tab_02.json을 connect에 등록

```bash
register_connector mysql_cdc_oc_source_datetime_tab_02.json
```

- topics 설정을 test02.oc.orders_datetime_tab 으로 변경한  jdbc sink connector를 mysql_jdbc_oc_sink_datetime_tab_02로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_datetime_tab_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "test02.oc.orders_datetime_tab",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_datetime_tab_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- mysql_cdc_oc_source_datetime_tab_test02.json을 connect에 등록

```bash
register_connector mysql_jdbc_oc_sink_datetime_tab_02.json
```

- oc_sink.orders_datetime_tab_sink 테이블에 데이터가 잘 입력되었는지 확인.
- 테스트에 사용한 connector를 모두 삭제

```bash
delete_connector mysql_cdc_oc_source_datetime_tab_01
delete_connector mysql_cdc_oc_source_datetime_tab_02

delete_connector mysql_jdbc_oc_sink_datetime_tab_01
delete_connector mysql_jdbc_oc_sink_datetime_tab_02
```

### timestamp with timezone 컬럼 타입의 Source Connector 데이터 변환

- timestamp 컬럼을 가지는 소스 테이블 oc.orders_timestamp_tab을 생성.

```sql
use oc;

CREATE TABLE orders_timestamp_tab (
	order_id int NOT NULL PRIMARY KEY,
	order_datetime datetime NOT NULL,
  order_timestamp timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ENGINE=InnoDB ;

insert into orders_timestamp_tab values (1, now(), now(), 1, 'delivered', 1);
```

- sink 테이블 oc_sink.orders_timestamp_tab_sink 생성.

```sql
-- oc_sink db에서 아래 수행. 
use oc_sink;

CREATE TABLE orders_timestamp_tab_sink (
	order_id int NOT NULL PRIMARY KEY,
	order_datetime datetime NOT NULL,
  order_timestamp timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ENGINE=InnoDB ;
```

- orders_timestamp_tab을 읽어들이는 debezium source connector를 mysql_cdc_oc_source_timestamp_tab_01.json으로 아래와 같이 설정. "database.connectionTimezone": "Asia/Seoul"을 추가

```json
{
    "name": "mysql_cdc_oc_source_timestamp_tab_01",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.allowPublicKeyRetrieval": "true",

        "database.server.id": "10022",
        "database.server.name": "test01",
        "database.include.list": "oc",
        "table.include.list": "oc.orders_timestamp_tab",
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

- Source Connector 생성등록

```bash
register_connector mysql_cdc_oc_source_timestamp_tab_01.json
```

- 생성된 토픽 메시지 확인

```bash
show_topic_messages json test01.oc.orders_timestamp_tab
```

- 아래와 같은 JDBC Sink Connector 설정을 mysql_jdbc_oc_sink_timestamp_tab_01.json으로 설정

```json
{
    "name": "mysql_jdbc_oc_sink_timestamp_tab_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "test01.oc.orders_timestamp_tab",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_timestamp_tab_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "transforms": "convertTS",
        "transforms.convertTS.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
        "transforms.convertTS.field": "order_timestamp",
        "transforms.convertTS.format": "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "transforms.convertTS.target.type": "Timestamp"
    }
}
```

- JDBC Sink Connector 생성등록

```bash
register_connector mysql_jdbc_oc_sink_timestamp_tab_01.json
```

- oc_sink.orders_timestamp_tab_sink 테이블의 데이터 확인.
- oc_sink.orders_timestamp_tab_sink 데이터 확인 후 truncate 수행.

```sql
use oc_sink;

truncate table orders_timestamp_tab_sink;
```

- 아래와 같은 JDBC Sink Connector 설정을 mysql_jdbc_oc_sink_timestamp_tab_02.json으로 설정. "db.timezone": "Asia/Seoul" 추가

```json
{
    "name": "mysql_jdbc_oc_sink_timestamp_tab_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "test01.oc.orders_timestamp_tab",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_timestamp_tab_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "db.timezone": "Asia/Seoul",

        "transforms": "convertTS",
        "transforms.convertTS.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
        "transforms.convertTS.field": "order_timestamp",
        "transforms.convertTS.format": "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "transforms.convertTS.target.type": "Timestamp"
    }
}
```

- JDBC Sink Connector 생성등록

```bash
register_connector mysql_jdbc_oc_sink_timestamp_tab_02.json
```

- oc_sink.orders_timestamp_tab_sink 테이블의 데이터 확인.
- 테스트용으로 생성한 connector 모두 삭제

```bash
delete_connector mysql_cdc_oc_source_timestamp_tab_01
delete_connector mysql_jdbc_oc_sink_timestamp_tab_01
delete_connector mysql_jdbc_oc_sink_timestamp_tab_02
```

### 대량 데이터로 Debezium Source Connector와 JDBC Sink Connector 연동 테스트

- 기존 Source 테이블에 있는 모든 데이터를 삭제.  연동이 제대로 되어 있으면 Source 테이블에만 delete 적용해도 target 테이블도 같이 적용. 만일 Source 테이블에 Truncate를 적용하였으면 Target쪽에도 수동으로 SQL을 통해 Truncate 적용.
- 대량 DML를 소스 테이블에 수행할 수 있는 Procedure를 아래와 같이 생성.

```sql
use oc;

DELIMITER $$

DROP PROCEDURE IF EXISTS oc.CONNECT_DML_TEST$$

create procedure CONNECT_DML_TEST(
  max_id INTEGER, 
  repeat_cnt INTEGER,
  upd_mod INTEGER,
  sleep_mod INTEGER
)
BEGIN
  DECLARE customer_idx INTEGER;
  DECLARE product_idx INTEGER;
  DECLARE order_idx INTEGER;
 
  DECLARE iter_idx INTEGER;
  
  SET iter_idx = 1; 

  WHILE iter_idx <= repeat_cnt DO
    SET customer_idx = max_id + iter_idx;
    SET order_idx = max_id + iter_idx;
    SET product_idx = max_id + iter_idx;
    
    insert into oc.customers values (customer_idx, concat('testuser_', 
                     customer_idx),  concat('testuser_', customer_idx));

    insert into oc.products values (product_idx, concat('testproduct_', product_idx), 
                     concat('testcat_', product_idx), 100* iter_idx/upd_mod);
    
    insert into oc.orders values (order_idx, now(), customer_idx, 'delivered', 1);

    insert into oc.orders_datetime_tab values (order_idx, now(), now(), customer_idx, 'delivered', 1);
       
    insert into oc.order_items values (order_idx, mod(iter_idx, upd_mod)+1, mod(iter_idx, upd_mod)+1, 100* iter_idx/upd_mod, 1); 
    
    if upd_mod > 0 and mod(iter_idx, upd_mod) = 0 then
       update oc.customers set full_name = concat('updateduser_', customer_idx) where customer_id = customer_idx;
       update oc.products set product_name = concat('updproduct_', product_idx) where product_id = product_idx;
       update oc.orders set  order_status = 'updated' where order_id = order_idx;
       update oc.orders_datetime_tab set  order_status = 'updated' where order_id = order_idx;
       update oc.order_items set quantity = 2 where order_id = order_idx;

       delete from oc.customers where customer_id = customer_idx -1;
       delete from oc.products where product_id = product_idx - 1;
       delete from oc.orders where order_id = order_idx - 1;
       delete from oc.orders_datetime_tab where order_id = order_idx -1;
       delete from oc.order_items where order_id = order_idx - 1;
 
    end if;

    if sleep_mod > 0 and mod(iter_idx, sleep_mod) = 0 then
        select sleep(1);
    end if;
   
    SET iter_idx = iter_idx + 1;
  END WHILE;
END$$

DELIMITER ;
```

- 기존 테이블 데이터 삭제

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

- CONNECT_DML_TEST 호출하여 Insert/Update/Delete 수행 테스트. 1000건의 데이터 입력 및 100번 수행시 마다 update와 delete 수행 및 1초 휴식

```sql
use oc;

call CONNECT_DML_TEST(0, 1000, 100, 100);
```

- oc.customers, oc.products, oc.orders, oc.order_items 테이블 데이터 확인.

### 연동 테스트를 위해 Debezium Source Connector 및 JDBC Sink Connector 재 설정

- date/time/datetime/timestamp 처리를 위한 Debezium Source Connector와 JDBC Sink Connector 재설정.
- Debezium Source Connector는 아래 설정으로 mysql_cdc_oc_source_02.json으로 저장.

```json
{
    "name": "mysql_cdc_oc_source_02",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.allowPublicKeyRetrieval": "true",

        "database.server.id": "12000",
        "database.server.name": "mysql02",
        "database.include.list": "oc",
        "table.include.list": "oc.customers, oc.products, oc.orders, oc.order_items, oc.orders_datetime_tab", 
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

- oc_sink.customers_sink 테이블의 sink를 위해서 아래 설정을 mysql_jdbc_oc_sink_customers_02.json으로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_customers_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql02.oc.customers",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.customers_sink",
        "insert.mode": "upsert",
        "pk.fields": "customer_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- oc_sink.products_sink 테이블의 sink를 위해서 아래 설정을 mysql_jdbc_oc_sink_products_02.json으로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_products_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql02.oc.products",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.products_sink",
        "insert.mode": "upsert",
        "pk.fields": "product_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- oc_sink.orders 테이블의 sink를 위해서 아래 설정을 mysql_jdbc_oc_sink_orders_02.json으로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_orders_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql02.oc.orders",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "db.timezone": "Asia/Seoul",

        "transforms": "convertTS",
        "transforms.convertTS.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
        "transforms.convertTS.field": "order_datetime",
        "transforms.convertTS.format": "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "transforms.convertTS.target.type": "Timestamp"
    }
}
```

- oc_sink.orders_datetime_tab 테이블의 sink를 위해서 아래 설정을 mysql_jdbc_oc_sink_orders_datetime_tab_02.json으로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_orders_datetime_tab_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql02.oc.orders_datetime_tab",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_datetime_tab_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

    }
}
```

- oc_sink.order_items 테이블의 sink를 위해서 아래 설정을 mysql_jdbc_oc_sink_order_items_02.json으로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_order_items_02",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql02.oc.order_items",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.order_items_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id, line_item_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- 생성한 source connector와 sink connector를 모두 등록
- call CONNECT_DML_TEST(0, 5000, 100, 100)  호출
- 아래 SQL로 oc_sink 테이블들의 입력 건수 확인.

```sql
use oc_sink;

select 'customers_sink' as table_name, count(*) from customers_sink
union all
select 'products_sink' as table_name, count(*) from products_sink
union all
select 'orders_sink' as table_name, count(*) from orders_sink
union all
select 'orders_datetime_tab_sink' as table_name, count(*) from orders_datetime_tab_sink
union all
select 'order_items_sink' as table_name, count(*) from order_items_sink;
```

### Debezium Source Connector의 Batch 처리 이해

- Debezium Source Connector는 한번에 여러건의 데이터를 DB로 부터 읽어서 이를 Producer가 Kafka로 전송
- connect-offsets 토픽에서 mysql_cdc_oc_source_02 Connector의 offsets 정보 확인.

```sql
kafkacat -b localhost:9092 -C -t connect-offsets -J -u -q |jq -c '{key , payload}' | grep 'mysql_cdc_oc_source_02'
```

### JDBC Sink Connector의 Batch 처리 이해

- JDBC Sink Connector는 한번에 여러건의 데이터를 Consumer가 읽어서 DB에 입력
- __consumer_offsets 토픽에서 jdbc sink connector의 offsets 정보 확인.

```sql
echo "exclude.internal.topics=false" > consumer_temp.config
kafka-console-consumer --consumer.config /home/min/consumer_temp.config  --bootstrap-server localhost:9092 --topic __consumer_offsets  --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" --from-beginning | grep 'mysql_jdbc_oc_sink_.*_02'
```

### Topic 명의 dot(.)을 dash로 변경하기

- 기본적으로 debezium은 topic명을 database.server.name+ “.” + database.include.list+”.” + table.include_list를 조합하여 만듬.  기존 생성된 토픽명이 dash를 기준으로 되어 있거나 dot을 dash로 변경하기 위해 RegexRouter SMT 적용.
- 기존 [database.server.name](http://database.server.name) = mysql-02, database.include.list=oc, table.include.list=oc.customers 일 경우 topic명은 mysql-02.oc.customers로 생성됨. 이를 mysql-02-oc-customers 로 토픽명 변경
- 정규 표현식의 dot(.)는 특수문자이므로 이를 단순 문자로 인식하기 위해 \ 추가. json에서 \을 인식시키기 위해 \\ 로 변경

```sql
{
    "name": "mysql_cdc_oc_source_rename_topic",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "10013",
        "database.server.name": "mysql-02",
        "database.include.list": "oc",
        "table.include.list": "oc.customers, oc.orders",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql-02.oc",

        "database.allowPublicKeyRetrieval": "true",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "transforms": "rename_topic",
        "transforms.rename_topic.type": "org.apache.kafka.connect.transforms.RegexRouter",
        "transforms.rename_topic.regex": "(.*)\\.(.*)\\.(.*)",
        "transforms.rename_topic.replacement": "$1-$2-$3"
    }
}
```

### 동일한 Source 테이블에 여러개의 Connector를 적용할 때 문제점

- 동일한 Source 테이블에 여러개의 Connector가 생성을 할 수는 있지만 이들중 단 하나의 Connector만 해당 테이블의 변경 사항을 Topic 메시지를 생성함에 유의. 따라서 동일한 Source 테이블에 여러개의 Connector를 생성하는 것은 피해야 함.
- mysql_cdc_oc_source_01_test.json 파일에 아래와 같이 oc.customers를 Source 테이블로 하는 새로운 Source Connector를 생성할 수 있도록 config 설정하고 Connector에 등록.  topic name은 mysql-01-test로 시작할 수 있도록 변경.

```sql
{
    "name": "mysql_cdc_oc_source_01_test",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "10022",
        "database.server.name": "mysql-01-test",
        "database.include.list": "oc",
        "table.include.list": "oc.customers",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql-01.oc",

        "database.allowPublicKeyRetrieval": "true",
        "database.connectionTimeZone": "Asia/Seoul",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- Connect에 새로운 Connector 등록하고 해당 topic들과 connect-offsets 토픽 메시지 확인

```sql
# connect-offsets 메시지 확인. 
kafkacat -b localhost:9092 -C -t connect-offsets -J -u -q |jq '.'

# mysql-01-test.oc.customers 메시지 확인.
kafkacat -b localhost:9092 -C -t mysql-01-test.oc.customers -J -u -q |jq '.'

# mysql-01.oc.customers 메시지 확인.
kafkacat -b localhost:9092 -C -t mysql-01.oc.customers -J -u -q |jq '.'
```

- 새로운 데이터를 oc.customers 테이블에 입력하고 토픽 메시지들을 확인.

```sql
use oc;

insert into customers values (7, 'testmail', 'testuser');
```

- 추가로 등록한 connector를 삭제하고 토픽 메시지들을 확인

```sql
delete_connector mysql_cdc_oc_source_01_test
```

- 최초 등록한 connector를 삭제후 재 등록하고 토픽 메시지들을 확인

```sql
delete_connector mysql_cdc_oc_source_01
register_connector mysql_cdc_oc_source_01.json
```

### max.batch.size, max.queue.size 테스트

- source connector의 batch size 테스트를 위해 oc.customers_batch 테이블을 생성.

```sql
use oc;

CREATE TABLE customers_batch (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB;
```

- customers_batch 테이블에 데이터를 insert하는 procedure 생성.

```sql
use oc;

DELIMITER $$

DROP PROCEDURE IF EXISTS oc.INSERT_CUSTOMERS_BATCH$$

create procedure INSERT_CUSTOMERS_BATCH(
  max_customer_id INTEGER,
	repeat_cnt INTEGER
)
BEGIN
	DECLARE customer_idx INTEGER;
	DECLARE iter_idx INTEGER;
  
  SET iter_idx = 1; 

	WHILE iter_idx <= repeat_cnt DO
    SET customer_idx = max_customer_id + iter_idx;
       
    insert into oc.customers_batch values (customer_idx, concat('testuser_', 
                     customer_idx),  concat('testuser_', customer_idx));
   
    SET iter_idx = iter_idx + 1;
  END WHILE;
END$$

DELIMITER ;
```

- 아래를 호출하여 10,000건을 입력

```sql
call INSERT_CUSTOMERS_BATCH(0, 10000);

select count(*) from oc.customers_batch;
```

- customers_batch 테이블을 Source로 하는 Source Connector를 아래와 같이 생성.

```json
"name": "mysql_cdc_oc_source_02_batch",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "10024",
        "database.server.name": "mysql02-batch",
        "database.include.list": "oc",
        "table.include.list": "oc.customers_batch",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql-01.oc",

        "database.allowPublicKeyRetrieval": "true",
        "database.connectionTimeZone": "Asia/Seoul",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

```json
# connect-offsets 메시지 확인. 
kafkacat -b localhost:9092 -C -t connect-offsets -J -u -q |jq '.'

# mysql02-batch.oc.customers_batch 메시지 확인.
kafkacat -b localhost:9092 -C -t mysql02-batch.oc.customers_batch -J -u -q |jq '.'
```

### 초기 Snapshot 모드 변동 테스트

- snapshot.mode=initial 로 default로 설정되어 있으면 connector를 생성하기 이전에 기존 소스 테이블에 생성되어 있는 레코드를 모두 카프카로 보내어서 동기화를 시킴. 기존 테이블의 데이터가 너무 클 경우 snapshot에 매우 오랜 시간이 소모됨.
- Connector가 생성되기 이전의 데이터를 메시지 생성하지 않을 경우 snapshot.mode를 schama_only로 설정하면 connector 생성 이후의 변경 데이터만 메시지로 생성.
- oc.customers_batch 테이블에 데이터가 대량으로 들어있는지 확인.

```json
use oc;

select count(*) from oc.customers_batch;

select max(customer_id) from oc.customers_batch;
```

- 기존 oc.customers_batch 테이블을 처리하는 Source Connector 삭제
- snapshot.mode를 schema_only로 설정한 아래 config를 mysql_cdc_oc_source_04_chonly.json으로 저장하고 새로운 connector 등록 생성.

```json
{
    "name": "mysql_cdc_oc_source_04_chonly",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "10027",
        "database.server.name": "mysql04-chonly",
        "database.include.list": "oc",
        "table.include.list": "oc.customers_batch",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql-01.oc",

        "snapshot.mode": "schema_only",

        "database.allowPublicKeyRetrieval": "true",
        "database.connectionTimeZone": "Asia/Seoul",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- mysql04-chonly.oc.customers_batch 토픽명으로 토픽이 생성되는지 확인.
- 100건의 데이터를 customers_batch 테이블에 입력 후

```json
call INSERT_CUSTOMERS_BATCH(30001, 100);
```

- mysql04-chonly.oc.customers_batch 토픽에 데이터 입력 건수 확인.

```json
kafkacat -b localhost:9092 -t mysql04-chonly.oc.customers_batch -J -u -q | jq '.'
```
