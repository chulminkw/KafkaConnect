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

### 신규 Source Connector 생성

- mysql의 om database에 있는 개별 테이블당 하나의 Source Connector를 생성. 모든 Source Connector는 key를 가질 수 있도록 SMT 변환