# Sink Connector 연동을 위한 신규 Source Connector 생성

### 신규 Source Connector 환경 파일 만들기

- 아래 규칙대로 Source Connector 환경파일 생성.

| 테이블명 | Json 파일명 | Connector 명 | Topic 명 |
| --- | --- | --- | --- |
| Customers | mysql_jdbc_source_customers.json | mysql_jdbc_source_customers | mysql_jdbc_customers |
| Products | mysql_jdbc_source_products.json | mysql_jdbc_source_products | mysql_jdbc_products |
| Orders | mysql_jdbc_source_orders.json | mysql_jdbc_source_orders | mysql_jdbc_orders |
| Order_items | mysql_jdbc_source_order_items.json | mysql_jdbc_source_order_items | mysql_jdbc_order_items |

 

- 개별 테이블별로 한개의 Source Connector 설정을 담은 json 파일을 다운로드

https://github.com/chulminkw/KafkaConnect/tree/main/connector_configs/jdbc_source_configs 에서 다운로드 할 수 있음. 

또는 아래와 같이 직접 curl 명령어로 다운로드 할 수 있음. 

```sql
cd ~/connector_configs
mkdir jdbc_source_configs
cd ~/connector_configs/jdbc_source_configs

curl -o mysql_jdbc_source_customers.json https://raw.githubusercontent.com/chulminkw/KafkaConnect/main/connector_configs/jdbc_source_configs/mysql_jdbc_source_customers.json
curl -o mysql_jdbc_source_order_items.json https://raw.githubusercontent.com/chulminkw/KafkaConnect/main/connector_configs/jdbc_source_configs/mysql_jdbc_source_order_items.json
curl -o mysql_jdbc_source_orders.json https://raw.githubusercontent.com/chulminkw/KafkaConnect/main/connector_configs/jdbc_source_configs/mysql_jdbc_source_orders.json
curl -o mysql_jdbc_source_products.json https://raw.githubusercontent.com/chulminkw/KafkaConnect/main/connector_configs/jdbc_source_configs/mysql_jdbc_source_products.json
```

### mysql_jdbc_source_customers.json 설정

```json
{
    "name": "mysql_jdbc_source_customers",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        
        "topic.prefix": "mysql_jdbc_",
        "catalog.pattern": "om", 
        "table.whitelist": "om.customers",
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

### mysql_jdbc_source_products.json 설정

```json
{
    "name": "mysql_jdbc_source_products",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",

        "topic.prefix": "mysql_jdbc_",
        "catalog.pattern": "om", 
        "table.whitelist": "om.products",
        "poll.interval.ms": 10000,
        "mode": "timestamp+incrementing",
        "incrementing.column.name": "product_id",
        "timestamp.column.name": "system_upd",
        
        "transforms": "create_key, extract_key",
        "transforms.create_key.type": "org.apache.kafka.connect.transforms.ValueToKey",
        "transforms.create_key.fields": "product_id",
        "transforms.extract_key.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
        "transforms.extract_key.field": "product_id"
    }
}
```

### mysql_jdbc_source_orders.json 설정

```json
{
    "name": "mysql_jdbc_source_orders",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",

        "topic.prefix": "mysql_jdbc_",
        "catalog.pattern": "om", 
        "table.whitelist": "om.orders",
        "poll.interval.ms": 10000,
        "mode": "timestamp+incrementing",
        "incrementing.column.name": "order_id",
        "timestamp.column.name": "system_upd",
        
        "transforms": "create_key, extract_key",
        "transforms.create_key.type": "org.apache.kafka.connect.transforms.ValueToKey",
        "transforms.create_key.fields": "order_id",
        "transforms.extract_key.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
        "transforms.extract_key.field": "order_id"
    }
}
```

### mysql_jdbc_source_order_items.json 설정

```json
{
    "name": "mysql_jdbc_source_order_items",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",

        "topic.prefix": "mysql_jdbc_",
        "catalog.pattern": "om", 
        "table.whitelist": "om.order_items",
        "poll.interval.ms": 10000,
        "mode": "timestamp",
        "timestamp.column.name": "system_upd",

        "transforms": "create_key",
        "transforms.create_key.type": "org.apache.kafka.connect.transforms.ValueToKey",
        "transforms.create_key.fields": "order_id, line_item_id"
    }
}
```

### MySQL om 데이터베이스의 테이블 데이터 재입력

- 기존 데이터를 삭제하고 새로운 데이터를 테이블별로 입력

```sql
use om;

-- 테이블 Drop 및 재 생성. 
use om;

drop table if exists customers;

drop table if exists products;

drop table if exists orders;

drop table if exists order_items;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers (
customer_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL,
system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_customers_001 on customers(system_upd);

CREATE TABLE products (
	product_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
	product_name varchar(100) NULL,
	product_category varchar(200) NULL,
	unit_price numeric NULL,
  system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_products_001 on products(system_upd);

CREATE TABLE orders (
	order_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
	order_datetime timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL,
	system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_orders_001 on orders(system_upd);

CREATE TABLE order_items (
	order_id int NOT NULL,
	line_item_id int NOT NULL,
	product_id int NOT NULL,
	unit_price numeric(10, 2) NOT NULL,
	quantity int NOT NULL,
  system_upd timestamp NOT NULL,
	primary key (order_id, line_item_id)
) ENGINE=InnoDB;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_order_items_001 on order_items(system_upd);

select * from customers;
select * from products;
select * from orders;
select * from order_items;
```

- 신규 데이터를 테이블 별로 입력

```sql
-- 테이블별 데이터 입력
insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01', now());
insert into customers values (2, 'testaddress_02@testdomain', 'testuser_02', now());
insert into orders values(1, now(), 1, 'delivered', 1, now());
insert into products values(1, 'testproduct', 'testcategory', 100, now());
insert into order_items values(1, 1, 1, 100, 1, now());
```

### 신규 Source Connector 생성 등록

- 새로운 json 파일을 기반으로 신규 Source Connector 생성 등록

```sql
cd ~/connector_configs/jdbc_source_configs

http POST http://localhost:8083/connectors @mysql_jdbc_source_customers.json
http POST http://localhost:8083/connectors @mysql_jdbc_source_products.json
http POST http://localhost:8083/connectors @mysql_jdbc_source_orders.json
http POST http://localhost:8083/connectors @mysql_jdbc_source_order_items.json
```

- 정상적으로 메시지가 Topic에 입력되었는지 메시지 확인

```sql
kafkacat -b localhost:9092 -t mysql_jdbc_customers -C -J -u -q | jq '.'
kafkacat -b localhost:9092 -t mysql_jdbc_products -C -J -u -q | jq '.'
kafkacat -b localhost:9092 -t mysql_jdbc_orders -C -J -u -q | jq '.'
kafkacat -b localhost:9092 -t mysql_jdbc_order_items -C -J -u -q | jq '.'
```
