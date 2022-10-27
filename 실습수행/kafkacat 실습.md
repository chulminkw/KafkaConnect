# kafkacat 실습

- kafkacat 설치

```sql
sudo apt-get install kafkacat
```

- -L 옵션으로 전체 토픽에 대한 메타 정보 확인

```sql
kafkacat -b localhost:9092 -L
```

- 특정 토픽의 메시지 읽어오기(키값은 나오지 않음)

```sql
kafkacat -b localhost:9092 -t spooldir-testing-topic
```

- -C 옵션부여하여 명확하게 Consumer 모드로 Topic의 메시지 읽어오기

```sql
kafkacat -b localhost:9092 -t spooldir-testing-topic -C
```

- 특정 토픽의 메시지를 읽어오되 키(Key)값도 함께 표시(키 seperator는 #)

```sql
kafkacat -b localhost:9092 -t spooldir-testing-topic -C -K#
```

- 특정 토픽의 메시지를 읽어오되 json 포맷으로 출력(key, value값 자동 출력됨)

```sql
kafkacat -b localhost:9092 -t spooldir-testing-topic -C -J | jq .
```

- 내부 토픽인 connect-offsets 토픽 읽기

```sql
kafkacat -b localhost:9092 -t connect-offsets -C -K#
```

- 내부 토픽 connect-offsets 의 특정 파티션의 메시지 읽기

```sql
kafkacat -b localhost:9092 -t connect-offsets -C -p 17 -K#
```

- 토픽 메시지를 특정 포맷으로 출력하기

```sql
kafkacat -b localhost:9092 -t connect-offsets -C -f '\nKey (%K bytes): %k\nValue (%S bytes): %s\nPartition: %p\nOffset: %o\n\n'
```

- kafkacat 테스트용 샘플 토픽 생성

```sql
kafka-topics --bootstrap-server localhost:9092 --create --topic kcat-test-topic --partitions 3
```

- Producer 모드로 메시지 전송 후 메시지 확인

```sql
kafkacat -b localhost:9092 -t kcat-test-topic -P -K#
kafkacat -b localhost:9092 -t kcat-test-topic -C -K#
```

- offset Reset을 적용. 대상 connector에 해당하는 key값의 value에 Null을 적용. 최종 메시지가 있는 partition을 찾아서 해당 partition에 Null 메시지를 적용해야 함

```sql
echo '["csv_spooldir_source",{"fileName":"csv-spooldir-source.csv"}]#' | \
    kafkacat -b localhost:9092 -t connect-offsets -P -Z -K# -p 17
```
