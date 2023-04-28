# Debezium PostgreSQL CDC Source Connector 실습

### PostgreSQL 설치하기(기 적용됨)

- 실습 환경 시스템 update && upgrade

```sql
sudo apt update
sudo apt -y upgrade
```

- postgresql 설치

```sql
sudo apt install postgresql postgresql-client
```

### PostgreSQL DB 환경 구축(기 적용됨)

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

### 실습용 사용자 생성(기 적용됨)

- postgres OS 사용자로 접속하여 psql 수행

```sql
sudo su - postgres
psql
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

### Source 및 Sink DB 생성 및 Replication user인 connect_dev에 replication 권한 부여

- psql에서 postgres 유저의 password 변경

```sql
sudo su - postgres
psql

\du
alter user postgres with password 'postgres';
```

- 현재 DB 리스트 및 접속 정보 조회

```sql
\l
\conninfo
```

- oc database 생성

```sql
create database oc;

create database oc_sink;
```

- 복제를 위해 connect_dev 사용자에 superuser, login, replication role 할당하고 oc 및 oc_sink 데이터베이스 권한 부여

```sql

alter user connect_dev with superuser login replication;
\du

grant all privileges on database oc to connect_dev;
grant all privileges on database oc_sink to connect_dev;
```

- connect_dev 사용자로 oc DB접속 후 DB Encoding 정보 확인.

```sql
psql -h localhost -U connect_dev -d oc

\conninfo
SHOW SERVER_ENCODING;
```

- 아래 스크립트를 수행하여 oc 데이터베이스의 public schema 에 customers, products, orders, order_items 테이블 생성

```sql
\connect oc;

CREATE TABLE public.customers (
	customer_id int NOT NULL PRIMARY KEY,
	email_address varchar(255) NOT NULL,
	full_name varchar(255) NOT NULL
);

CREATE TABLE public.products (
	product_id int NOT NULL PRIMARY KEY,
	product_name varchar(100) NULL,
	product_category varchar(200) NULL,
	unit_price numeric NULL
);

CREATE TABLE public.orders (
	order_id int NOT NULL PRIMARY KEY,
	order_datetime timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ;

CREATE TABLE public.order_items (
	order_id int NOT NULL,
	line_item_id int NOT NULL,
	product_id int NOT NULL,
	unit_price numeric(10, 2) NOT NULL,
	quantity int NOT NULL,
	primary key (order_id, line_item_id)
);

\dt
\d customers
\d products
\d orders
\d order_items
```

- 아래 스크립트를 수행하여 oc_sink 데이터베이스의 public schema 에 customers_sink, products_sink, orders_sink, order_items_sink 테이블 생성

```sql
\connect oc_sink;
\conninfo;

CREATE TABLE public.customers_sink (
	customer_id int NOT NULL PRIMARY KEY,
	email_address varchar(255) NOT NULL,
	full_name varchar(255) NOT NULL
);

CREATE TABLE public.products_sink (
	product_id int NOT NULL PRIMARY KEY,
	product_name varchar(100) NULL,
	product_category varchar(200) NULL,
	unit_price numeric NULL
);

CREATE TABLE public.orders_sink (
	order_id int NOT NULL PRIMARY KEY,
	order_datetime timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ;

CREATE TABLE public.order_items_sink (
	order_id int NOT NULL,
	line_item_id int NOT NULL,
	product_id int NOT NULL,
	unit_price numeric(10, 2) NOT NULL,
	quantity int NOT NULL,
	primary key (order_id, line_item_id)
);

\dt
\d customers_sink
\d products_sink
\d orders_sink
\d order_items_sink
```

### ExtractNewRecordState SMT 적용하여 Source Connector 생성

- postgres_cdc_oc_source_01.json 파일에 아래 설정 저장.

```sql
{
    "name": "postgres_cdc_oc_source_01",
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.hostname": "localhost",
        "database.port": "5432",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.dbname": "oc",
        "database.server.name": "pg01",

        "plugin.name": "pgoutput",
        "slot.name": "debezium_01",

        "schema.include_list": "public",
        "table.include.list": "public.customers, public.products, public.orders, public.order_items",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter", 
        
        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"

    }
}
```

- 해당 파일을 Connect에 등록하여 신규 Connector 생성

```sql
register_connector postgres_cdc_oc_source_01.json
show_connectors
```

- customers, orders, products, order_items에 데이터 입력

```sql
sudo su - postgres
psql -h localhost -U connect_dev -d oc;

\conninfo

insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01');
insert into customers values (2, 'testaddress_02@testdomain', 'testuser_02');
insert into orders values(1, now(), 1, 'delivered', 1);
insert into products values(1, 'testproduct', 'testcategory', 100);
insert into order_items values(1, 1, 1, 100, 1);

```

- 토픽 생성 및 토픽 메시지 확인

```sql
show_topic_messages json pg.public.customers
```

### JDBC Sink Connector로 데이터 입력

- oc_sink DB에 토픽 메시지를 입력하는 Connector를 아래와 같이 생성
- postgres_jdbc_oc_sink_customers_01.json 파일에 아래 설정 저장

```sql
{
    "name": "postgres_jdbc_oc_sink_customers_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "pg01.public.customers",
        "connection.url": "jdbc:postgresql://localhost:5432/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "public.customers_sink",

        "insert.mode": "upsert",
        "pk.fields": "customer_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- jdbc sink connector 등록

```sql
register_connector postgres_jdbc_oc_sink_customers_01.json
show_connectors
```

- oc_sink DB에 접속하여 customers_sink 테이블에 데이터가 입력되었는지 확인

```sql

\connect oc_sink
select * from customers_sink;
```

### Source Connector에서 Publication 생성 및 적용

- 모든 테이블에 대해서 publication을 적용하는 dbz_publication 생성이 되어 있음을 확인. slot 정보도 함께 확인. pg_replication_slots는 모든 db에 대한 replication slot정보를 가지고 있음.

```sql
\connect oc

select * from pg_publication;

select * from pg_replication_slots;
```

- PK가 없는 임의의 테이블을 생성 후 데이터 입력. 레코드 삭제 수행 시 오류 발생.  레코드 자체를 identity를 설정하면 문제 없이 삭제됨.

```sql
create table no_pk_tab
( col1 integer);

insert into no_pk_tab values (1);

-- 아래는 오류 발생. 
delete from no_pk_tab;

ALTER TABLE no_pk_tab REPLICA IDENTITY FULL;

delete from no_pk_tab;
```

- PK가 있는  테이블의 레코드 삭제는 문제 없음.

```sql
create table pk_tab
( col1 integer primary key);

insert into pk_tab values (1);

delete from pk_tab; 
```

- 특정 테이블만을 publication 하는 신규 publication_생성.

```sql
create publication pub_filtered for table public.customers, public.products, public.orders, public.order_items;
--create publication pub_all for all tables;
--create publication pub_schema for tables in public;

select * from pg_publication;

select * from pg_publication_tables;
```

- 기존 connector를 삭제한 후 publication이 삭제 되는 지 확인.

```sql
delete_connector postgres_cdc_oc_source_01;
```

- publication 삭제

```sql
drop publication dbz_publication;

select * from pg_publication;

-- 아래는 relication_slot 삭제
--select pg_drop_replication_slot('debezium_01');
```

- publication.name을 pub_filtered, publication.autocreate.mode를 filtered로 설정. postgres_cdc_oc_source_02.json 파일에 아래 설정 저장.

```sql
{
    "name": "postgres_cdc_oc_source_02",
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.hostname": "localhost",
        "database.port": "5432",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.dbname": "oc",
        "database.server.name": "pg02",

        "plugin.name": "pgoutput",
        "slot.name": "debezium_01",
        "publication.name": "pub_filtered",
        "publication.autocreate.mode": "filtered", 

        "schema.include_list": "public",
        "table.include.list": "public.customers, public.products, public.orders, public.order_items",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter", 
        
        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"

    }
}
```

- publication과 replication slot 삭제

```sql
drop publication pub_filtered;
drop publication dbz_publication;

SELECT pg_drop_replication_slot('debezium_01');
SELECT pg_drop_replication_slot('debezium_02');

```

### Source 테이블의 컬럼 추가에 따른 JDBC Sink Connector의 Target 테이블 자동 반영

- 아래와 같이새로운 테이블을 oc와 oc_sink DB에 생성.

```sql
psql -h localhost -U connect_dev -d oc

\conninfo

drop table if exists customers_redef;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_redef (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
);

insert into customers_redef (customer_id, email_address, full_name) values (1, 'test', 'test');

\connect oc_sink;

drop table if exists customers_redef_sink;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_redef_sink (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
);

```

- postgres_cdc_oc_source_redef.json파일에 아래 설정으로 Source Connect 생성

```sql
{
    "name": "postgres_cdc_oc_source_redef",
    "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "database.hostname": "localhost",
        "database.port": "5432",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.dbname": "oc",
        "database.server.name": "pgrd",

        "plugin.name": "pgoutput",
        "slot.name": "debezium_slot",

        "publication.name": "pub_schema",
        "publication.autocreate.mode": "filtered", 

        "schema.include_list": "public",
        
        "time.precision.mode": "connect",
        "database.connectionTimezone": "Asia/Seoul",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter", 
        
        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- auto.evolve=true 설정으로 postgres_jdbc_oc_sink_customers_redef.json 생성.

```json
{
    "name": "postgres_jdbc_oc_sink_customers_redef",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "pgrd.public.customers_redef",
        "connection.url": "jdbc:postgresql://localhost:5432/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "public.customers_redef_sink",

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
register_connector postgres_cdc_oc_source_redef.json
register_connector postgres_jdbc_oc_sink_customers_redef.json.json

# 토픽 메시지 확인
show_topic_messages json pgrd.public.customers_redef
```

- publication과 replication slot 확인.

```bash
\connect oc

select * from pg_publication;

select * from pg_replication_slots;
```

### Source 테이블에 숫자형 컬럼 추가

- oc DB의 customers_redef 테이블에 정수형 컬럼 추가(default Null) 및 데이터 입력

```sql
\connect oc;

alter table customers_redef add column age int;

\d customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age) 
values (2, 'test', 'test', 40);
```

- 토픽 메시지 및 Target 테이블 변경 확인

```bash
show_topic_messages json pgrd.public.customers_redef
```

- oc DB의 customers_redef 테이블에 Not Null 정수형 컬럼 추가 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
\connect oc;

alter table customers_redef add column salary int not null default 0;

\d customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary) 
values (3, 'test', 'test', 30, 10000);
```

### Source 테이블에 varchar 컬럼 추가

- customers_redef 테이블에 varchar 컬럼 추가(Null) 및 데이터 입력 후 토픽 메시지와 Target 테이블 변경 확인

```sql
\connect oc;

alter table customers_redef add column address_01 varchar(100);

\d customers_redef;

insert into customers_redef (customer_id, email_address, full_name, age, salary, address_01) 
values (4, 'test', 'test', 30, 10000, 'test address 04');
```

- Target 테이블 값 및 데이터 타입 확인.

```sql
\connect oc_sink;

select * from customers_redef_sink;

\d customers_redef_sink
```

- Sink Connector 상태 정지(또는 삭제)

```sql
http GET http://localhost:8083/connectors/postgres_jdbc_oc_sink_customers_redef/status

delete_connector postgres_jdbc_oc_sink_customers_redef
```

- Target 테이블 customers_redef_sink의 address_01 컬럼을 varchar(100)으로 변경

```sql
\connect oc_sink;

alter table customers_redef_sink alter column address_01 type varchar(100);

\d customers_redef_sink;
```

- postgres_jdbc_oc_sink_customers_redef Sink Connector 재 기동 수행.

```sql
http GET http://localhost:8083/connectors/postgres_jdbc_oc_sink_customers_redef/status

register_connector postgres_jdbc_oc_sink_customers_redef.json
```

- oc db에서 customers_redef 테이블에 새로운 데이터 입력 후 oc_sink에서 데이터 확인

```sql
\connect oc;

insert into customers_redef (customer_id, email_address, full_name, age, salary, address_01) 
values (5, 'test', 'test', 30, 10000, 'test address 05');

\connect oc_sink;

select * from customers_redef;

\d customers_redef_sink;
```

### Timezone에 따른 timestamp와 timestamptz 출력 값 차이

- timestamptz 확인

```sql
show timezone;

select now();

create table timestamp_test
(
timestamp_col timestamp,
timestamptz_col timestamptz
);

insert into timestamp_test 
values (
'2023-04-27 14:00:00',
'2023-04-27 14:00:00'
);

select * from timestamp_test;

set timezone='UTC';

select * from timestamp_test;

```

### Source 테이블에 date, timestamp, timestamptz 컬럼 추가

- oc db의 temporal_tab 테이블에 date/timestamp/timestamptz 컬럼 생성 및 데이터 입력 . 데이터 입력 전에 pub_schema publication에 신규 테이블인 temporal_tab 테이블 등록

```sql
\connect oc

create table temporal_tab
( id int primary key,
  date_col date,
  timestamp_col timestamp,
  timestamptz_col timestamptz
);

select * from pg_publication;

select * from pg_publication_tables;

alter publication pub_schema add table temporal_tab;

insert into temporal_tab values (1, '2023-04-26', '2023-04-26 19:00:00', '2023-04-26 19:00:00');
```

- connector 재기동

```sql
show_connectors

delete_connector postgres_cdc_oc_source_redef

register_connector postgres_cdc_oc_source_redef
```

- topic 메시지 확인

```sql
show_topic_messages json pgrd.public.temporal_tab;
```

- oc_sink db에 temporal_tab_sink 테이블 생성.

```sql
\connect oc_sink;

create table temporal_tab_sink
( id int primary key,
  date_col date,
  timestamp_col timestamp,
  timestamptz_col timestamptz
);
```

- sink connector 생성. postgres_jdbc_oc_sink_temporal_tab.json 파일로 설정.

```sql
{
    "name": "postgres_jdbc_oc_sink_temporal_tab",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "pgrd.public.temporal_tab",
        "connection.url": "jdbc:postgresql://localhost:5432/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "public.temporal_tab_sink",

        "insert.mode": "upsert",
        "pk.fields": "id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "auto.evolve": "true",

        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter", 

        "transforms": "convertTS",
        "transforms.convertTS.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
        "transforms.convertTS.field": "timestamptz_col",
        "transforms.convertTS.format": "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "transforms.convertTS.target.type": "Timestamp"
    }
}
```

- connector 등록 후 sink 테이블 확인