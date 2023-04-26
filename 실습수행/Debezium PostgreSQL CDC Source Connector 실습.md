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