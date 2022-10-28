# 특정 Connector의 connect-offsets 리셋하기

- Connector는 소스 데이터를 마지막으로 읽어들인 지점에 대한 offset을 connect-offsets 내부 토픽으로 저장하며 Connector는 주기적으로 소스 데이터를 읽지만, 해당 소스 데이터가 connect-offsets에 저장된 offset 값보다 작은 경우 Kafka로 전송하지 않음.
- 하지만 유지보수 차원에서 Connector의 offset값을 리셋해야 하는 경우가 있음.   mysql_jdbc_om_source_03 Connector의 offset을 리셋 테스트
- connect-offsets 토픽에서 mysql_jdbc_om_source_03 Connector의 offset 정보 추출. 반드시 어떤 파티션에 기록되어 있는지 확인 필요.

```sql
kafkacat -b localhost:9092 -t connect-offsets -C -f '\nKey: %k Value: %s Partition: %p Offset: %o\n\n' | grep "mysql_jdbc_om_source_03"
```

또는 아래와 같이 입력

```sql
kafkacat -b localhost:9092 -t connect-offsets -C -J | grep "mysql_jdbc_om_source_03"
```

- Connector 삭제

```sql
http DELETE http://localhost:8083/connectors/mysql_jdbc_om_source_03
```

- Connect를 내리고 mysql_jdbc_om_source_03 Connector의 connect-offsets key값으로 value값을 null로 설정.

```sql
echo '["mysql_jdbc_om_source_03",{"protocol":"1","table":"om.customers"}]#' | \
    kafkacat -b localhost:9092 -t connect-offsets -P -Z -K# -p 5
```

- Connect를 올리고 Connector를 다시 생성한 후 메시지가 Kafka로 전송되는 지 확인

```sql

kafkacat -b localhost:9092 -t mysql_om_smt_customers -C -K# -e
http POST http://localhost:8083/connectors @mysql_jdbc_om_source_smt.json
```
