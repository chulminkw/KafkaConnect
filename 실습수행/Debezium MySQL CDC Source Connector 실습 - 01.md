# Debezium MySQL CDC Source Connector 실습 - 01

### Debezium MySQL Connector Plugin을 Connect에 설치하기

- Debezium 사이트에서 Debezium mysql source connecto 1.9.7 버전 Download를 검색하여 다운로드로 local PC에 저장.

[Debezium Release Series 1.9](https://debezium.io/releases/1.9/)

- 압축 파일을 실습 VM에 올리고 압축 해제
- plug.path 디렉토리 밑에 cdc_source_connector로 서브 디렉토리 생성하고 압축 해제한 jar 파일을 해당 디렉토리로 복사

```bash
tar -xvf debezium-connector-mysql-1.9.7.Final-plugin.tar.gz
cd ~/connector_plugins
mkdir cdc_source_connector
cd ~/debezium-connector-mysql
cp *.jar ../connector_plugins/cdc_source_connector 
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
--grant SUPER, REPLICATION CLIENT, REPLICATION SLAVE, RELOAD on *.* to 'connect_dev'@'%' with grant option;

grant SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'connect_dev'@'%' with grant option;

flush privileges;
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

select * from customers;
select * from products;
select * from orders;
select * from order_items;
```

### MySQL의 복제 환경 확인

- root로 로그인하여 현재 복제하는 binlog 정보 확인

```sql
show master status;

SELECT variable_value as "BINARY LOGGING STATUS (log-bin) ::"
FROM performance_schema.global_variables WHERE variable_name='log_bin';

show variables like '%log_bin%';
```

- 만약 binlog 복제 설정이 되어 있지 않으면 /etc/mysql/mysql.conf.d/mysqld.cnf 파일에 아래 설정을 추가하고 mysql 재 기동

```sql
server-id         = 223344
log_bin           = binlog
binlog_format     = ROW
binlog_row_image  = FULL
expire_logs_days  = 0
```

- binlog 관련 정보 확인

```sql
show variables like "%binlog_%";
show variables like '%expire_logs%';
```

- binlog가 쌓이는 디렉토리 확인. os에서 root 사용자로 로그인 한뒤 /var/lib/mysql 디렉토리에서 binlog 확인

### CDC Source Connector 생성해보기 - ExtractNewRecordState SMT 적용 없이 생성

- oc 데이터베이스의 모든 테이블들에 대한 변경 데이터를 가져오는 Source Connector 생성
- MySQL 기동을 확인 후에 아래와 같은 설정을 mysql_cdc_oc_source_test01.json에 저장

```json
{
    "name": "mysql_cdc_oc_source_test01",
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

- 신규 데이터를 customers 테이블에 입력

```sql
use oc;

insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01');
insert into customers values (2, 'testaddress_02@testdomain', 'testuser_02');
insert into orders values(1, now(), 1, 'delivered', 1);
insert into products values(1, 'testproduct', 'testcategory', 100);
insert into order_items values(1, 1, 1, 100, 1);

update customers set full_name='updateduser_01' where customer_id = 2;

delete from customers where customer_id = 2;
```

- 토픽 메시지 확인

```sql
kafkacat -b localhost:9092 -t test01.oc.customers -C -J -u -q | jq '.'
# 또는 
show_topic_messages json test01.oc.customers
```

- 데이터를 추가로 입력하고 토픽 메시지 확인

```sql
use oc;

insert into customers values (3, 'testaddress_01@testdomain', 'testuser_01');
insert into customers values (4, 'testaddress_02@testdomain', 'testuser_02');
```

### JDBC Sink Connector로 데이터 동기화 실습 - Source에서 ExtractNewRecordState SMT 적용 없는 메시지

- Debezium Source Connector의 메시지를 그대로 생성하면 JDBC Sink Connector는 해당 포맷을 해석할 수 없으므로 데이터 입력처리 불가
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
	unit_price decimal(10, 0) NULL
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
	unit_price decimal(10, 2) NOT NULL,
	quantity int NOT NULL,
	primary key (order_id, line_item_id)
) ENGINE=InnoDB;

select * from customers_sink;
select * from products_sink;
select * from orders_sink;
select * from order_items_sink;
```

- mysql_cdc_oc_sink_test01.json 파일로 아래 설정을 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_customers_test01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "test01.oc.customers",
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

- 새로운 Connector로 생성 등록

```sql
register_connector mysql_cdc_oc_sink_test01.json.json
```

- **connect console에서 로그 메시지를 확인하면 Sink Connector가 수행되지 않고 오류가 발생함을 확인**

### Source에서 ExtractNewRecordState SMT 적용하여 After 메시지만 생성.

- ExtractNewRecordStateSMT를 적용하여 환경설정. 아래 내용을 mysql_cdc_oc_source_01.json 파일에 저장

```json
{
    "name": "mysql_cdc_oc_source_01",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "10001",
        "database.server.name": "mysql01",
        "database.include.list": "oc",
        "table.include.list": "oc.customers, oc.products, oc.orders, oc.order_items", 
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

- 해당 설정을 Connect로 등록하여 신규 connector 생성.

```sql
register_connector mysql_cdc_oc_source_01.json
```

- 토픽 메시지 확인

```sql
kafkacat -b localhost:9092 -t mysql01.oc.customers -C -J -u -q | jq '.'
# 또는 
show_topic_messages json mysql01.oc.customers
```

- JDBC Sink Connector 신규 생성. 아래 설정을 mysql_jdbc_oc_sink_customers_01.json 파일에 저장

```json
{
    "name": "mysql_jdbc_oc_sink_customers_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql01.oc.customers",
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

- 해당 설정을 Connect로 등록하여 신규 connector 생성.

```sql
register_connector mysql_jdbc_oc_sink_customers_01.json
```

- 소스 테이블의 데이터가 제대로 Sink 되는지 oc_sink 내의 테이블 확인

### Sink Connector 에서 ExtractNewRecordState SMT 적용하여 After 메시지만 변환한 뒤 DB 입력

- Source Connector는 Before/After를 그대로 유지하고 Sink Connector에서 ExtractNewRecordState SMT 적용하여 DB 입력 수행
- 아래 설정을 mysql_jdbc_oc_sink_customers_smt_after_01.json 파일에 저장.

```sql
{
    "name": "mysql_jdbc_oc_sink_customers_smt_after_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "test01.oc.customers",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "customers_sink_smt_after",
        "insert.mode": "upsert",
        "pk.fields": "customer_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter", 
        
        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"

    }
}
```

- oc_sink DB에 별도의 테스트용 테이블을 생성.

```sql
use oc_sink;

drop table if exists customers_sink_smt_after;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers_sink_smt_after (
customer_id int NOT NULL PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL
) ENGINE=InnoDB ;
```

- 해당 설정을 Connect로 등록하여 신규 connector 생성.

```sql
register_connector mysql_jdbc_oc_sink_customers_smt_after_01.json
```

- oc_sink의 customers_sink_smt_after 테이블에 데이터가 입력되었는지 확인.

### connect-offsets 및 __consumer_offsets 메시지 확인

- Source Connector에서 기록한 connect-offset 메시지 확인

```sql
kafkacat -b localhost:9092 -C -t connect-offsets -J -u -q |jq '.'
#또는
show_topic_message.sh json connect-offsets
```

- Sink Connector에서 기록한 __consumer_offsets 메시지 확인

```sql
echo "exclude.internal.topics=false" > /home/min/consumer_temp.config
kafka-console-consumer --consumer.config /home/min/consumer_temp.config  --bootstrap-server localhost:9092 --topic __consumer_offsets  --formatter "kafka.coordinator.group.GroupMetadataManager\$OffsetsMessageFormatter" --from-beginning
```

### products, orders, order_items 테이블용 JDBC Sink Connector 생성

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
        "table.name.format": "products_sink",
        "insert.mode": "upsert",
        "pk.fields": "product_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_orders_01.json으로 저장.

```json
{
    "name": "mysql_jdbc_oc_sink_orders_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysql01.oc.orders",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "orders_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
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
        "table.name.format": "order_items_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id, line_item_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",
        "key.converter": "org.apache.kafka.connect.json.JsonConverter",
        "value.converter": "org.apache.kafka.connect.json.JsonConverter"
    }
}
```

- products_sink, orders_sink, order_items_sink용 JDBC Sink Connector를 생성.

```sql
http POST http://localhost:8083/connectors @mysql_jdbc_oc_sink_products_01.json
http POST http://localhost:8083/connectors @mysql_jdbc_oc_sink_orders_01.json
http POST http://localhost:8083/connectors @mysql_jdbc_oc_sink_order_items_01.json
```

### Debezium Source Connector와 JDBC Sink Connector 연동 테스트

- 기존 Source 테이블에 있는 모든 데이터를 삭제.  연동이 제대로 되어 있으면 Source 테이블에만 delete 적용해도 target 테이블도 같이 적용. 만일 Source 테이블에 Truncate를 적용하였으면 Target쪽에도 수동으로 SQL을 통해 Truncate 적용.
- DML 테스트를 위해 아래의 Procedure를 생성. 아래 Procedure는 repeat_cnt만큼 데이터를 insert 수행.  repeat_cnt 만큼 반복 insert 수행중 upd_mod

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
       
    insert into oc.order_items values (order_idx, mod(iter_idx, upd_mod)+1, mod(iter_idx, upd_mod)+1, 100* iter_idx/upd_mod, 1); 
    
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

- products 테이블을 아래와 같이 수동으로 생성.

```sql
insert into products values(1, 'testproduct_01', 'testcategory_01', 100);
insert into products values(2, 'testproduct_02', 'testcategory_02', 200);
insert into products values(3, 'testproduct_03', 'testcategory_03', 300);
insert into products values(4, 'testproduct_04', 'testcategory_04', 400);
insert into products values(5, 'testproduct_05', 'testcategory_05', 500);
insert into products values(6, 'testproduct_06', 'testcategory_06', 600);
insert into products values(7, 'testproduct_07', 'testcategory_07', 700);
insert into products values(8, 'testproduct_08', 'testcategory_08', 800);
insert into products values(9, 'testproduct_09', 'testcategory_09', 900);
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

```sql
CREATE TABLE orders_test_new (
	order_id int NOT NULL PRIMARY KEY,
	order_datetime timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL
) ENGINE=InnoDB ;
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