# Debezium CDC Source Connector 실습 - MySQL

### Debezium MySQL Connector Plugin을 Connect에 설치하기

- connector hub에서 Debezium mysql source connector를 검색하여 찾고 아래에서 다운로드하여 local PC에 저장.

[Debezium MySQL CDC Source Connector](https://www.confluent.io/hub/debezium/debezium-connector-mysql)

- 압축 파일을 실습 VM에 올리고 압축 해제
- lib 디렉토리에 jar 파일 있는것을 확인하고 lib 디렉토리를 cdc_source_connector로 이름을 변경한 뒤 plugin.path 디렉토리로 이전

```bash
unzip debezium-debezium-connector-mysql-1.9.6.zip
cd debezium-debezium-connector-mysql-1.9.6
mv lib cdc_source_connector
cp -r cdc_source_connector ~/connector_plugins
```

- Connect를 재 기동하고 아래 명령어로 debezium connector plugin이 로딩되었는지 확인

```bash
http GET http://localhost:8083/connector-plugins | jq '.[].class'
```

### CDC Source Connector 수행을 위한 DB Replication 권한 생성 및 테스트 DB 생성

- mysql -u root -p 로 root 사용자로 mysql 접속 후 oc 데이터베이스 생성하고 connect_dev 사용자에게 접근 권한 부여

```sql

create database oc;
show databases;
# 데이터베이스 사용권한 부여
grant all privileges on oc.* to 'connect_dev'@'%' with grant option;

flush privileges;
```

- 반드시 connect_dev 사용자에게 아래 권한을 부여해야 함.

```sql
grant SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'connect_dev' with grant option;
--grant SUPER, REPLICATION CLIENT, REPLICATION SLAVE, RELOAD on *.* to 'connect_dev'@'%' with grant option;
grant all privileges on information_schema.* to 'connect_dev'@'%' with grant option;
grant all privileges on performance_schema.* to 'connect_dev'@'%' with grant option;

flush 
```

- 또는 아래와 같이 모든 권한을 connect_dev 사용자에게 부여

```sql
grant all privileges on *.* to 'connect_dev'@'%' with grant option;
```

- mysql -u connect_dev -p 로 connect_dev 사용자로 접속 후 아래 DDL로 테스트용 테이블을 생성.

```sql
use oc;

drop table if exists customers;
drop table if exists products;
drop table if exists orders;
drop table if exists order_items;

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
	unit_price numeric NULL
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
	unit_price numeric(10, 2) NOT NULL,
	quantity int NOT NULL,
	primary key (order_id, line_item_id)
) ENGINE=InnoDB;

select * from customers;
select * from products;
select * from orders;
select * from order_items;
```

### CDC Source Connector 생성해보기 - 01

- oc 데이터베이스의 모든 테이블들에 대한 변경 데이터를 가져오는 Source Connector 생성
- MySQL 기동을 확인 후에 아래와 같은 설정을 mysql_cdc_oc_source_00.json에 저장

```json
{
    "name": "mysql_cdc_oc_source_test",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "192.168.56.101",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "10000",
        "database.server.name": "test01",
        "database.include.list": "oc",
        "database.allowPublicKeyRetrieval": "true",
        "database.history.kafka.bootstrap.servers": "192.168.56.101:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- 해당 설정을 Connect로 등록하여 신규 connector 생성.

```sql
http POST http://localhost:8083/connectors @mysql_cdc_oc_source_00.json
```

- 데이터를 customers 테이블에 입력한 뒤 토픽과 메시지 생성 확인

```sql
use oc;

insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01');
insert into orders values(1, now(), 1, 'delivered', 1);
insert into products values(1, 'testproduct', 'testcategory', 100);
insert into order_items values(1, 1, 1, 100, 1);
```

- 토픽 메시지 확인

```sql
kafkacat -b localhost:9092 -t dbserver1.oc.customers -C -J -e|jq '.'
# 또는 
kafka-console-consumer --bootstrap-server localhost:9092 --topic dbserver1.oc.customers --from-beginning --property print.key=true| jq '.'
```

### JDBC Sink Connector로 데이터 동기화 실습

- mysql -u root -p 로 접속하여 oc_sink DB 생성하고 connect_dev 사용자에게 권한 부여.

```sql
create database oc_sink;
grant all privileges on oc_sink.* to 'connect_dev'@'%' with grant option;
```

- 아래 script를 수행하여 oc_sink 디비에 새로운 테이블들을 생성.

```sql
use oc_sink;

drop table if exists customers_sink;
drop table if exists products_sink;
drop table if exists orders_sink;
drop table if exists order_items_sink;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_sink (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB ;

CREATE TABLE products_sink (
	product_id int NOT NULL PRIMARY KEY,
	product_name varchar(100) NULL,
	product_category varchar(200) NULL,
	unit_price numeric NULL
) ENGINE=InnoDB ;

CREATE TABLE orders_sink (
	order_id int NOT NULL PRIMARY KEY,
	order_datetime timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ENGINE=InnoDB ;

CREATE TABLE order_items_sink (
	order_id int NOT NULL,
	line_item_id int NOT NULL,
	product_id int NOT NULL,
	unit_price numeric(10, 2) NOT NULL,
	quantity int NOT NULL,
	primary key (order_id, line_item_id)
) ENGINE=InnoDB;

select * from customers_sink;
select * from products_sink;
select * from orders_sink;
select * from order_items_sink;
```

- mysql_jdbc_oc_sink_customers_00.json 파일로 아래 설정을 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_customers_00",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "dbserver1.oc.customers",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "customers_sink",
        "insert.mode": "upsert",
        "pk.fields": "customer_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- 새로운 Connector로 생성 등록

```sql
http POST http://localhost:8083/connectors @mysql_jdbc_oc_sink_customers_00.json
```

### CDC Source Connector의 메시지 생성 시 K

```sql
DELIMITER $$

DROP PROCEDURE IF EXISTS oc.CONNECT_INSERT_TEST$$

create procedure CONNECT_INSERT_TEST(
	repeat_cnt INTEGER
)
BEGIN
	DECLARE customer_idx INTEGER;
	DECLARE product_idx INTEGER;
  DECLARE product_idx_start INTEGER;
  DECLARE order_idx INTEGER;
  DECLARE line_item_idx INTEGER;
  DECLARE iter_idx_01 INTEGER;
  DECLARE iter_idx_02 INTEGER;

  select ifnull(max(customer_id), 0)+1 INTO customer_idx from oc.customers;
	select ifnull(max(order_id), 0) + 1 INTO order_idx from oc.orders;
  select ifnull(max(product_id), 0) + 1 INTO product_idx_start from oc.products;

  SET iter_idx_01 = 1;
  SET iter_idx_02 = 1; 
  SET product_idx = product_idx_start; 
  
  WHILE iter_idx_01 <= repeat_cnt/10 DO
    SET product_idx = product_idx + iter_idx_01;
    
    insert into oc.products values (product_idx, concat('testproduct_', product_idx),
                                    concat('testcategory_', product_idx), 100*iter_idx_01); 
  END WHILE;

	WHILE iter_idx_02 <= repeat_cnt DO
    SET customer_idx = customer_idx + iter_idx_02;
    SET order_idx = order_idx + iter_idx_02;
    
    insert into oc.customers values (customer_idx, concat('testuser_', 
                     customer_idx),  concat('testuser_', customer_idx));
    insert into oc.orders values (order_idx, now(), customer_idx, 'delivered', 1);
    
    SET product_idx =  product_idx_start + mod(iter_idx_02, 10);  
    insert into oc.order_items values (order_idx, product_idx, product_idx, 100* iter_idx_02/10, 1); 
    
    SET iter_idx_02 = iter_idx_02 + 1;
  END WHILE;
END$$

DELIMITER ;
```

```sql
DELIMITER $$

DROP PROCEDURE IF EXISTS oc.CONNECT_INSERT_TEST$$

create procedure CONNECT_INSERT_TEST(
	repeat_cnt INTEGER
)
BEGIN
	DECLARE customer_idx INTEGER;
	DECLARE product_idx INTEGER;
  DECLARE product_idx_start INTEGER;
  DECLARE order_idx INTEGER;
  DECLARE line_item_idx INTEGER;
  DECLARE iter_idx_01 INTEGER;
  DECLARE iter_idx_02 INTEGER;

  select ifnull(max(customer_id), 0)+1 INTO customer_idx from oc.customers;
	select ifnull(max(order_id), 0) + 1 INTO order_idx from oc.orders;

  SET iter_idx_02 = 1; 

 
	WHILE iter_idx_02 <= repeat_cnt DO
    SET customer_idx = customer_idx + iter_idx_02;
    SET order_idx = order_idx + iter_idx_02;
    
    insert into oc.customers values (customer_idx, concat('testuser_', 
                     customer_idx),  concat('testuser_', customer_idx));
    insert into oc.orders values (order_idx, now(), customer_idx, 'delivered', 1);
    
    
    insert into oc.order_items values (order_idx, mod(iter_idx_02, 10), mod(iter_idx_02, 10), 100* iter_idx_02/10, 1); 
    
    SET iter_idx_02 = iter_idx_02 + 1;
  END WHILE;
END$$

DELIMITER ;
```

```sql
use oc;

DELIMITER $$

DROP PROCEDURE IF EXISTS oc.CONNECT_DML_TEST$$

create procedure CONNECT_DML_TEST(
  max_customer_id INTEGER,
  max_order_id INTEGER,
	repeat_cnt INTEGER,
  upd_mod INTEGER
)
BEGIN
	DECLARE customer_idx INTEGER;
	DECLARE product_idx INTEGER;
  DECLARE product_idx_start INTEGER;
  DECLARE order_idx INTEGER;
  DECLARE line_item_idx INTEGER;
  DECLARE iter_idx INTEGER;
  
  SET iter_idx = 1; 

	WHILE iter_idx <= repeat_cnt DO
    SET customer_idx = max_customer_id + iter_idx;
    SET order_idx = max_order_id + iter_idx;
    
    insert into oc.customers values (customer_idx, concat('testuser_', 
                     customer_idx),  concat('testuser_', customer_idx));
    
    insert into oc.orders values (order_idx, now(), customer_idx, 'delivered', 1);
       
    insert into oc.order_items values (order_idx, mod(iter_idx, 10), mod(iter_idx, 10), 100* iter_idx/10, 1); 
    
		if mod(iter_idx, upd_mod) = 0 then
       update oc.customers set full_name = concat('updateduser_', customer_idx) where customer_id = customer_idx;
       update oc.orders set  order_status = 'updated' where order_id = order_idx;
       update oc.order_items set quantity = 2 where order_id = order_idx;
    end if;
   
    SET iter_idx = iter_idx + 1;
  END WHILE;
END$$

DELIMITER ;
```

```sql
truncate table oc.customers;
truncate table oc.orders;
truncate table oc.order_items;

truncate table oc_sink.customers_sink;
truncate table oc_sink.orders_sink;
truncate table oc_sink.order_items_sink;
```

```sql
call CONNECT_DML_TEST(0, 0, 50, 10);
```

```sql
call CONNECT_DML_TEST(50, 50, 100, 5);
```