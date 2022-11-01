# Source Connect 환경 재 설정하기

### connect-offsets 토픽을 삭제하여 모든 Source Connector의 connect offset을 Reset하기

- 기존에 등록된 모든 Connector를 모두 삭제하기
- Connect 내리기
- Source Connector로 생성된 모든 토픽 삭제

```bash
kafka-topics --bootstrap-server localhost:9092 --list
kafka-topics --bootstrap-server localhost:9092 --delete --topic topic명
```

- connect-offsets, connect-configs, connect-status 토픽 삭제

```bash
kafka-topics --bootstrap-server localhost:9092 --delete --topic connect-offsets
kafka-topics --bootstrap-server localhost:9092 --delete --topic connect-configs
kafka-topics --bootstrap-server localhost:9092 --delete --topic connect-status
```

- Connect 재기동후 connect-offsets, connect-configs, connect-status가 재 생성되었는지 확인

```bash
connect_start.sh
```

### 신규 Source Connector 환경 파일 만들기

- 아래 규칙대로 Source Connector 환경파일 생성.

| 테이블명 | Json 파일명 | Connector 명 | Topic 명 |
| --- | --- | --- | --- |
| Customers | mysql_jdbc_source_customers.json | mysql_jdbc_source_customers | mysql_jdbc_customers |
| Products | mysql_jdbc_source_products.json | mysql_jdbc_source_products | mysql_jdbc_products |
| Orders | mysql_jdbc_source_orders.json | mysql_jdbc_source_orders | mysql_jdbc_orders |
| Order_items | mysql_jdbc_source_order_items.json | mysql_jdbc_source_order_items | mysql_jdbc_order_items |

 

- 개별 테이블별로 한개의 Source Connector 설정을 담은 json 파일을 다운로드

[https://github.com/chulminkw/KafkaConnect/tree/main/connector-configs/jdbc_source_configs](https://github.com/chulminkw/KafkaConnect/tree/main/connector-configs/jdbc_source_configs) 에서 다운로드 할 수 있음. 

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

### MySQL om 데이터베이스의 테이블 데이터 재입력

- 기존 데이터를 삭제하고 새로운 데이터를 테이블별로 입력

```sql
use om;

-- 테이블 Truncate
truncate table customers;
truncate table products;
truncate table orders;
truncate table order_items;

-- 테이블별 데이터 입력
insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01', now());
insert into customers (email_address, full_name, system_upd) values ('testaddress_02@testdomain', 'testuser_02', now());
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
kafkacat -b localhost:9092 -t mysql_jdbc_customers -C -J -e | grep -v '% Received' | jq '.'
kafkacat -b localhost:9092 -t mysql_jdbc_products -C -J -e | grep -v '% Received' | jq '.'
kafkacat -b localhost:9092 -t mysql_jdbc_orders -C -J -e | grep -v '% Received' | jq '.'
kafkacat -b localhost:9092 -t mysql_jdbc_order_items -C -J -e | grep -v '% Received' | jq '.'
```
