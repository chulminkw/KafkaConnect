# Schema Registry 기반의 Connector 구성 실습

### Schema Registry 실행 스크립트 작성

- schema-registry-start 쉘을 [schema-registry.properties](http://schema-registry.properties) 설정으로 실행

```bash
vi registry_start.sh
$CONFLUENT_HOME/bin/schema-registry-start $CONFLUENT_HOME/etc/schema-registry/schema-registry.properties
```

- registry_start.sh 을 수행하여 schema registry 기동

### MySQL용 Debezium CDC Source Connector를 Schema Registry를 적용하여 생성

- 기존 Source Connector를 모두 삭제
- oc와 oc_sink 주요 테이블의 데이터를 모두 Truncate

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

- mysql_cdc_oc_source_avro_01.json 파일에 아래 설정을 저장. Key와 Value모두 Avro 형태의 Converter를 적용하고, Schema는 Schema Registry에 등록

```json
{
    "name": "mysql_cdc_oc_source_avro_01",
    "config": {
        "connector.class": "io.debezium.connector.mysql.MySqlConnector",
        "tasks.max": "1",
        "database.hostname": "localhost",
        "database.port": "3306",
        "database.user": "connect_dev",
        "database.password": "connect_dev",
        "database.server.id": "20000",
        "database.server.name": "mysqlavro",
        "database.include.list": "oc",
        "table.include.list": "oc.customers, oc.products, oc.orders, oc.order_items, oc.orders_datetime_tab",
        "database.history.kafka.bootstrap.servers": "localhost:9092",
        "database.history.kafka.topic": "schema-changes.mysql.oc",

        "time.precision.mode": "connect",
        "database.connectionTimezone": "Asia/Seoul",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081",

        "transforms": "unwrap",
        "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
        "transforms.unwrap.drop.tombstones": "false"
    }
}
```

- 아래 명령어로 생성한 json 파일을 등록하여 새로운 CDC Connector 생성.

```sql
register_connector mysql_cdc_oc_source_avro_01.json
```

- oc의 주요 테이블에 데이터 확인

```sql
use oc;

insert into customers values (1, 'testaddress_01@testdomain', 'testuser_01');
insert into customers values (2, 'testaddress_02@testdomain', 'testuser_02');
insert into orders values(1, now(), 1, 'delivered', 1);
insert into products values(1, 'testproduct', 'testcategory', 100);
insert into order_items values(1, 1, 1, 100, 1);

update customers set full_name='updateduser_01' where customer_id = 2;

delete from customers where customer_id = 2;

insert into orders_datetime_tab values (1, now(), now(), 1, 'delivered', 1);
```

- customers 토픽에서 메시지 확인

```sql
show_topic_messages avro mysqlavro.oc.customers;
```

### Schema Registry에 등록된 Schema 정보 확인

- Schema Registry에 등록된 모든 Schema 정보 확인

```sql
http GET http://localhost:8081/schemas
```

- Schema Registry에 등록된 모든 subjects 정보 확인. subject명은  key와 value 별로 생성되며 기본적으로 Topic명 + ‘-key’ 또는 ‘-value’ 로 명명됨.

```sql
http GET http://localhost:8081/subjects
```

- 특정 id를 가지는 schema 정보 확인.

```sql
http GET http://localhost:8081/schemas/ids/1
```

- 특정 subject의 버전별 schema 정보 확인.

```sql
http GET http://localhost:8081/subjects/mysqlavro.oc.customers-value/versions/1
```

### JDBC Sink Connector를 Schema Registry를 적용하여 MySQL Target DB에 데이터 입력

- Schema가 없는 데이터를 토픽에서 읽어서  Schema Registry를 통해서 스키마 정보 추출 후 JDBC를 통해 Target DB에 입력할 수 있도록 새로운 Connector 생성
- 아래 설정을 mysql_jdbc_oc_sink_customers_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_customers_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.customers",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.customers_sink",
        "insert.mode": "upsert",
        "pk.fields": "customer_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"

    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_products_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_products_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.products",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.products_sink",
        "insert.mode": "upsert",
        "pk.fields": "product_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"

    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_orders_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_orders_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.orders",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081",

        "db.timezone": "Asia/Seoul",

        "transforms": "convertTS",
        "transforms.convertTS.type": "org.apache.kafka.connect.transforms.TimestampConverter$Value",
        "transforms.convertTS.field": "order_datetime",
        "transforms.convertTS.format": "yyyy-MM-dd'T'HH:mm:ss'Z'",
        "transforms.convertTS.target.type": "Timestamp"

    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_order_items_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_order_items_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.order_items",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.order_items_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id, line_item_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"

    }
}
```

- 아래 설정을 mysql_jdbc_oc_sink_orders_datetime_tab_avro_01.json에 저장

```sql
{
    "name": "mysql_jdbc_oc_sink_orders_datetime_tab_avro_01",
    "config": {
        "connector.class": "io.confluent.connect.jdbc.JdbcSinkConnector",
        "tasks.max": "1",
        "topics": "mysqlavro.oc.orders_datetime_tab",
        "connection.url": "jdbc:mysql://localhost:3306/oc_sink",
        "connection.user": "connect_dev",
        "connection.password": "connect_dev",
        "table.name.format": "oc_sink.orders_datetime_tab_sink",
        "insert.mode": "upsert",
        "pk.fields": "order_id",
        "pk.mode": "record_key",
        "delete.enabled": "true",

        "key.converter": "io.confluent.connect.avro.AvroConverter",
        "value.converter": "io.confluent.connect.avro.AvroConverter",
        "key.converter.schema.registry.url": "http://localhost:8081",
        "value.converter.schema.registry.url": "http://localhost:8081"

    }
}
```

- 위에서 설정한 Connector를 모두 생성.

```sql
register_connector mysql_jdbc_oc_sink_customers_avro_01.json
register_connector mysql_jdbc_oc_sink_products_avro_01.json
register_connector mysql_jdbc_oc_sink_orders_avro_01.json
register_connector mysql_jdbc_oc_sink_order_items_avro_01.json
register_connector mysql_jdbc_oc_sink_orders_datetime_tab_avro_01.json
```

- Source 테이블의 변경 사항이 Sink 테이블로 반영 되었는지 확인.