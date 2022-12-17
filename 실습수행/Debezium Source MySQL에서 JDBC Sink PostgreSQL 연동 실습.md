# Debezium Source MySQL에서 JDBC Sink PostgreSQL 연동 실습

- mysql -u root -p 로 root 사용자로 mysql 접속 후 ops 데이터베이스 생성하고 connect_dev 사용자에게 접근 권한 부여

```sql

create database ops;
show databases;
# 데이터베이스 사용권한 부여
grant all privileges on ops.* to 'connect_dev'@'%' with grant option;

flush privileges;
```

- mysql -u connect_dev -p 로 connect_dev 사용자로 접속 후 아래 DDL로 테스트용 테이블을 생성.

```sql
use ops;

drop table if exists customers;
drop table if exists products;
drop table if exists orders;
drop table if exists order_items;
drop table boards;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB ;

CREATE TABLE products (
	product_id int NOT NULL PRIMARY KEY,
	product_name varchar(100) NULL,
	product_category varchar(200) NULL,
	unit_price decimal(10,0) NULL
) ENGINE=InnoDB ;

CREATE TABLE orders (
	order_id int NOT NULL PRIMARY KEY,
	order_datetime timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ENGINE=InnoDB ;

CREATE TABLE order_items (
	order_id int NOT NULL,
	line_item_id int NOT NULL,
	product_id int NOT NULL,
	unit_price decimal(10, 2) NOT NULL,
	quantity int NOT NULL,
	primary key (order_id, line_item_id)
) ENGINE=InnoDB;

CREATE TABLE boards (
  board_id int NOT NULL PRIMARY KEY,
  subject_name varchar(100) NOT NULL,
  customer_id int NOT NULL,
  write_date date NOT NULL,
  write_datetime datetime NOT NULL,
  content text
) ENGINE=InnoDB;

select * from customers;
select * from products;
select * from orders;
select * from order_items;
select * from boards;
```

### PostgreSQL 설치하기

- 실습 환경 시스템 update && upgrade

```sql
sudo apt update
sudo apt -y upgrade
```

- postgresql 설치

```sql
sudo apt install postgresql postgresql-client
```

### PostgreSQL DB 환경 구축

- postgres os 사용자로 로그인한 뒤 /etc/postgresql/12/main 디렉토리로 이동.

```sql
sudo su - postgres
cd /etc/postgresql/12/main
```

- postgresql.conf 의 listen_addresses 설정을 ‘*’ 으로, Debezium에서 replication 적용하기 위해 wal_level = logical 으로 변경.

```sql
listen_addresses = '*'

wal_level = logical
```

- pg_hba.conf의 아래 IPV4의 address를 0.0.0.0/0 으로 변경

```sql
# "local" is for Unix domain socket connections only
local   all             all                                     md5

# IPv4 local connections:
host    all             all             0.0.0.0/0            md5
```

- postgresql 재 기동.

```sql
sudo systemctl restart postgresql
```

- psql 접속

```sql
sudo su - postgres
psql
```

- 새로운 user connect_dev 생성.

```sql
create user connect_dev password 'connect_dev';
alter user connect_dev createdb;
grant all privileges on database postgres to connect_dev;
```

- 새로운 user인 connect_dev로 postgres DB 접속

```sql
psql -h localhost -U connect_dev -d postgres
```

- psqll 접속 후 접속 DB 확인 및 신규 스키마 op_sink 생성.

```sql
\conninfo
\l
create schema ops_sink;
\dn
```

- default schema를 op_sink로 설정.

```sql
show search_path;
set search_path=ops_sink;
show search_path;
```

- op_sink 스키마에 테스트용 테이블 생성.

```sql
show search_path;

drop table if exists customers_sink;
drop table if exists products_sink;
drop table if exists orders_sink;
drop table if exists order_items_sink;
drop table if exists boards_sink;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_sink (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
);

CREATE TABLE products_sink (
	product_id int NOT NULL PRIMARY KEY,
	product_name varchar(100) NULL,
	product_category varchar(200) NULL,
	unit_price decimal(10,0) NULL
);

CREATE TABLE orders_sink (
	order_id int NOT NULL PRIMARY KEY,
	order_datetime timestamptz NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
);

CREATE TABLE order_items_sink (
	order_id int NOT NULL,
	line_item_id int NOT NULL,
	product_id int NOT NULL,
	unit_price decimal(10, 2) NOT NULL,
	quantity int NOT NULL,
	primary key (order_id, line_item_id)
);

CREATE TABLE boards_sink (
  board_id int NOT NULL PRIMARY KEY,
  subject_name varchar(100) NOT NULL,
  customer_id int NOT NULL,
  write_date date NOT NULL,
  write_datetime timestamp NOT NULL,
  content text
);

select * from customers_sink;
select * from products_sink;
select * from orders_sink;
select * from order_items_sink;
select * from boards_sink;
```

### MySQL과 PostgreSQL 연동 테스트 - 환경 구축 및 Connector 설정

- Partition 3개로 Topic을 미리 생성

```bash
kafka-topics --bootstrap-server localhost:9092 --create --topic mysqlavro-ops-customers --partitions 3
kafka-topics --bootstrap-server localhost:9092 --create --topic mysqlavro-ops-orders --partitions 3
kafka-topics --bootstrap-server localhost:9092 --create --topic mysqlavro-ops-products --partitions 3
kafka-topics --bootstrap-server localhost:9092 --create --topic mysqlavro-ops-order_items --partitions 3
kafka-topics --bootstrap-server localhost:9092 --create --topic mysqlavro-ops-boards --partitions 3
```

- MySQL ops DB를 소스 테이블로 하는 Source Connector 생성. mysql_cdc_ops_source_avro_01.json 파일로 아래 설정.

```json
{
    "name": "mysql_cdc_ops_source_avro_01",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "30000",
        "database.server.name": "mysqlavro",
        "database.include.list": "ops",
        "table.include.list": "ops.customers, ops.products, ops.orders, ops.order_items, ops.boards",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",

        "time.precision.mode": "connect",
        "database.connectionTimezone": "Asia/Seoul",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081",

        
        "transforms": "rename_topic, unwrap",
        "transforms.rename_topic.type": "org.apache.kafka.connect.transforms.RegexRouter",
        "transforms.rename_topic.regex": "(.*)\\.(.*)\\.(.*)",
        "transforms.rename_topic.replacement": "$1-$2-$3",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- PostgreSQL ops_sink 스키마의 Customers_sink 테이블을 Sink로 하는 JDBC Sink Connector 생성.  postgres_jdbc_ops_sink_customers_avro_01.json 파일로 아래 설정.

```json
{
    "name": "postgres_jdbc_ops_sink_customers_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro-ops-customers",
        "connection.url": "jdbc:postgresql://localhost:5432/postgres",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "ops_sink.customers_sink",

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

- PostgreSQL ops_sink 스키마의 products_sink 테이블을 Sink로 하는 JDBC Sink Connector 생성.  postgres_jdbc_ops_sink_products_avro_01.json 파일로 아래 설정.

```json
{
    "name": "postgres_jdbc_ops_sink_products_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro-ops-products",
        "connection.url": "jdbc:postgresql://localhost:5432/postgres",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "ops_sink.products_sink",

        "insert.mode": "upsert",
        "pk.fields": "product_id",
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

- PostgreSQL ops_sink 스키마의 orders_sink 테이블을 Sink로 하는 JDBC Sink Connector 생성.  postgres_jdbc_ops_sink_orders_avro_01.json 파일로 아래 설정.

```json
{
    "name": "postgres_jdbc_ops_sink_orders_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro-ops-orders",
        "connection.url": "jdbc:postgresql://localhost:5432/postgres",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "ops_sink.orders_sink",

        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "auto.evolve": "true",
        
        "transforms": "convertTS",
        "transforms.convertTS.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
        "transforms.convertTS.field": "order_datetime",
        "transforms.convertTS.format": "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "transforms.convertTS.target.type": "Timestamp",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"
    }
}
```

- PostgreSQL ops_sink 스키마의 order_items_sink 테이블을 Sink로 하는 JDBC Sink Connector 생성.  postgres_jdbc_ops_sink_order_items_avro_01.json 파일로 아래 설정.

```json
{
    "name": "postgres_jdbc_ops_sink_order_items_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro-ops-order_items",
        "connection.url": "jdbc:postgresql://localhost:5432/postgres",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "ops_sink.order_items_sink",

        "insert.mode": "upsert",
        "pk.fields": "order_id, line_item_id",
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

- PostgreSQL ops_sink 스키마의 boards_sink 테이블을 Sink로 하는 JDBC Sink Connector 생성.  postgres_jdbc_ops_sink_boards_avro_01.json 파일로 아래 설정.

```json
{
    "name": "postgres_jdbc_ops_sink_boards_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro-ops-boards",
        "connection.url": "jdbc:postgresql://localhost:5432/postgres",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "ops_sink.boards_sink",

        "insert.mode": "upsert",
        "pk.fields": "board_id",
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

### Source와 Sink Connector 생성 후 MySQL에 데이터 입력하여 PostgreSQL과 연동 되는지 테스트

- mysql -u connect_dev -p 로 connect_dev 사용자로 접속 후 대량 DML 발생 Procedure 생성.

```sql
use ops;

DELIMITER $$

DROP PROCEDURE IF EXISTS ops.CONNECT_DML_TEST_01$$

create procedure CONNECT_DML_TEST_01(
  max_id INTEGER, 
  repeat_cnt INTEGER,
  upd_mod INTEGER,
  sleep_mod INTEGER, 
  sleep_sec INTEGER
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
    
    insert into ops.customers values (customer_idx, concat('testuser_', customer_idx)
                , concat('testuser_', customer_idx));

    insert into ops.products values (product_idx, concat('testproduct_', product_idx)
                , concat('testcat_', product_idx), 100* iter_idx/upd_mod);
    
    insert into ops.orders values (order_idx, now(), customer_idx, 'delivered', 1);                   
       
    insert into ops.order_items values (order_idx, mod(iter_idx, upd_mod)+1, 
                mod(iter_idx, upd_mod)+1, 100* iter_idx/upd_mod, 1); 

    insert into ops.boards values (iter_idx, concat('testsubject_', iter_idx), customer_idx, 
                      now(), now(), concat('testcontent ###################################_', iter_idx));
    
    if upd_mod > 0 and mod(iter_idx, upd_mod) = 0 then
       update ops.customers set full_name = concat('updateduser_', customer_idx) where customer_id = customer_idx;
       update ops.products set product_name = concat('updproduct_', product_idx) where product_id = product_idx;
       update ops.orders set  order_status = 'updated' where order_id = order_idx;
       update ops.order_items set quantity = 2 where order_id = order_idx;
       update ops.boards set content = concat('updatedcontent ###################################_', iter_idx)
              where board_id = iter_idx;

       delete from ops.customers where customer_id = customer_idx -1;
       delete from ops.products where product_id = product_idx - 1;
       delete from ops.orders where order_id = order_idx - 1;
       delete from ops.order_items where order_id = order_idx - 1;
       delete from ops.boards where board_id = iter_idx;
 
    end if;

    if sleep_mod > 0 and mod(iter_idx, sleep_mod) = 0 then
        select sleep(sleep_sec);
    end if;
   
    SET iter_idx = iter_idx + 1;
  END WHILE;
END$$

DELIMITER ;
```

- MySQL의 기존 ops DB의 테이블 Truncate

```sql
use ops;

truncate table customers;
truncate table orders;
truncate table products;
truncate table order_items;
truncate table boards;

```

- PostgreSQL의 기존 ops_sink 스키마의 테이블 Truncate

```sql
set search_path=ops_sink;

truncate table customers_sink;
truncate table orders_sink;
truncate table products_sink;
truncate table order_items_sink;
truncate table boards_sink;
```

- source connector와 sink connector를 등록

```bash
register_connector mysql_cdc_ops_source_avro_01.json
register_connector postgres_jdbc_ops_sink_customers_avro_01.json
register_connector postgres_jdbc_ops_sink_products_avro_01.json 
register_connector postgres_jdbc_ops_sink_orders_avro_01.json
register_connector postgres_jdbc_ops_sink_order_items_avro_01.json  
register_connector postgres_jdbc_ops_sink_boards_avro_01.json
```

- mysql -u connect_dev -p’connect_dev’ 로 접속하여 CALL_DML_TEST_01 프로시저를 수행 후 MySQL 데이터 입력 및 PostgreSQL에 데이터가 연동되는지 확인.

```sql
use ops;
-- 1000번 Loop 수행, 10번 수행시마다 Update/Delete, 100번 수행 시마다 1초 sleep
call CONNECT_DML_TEST_01(0, 1000, 10, 100, 1);
```