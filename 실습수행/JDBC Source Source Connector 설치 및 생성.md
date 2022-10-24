# JDBC Source/Source Connector 설치 및 구성

### JDBC Source/Sink Connector Plugin을 Connect에 설치하기

- JDBC Source/Sink Connector 로컬 PC에 Download

[JDBC Connector (Source and Sink)](https://www.confluent.io/hub/confluentinc/kafka-connect-jdbc)

- MySQL JDBC Driver 로컬 PC에 Download. 오라클 사이트나 maven에서 jar download

[https://mvnrepository.com/artifact/mysql/mysql-connector-java/8.0.30](https://mvnrepository.com/artifact/mysql/mysql-connector-java/8.0.30)

- 로컬 PC에 다운로드 받은 JDBC Connector와 MySQL JDBC Driver를 실습 vm로 옮김
- upload된 JDBC Connector의 압축을 풀고 lib 디렉토리를 jdbc_connector로 이름 변경

```sql
unzip confluentinc-kafka-connect-jdbc-10.6.0.zip
cd confluentinc-kafka-connect-jdbc-10.6.0
mv lib jdbc_connector
```

- jdbc_connector 디렉토리를 plugin.path 디렉토리로 이동

```sql
# ~/confluentinc-kafka-connect-jdbc-10.6.0 디렉토리에 아래 수행.
cp -r jdbc_connector ~/connector_plugins
```

- Connect를 재기동하고 REST API로 해당 plugin class가 제대로 Connect에 로딩 되었는지 확인

```sql
# 아래 명령어는 반드시 Connect를 재 기동후 수행
http http://localhost:8083/connector-plugins
```