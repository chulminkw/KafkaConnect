# JDBC Sink Connector 실습

### Mysql에 om_sink database 생성

- mysql -u root -p 로 mysql 접속 후 om_sink db 생성하고 connect_dev 사용자에게 권한 부여

```sql
create database om_sink;

grant all privileges on om_sink.* to 'connect_dev'@'%' with grant option;
```

- 아래 SQL로 Sink 대상이 되는 테이블 생성.

```sql
use om_sink;

drop table if exists customers_sink;
drop table if exists products_sink;
drop table if exists orders_sink;
drop table if exists order_items_sink;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_sink (
customer_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL,
system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_customers_sink_001 on customers_sink(system_upd);

CREATE TABLE products_sink (
	product_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
	product_name varchar(100) NULL,
	product_category varchar(200) NULL,
	unit_price decimal(10, 0) NULL,
  system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_products_sink_001 on products_sink(system_upd);

CREATE TABLE orders_sink (
	order_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
	order_datetime timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL,
	system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_orders_sink_001 on orders_sink(system_upd);

CREATE TABLE order_items_sink (
	order_id int NOT NULL,
	line_item_id int NOT NULL,
	product_id int NOT NULL,
	unit_price decimal(10, 2) NOT NULL,
	quantity int NOT NULL,
  system_upd timestamp NOT NULL,
	primary key (order_id, line_item_id)
) ENGINE=InnoDB;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_order_items_sink_001 on order_items_sink(system_upd);

select * from customers_sink;
select * from products_sink;
select * from orders_sink;
select * from order_items_sink;
```

### JDBC Sink Connector Plug in 확인

```sql
http GET http://localhost:8083/connector-plugins | jq '.[].class'
```

### REST API 및 토픽 메시지 읽기 관련 유틸리티 쉘 스크립트 생성

- [https://github.com/chulminkw/KafkaConnect/tree/main/scripts](https://github.com/chulminkw/KafkaConnect/tree/main/scripts) 에 있는 show_connectors, register_connector, delete_connector, show_topic_messages 쉘 스크립트를 /home/min 디렉토리로 복사

### JDBC Sink Connector 생성하여 Key값을 가지는 Customers 토픽에서 테이블로 데이터 Sink

 

- Mysql의 om 데이터베이스의 customers 테이블의 데이터를 om_sink 데이터베이스로 입력하는 JDBC Sink Connector 생성
- 아래 설정을 mysql_jdbc_sink_00.json으로 생성(topics에 새로운 topic 명을 주면 그대로 새로운 topic을 생성함)

```json
{
    "name": "mysql_jdbc_sink_customers_00",
    "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql_jdbc_customers",
        "connection.url": "jdbc:mysql://localhost:3306/om_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",

        "insert.mode": "upsert",
        "pk.mode": "record_key",
        "pk.fields": "customer_id",
        "delete.enabled": "true",
        
        "table.name.format": "om_sink.customers_sink_base",
        
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter",
        "auto.create": "true"
    }
}
```

- 새로운 sink connector 생성

```sql
register_connector mysql_jdbc_sink_00.json 
```

- om_sink db에서 customers_sink_base 테이블의 데이터 입력 확인
- mysql_jdbc_customers 토픽의 메시지 확인

```bash
kafkacat -b localhost:9092 -t mysql_jdbc_customers -C -J -u -q | jq '.'
#또는
show_topic_messages mysql_jdbc_customers
```

- auto.create로 테이블을 자동 생성하는 것은 바람직하지 않음. 테이블 관리를 위해서라도 DB에서 테이블을 먼저 생성한 뒤에 토픽에서 DB 테이블로 Sink 권장
- 기존 mysql_jdbc_sink_customers_00 Connector 삭제

```sql
delete_connector mysql_jdbc_sink_customers_00
```

- 아래 설정을 mysql_jdbc_sink_customers.json으로 만들고 Connect에 신규 Connector로 생성.

```json
{
    "name": "mysql_jdbc_sink_customers",
    "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql_jdbc_customers",
        "connection.url": "jdbc:mysql://localhost:3306/om_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        
        "insert.mode": "upsert",
        "pk.mode": "record_key",
        "pk.fields": "customer_id",
        "delete.enabled": "true",

        "table.name.format": "om_sink.customers_sink",
        
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- sink connector 등록

```sql
register_connector mysql_jdbc_sink_customers.json 
```

- 신규 Connector 생성 후 om_sink DB의 customers_sink 테이블에서 데이터 입력 확인

### PK컬럼이 여러개인 테이블에 대한 Sink Connector 생성

- order_id, line_item_id를 PK로 가지는 order_items_sink 테이블에 데이터 입력
- 아래 설정을 mysql_jdbc_sink_order_items.json 파일에 저장

```json
{
    "name": "mysql_jdbc_sink_order_items",
    "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql_jdbc_order_items",
        "connection.url": "jdbc:mysql://localhost:3306/om_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "insert.mode": "upsert",
        "pk.mode": "record_key",
        "pk.fields": "order_id, line_item_id",
        "delete.enabled": "true",
        "table.name.format": "om_sink.order_items_sink",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- order_items_sink 테이블용 신규 Sink Connector 생성

```sql
register_connector mysql_jdbc_sink_order_items.json
```

### Source 테이블과 연계하여 Sink 테이블에 데이터 연동 테스트

- 다른 테이블에 대해서도 Sink Connector를 생성하고 Source 테이블에 데이터 입력하여 Sink(Target) 테이블에 데이터가 동기화 되는지 확인.
- products_sink용 sink connector를 위해서 아래 설정을 mysql_jdbc_sink_products.json 파일에 저장.

```json
{
    "name": "mysql_jdbc_sink_products",
    "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql_jdbc_products",
        "connection.url": "jdbc:mysql://localhost:3306/om_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "insert.mode": "upsert",
        "pk.mode": "record_key",
        "pk.fields": "product_id",
        "delete.enabled": "true",
        "table.name.format": "om_sink.products_sink",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- orders_sink용 sink connector를 위해서 아래 설정을 mysql_jdbc_sink_orders.json 파일에 저장.

```json
{
    "name": "mysql_jdbc_sink_orders",
    "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql_jdbc_orders",
        "connection.url": "jdbc:mysql://localhost:3306/om_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "insert.mode": "upsert",
        "pk.mode": "record_key",
        "pk.fields": "order_id",
        "delete.enabled": "true",
        "table.name.format": "om_sink.orders_sink",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- orders와 products 관련 sink connector 생성 등록

```sql
register_connector mysql_jdbc_sink_products.json
register_connector mysql_jdbc_sink_orders.json

```

- om 데이터베이스의 테이블들에 데이터 insert 후 om_sink 데이터베이스의 테이블들에 동기화 입력 되는지 확인

```sql
use om;

-- customers 테이블에 데이터 입력
insert into customers (email_address, full_name, system_upd) 
  values ('testaddress_03@testdomain', 'testuser_03', now());
insert into customers (email_address, full_name, system_upd) 
  values ('testaddress_04@testdomain', 'testuser_04', now());

-- products 테이블에 데이터 입력
insert into products (product_name, product_category, unit_price, system_upd)
  values ('test_products_02', 'test_category', 200, now());
insert into products (product_name, product_category, unit_price, system_upd)
  values ('test_products_03', 'test_category', 300, now());

-- orders 테이블에 데이터 입력
insert into orders (order_datetime, customer_id, order_status, store_id, system_upd)
  values (now(), 1, 'delivered', 1, now());
insert into orders (order_datetime, customer_id, order_status, store_id, system_upd)
  values (now(), 2, 'delivered', 2, now());

-- order_items 테이블에 데이터 입력
insert into order_items(order_id, line_item_id, product_id, unit_price, quantity, system_upd)
  values (2, 1, 2, 200, 1, now());
insert into order_items (order_id, line_item_id, product_id, unit_price, quantity, system_upd)
  values (2, 2, 3, 300, 1, now());
insert into order_items (order_id, line_item_id, product_id, unit_price, quantity, system_upd)
  values (3, 1, 1, 100, 1, now());
```

### 레코드 업데이트 테스트

- 소스 DB(om)에서 customers테이블의 customer_id = 1인 레코드의  full_name을 updated_name으로 변경

```sql
use om;

update customers set full_name='updated_name', system_upd=now() where customer_id=1;
```

- 변경 후 sink DB에서 해당 레코드가 성공적으로 Update 되었는지 확인

```sql
use om_sink;

select * from customers_sink;
```

- mysql_jdbc_source_customers 토픽의 메시지 내용 확인

```bash
show_topic_messages json mysql_jdbc_customers
```

- 다른 테이블도 Update 테스트 수행후 Sink DB에서 성공적으로 Update 되었는지 확인

```sql
use om;

update products set product_category='updated_category', system_upd=now() where product_id = 2;

update orders set order_status='updated', system_upd=now() where order_id = 2;

update order_items set quantity=2, system_upd=now() where order_id = 2;
```

### 레코드 삭제 테스트

- Topic 메시지의 Key값에 해당하는 Value가 Null이면 Sink Connector는 Key값에 해당하는 PK가 가리키는 레코드를 삭제함.
- JDBC Source Connector는 Delete 메시지를 보낼 수 없으므로 kafkacat으로 Delete 메시지를 시뮬레이션 하기 위해 특정 key값을 가지는 메시지의 value를 Null로 만듬.
- 기존 mysql_jdbc_source_customers Connector와 mysql_jdbc_sink_customers Connector를 정지

```sql
http PUT http://localhost:8083/connectors/mysql_jdbc_source_customers/pause
http PUT http://localhost:8083/connectors/mysql_jdbc_sink_customers/pause

http GET http://localhost:8083/connectors/mysql_jdbc_source_customers/status
http GET http://localhost:8083/connectors/mysql_jdbc_sink_customers/status
```

- mysql_jdbc_customers토픽에서 customer_id=3인 데이터의 Key값을 찾아서 해당 Key값으로 Value를 Null로 설정.

```bash
kafkacat -b localhost:9092 -t mysql_jdbc_customers -C -J -u -q | jq '.'
echo '{"schema":{"type":"int32","optional":false},"payload":3}#' | kafkacat -b localhost:9092 -P -t mysql_jdbc_customers -Z -K#
```

- mysql_jdbc_source_customers Connector와 mysql_jdbc_sink_customers Connector를 재기동

```sql
http PUT http://localhost:8083/connectors/mysql_jdbc_source_customers/resume
http PUT http://localhost:8083/connectors/mysql_jdbc_sink_customers/resume

http GET http://localhost:8083/connectors/mysql_jdbc_source_customers/status
http GET http://localhost:8083/connectors/mysql_jdbc_sink_customers/status
```

- mysql에 접속하여 om_sink 의 customers_sink 테이블의 customer_id=3이 삭제되었는지 확인
- 데이터 동기화를 위해 om DB의 customers 테이블의 customer_id=3을 강제 삭제

### JDBC Source Connector의 date, datetime, timestamp 관련 데이터 변환 및 Sink Connector 입력

- date와 datetime 컬럼 타입을 테스트해보기 위해 orders_datetime_tab 테이블을 oc DB에 생성

```sql
use om;

drop table if exists datetime_tab;

CREATE TABLE datetime_tab (
  id int NOT NULL PRIMARY KEY,
  order_date date NOT NULL,
  order_datetime datetime NOT NULL,
  order_timestamp timestamp NOT NULL,
  system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

insert into datetime_tab values (1, now(), now(), now(), now());
```

- oc_sink db에 orders_datetime_tab_sink 테이블 생성

```sql
use om_sink;

drop table if exists datetime_tab_sink;

CREATE TABLE datetime_tab_sink (
  id int NOT NULL PRIMARY KEY,
  order_date date NOT NULL,
  order_datetime datetime NOT NULL,
  order_timestamp timestamp NOT NULL,
  system_upd timestamp NOT NULL
) ENGINE=InnoDB ;
```

- datetime_tab 테이블을 위한 source connector 설정을 mysql_jdbc_source_datetime_tab.json 파일에 저장.

```json
{
    "name": "mysql_jdbc_om_source_datetime_tab",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSourceConnector",
        "tasks.max": "1",
        "connection.url": "jdbc:mysql://localhost:3306/om",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "topic.prefix": "mysql_jdbc_",
        "table.whitelist": "om.datetime_tab",
        "poll.interval.ms": 10000,
        "mode": "timestamp",
        "timestamp.column.name": "system_upd",
        "transforms": "create_key, extract_key",
        "transforms.create_key.type": "org.apache.kafka.connect.transforms.ValueToKey",
        "transforms.create_key.fields": "id",
        "transforms.extract_key.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
        "transforms.extract_key.field": "id"
    }
}
```

- source connector 생성 등록

```shell
register_connector mysql_jdbc_source_datetime_tab.json
```

- 토픽 메시지 확인

```shell
show_topic_messages json mysql_jdbc_datetime_tab
```

- mysql_jdbc_sink_datetime_tab.json에 sink connector 생성

```json
{
    "name": "mysql_jdbc_sink_datetime_tab",
    "config": {
        "connector.class":"io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql_jdbc_datetime_tab",
        "connection.url": "jdbc:mysql://localhost:3306/om_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "insert.mode": "upsert",
        "pk.mode": "record_key",
        "pk.fields": "id",
        "delete.enabled": "true",
        "table.name.format": "om_sink.datetime_tab_sink",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- sink connector 등록

```shell
register_connector mysql_jdbc_sink_datetime_tab.json
```

- om_sink.datetime_tab_sink 테이블에 데이터가 연동되는지 확인
