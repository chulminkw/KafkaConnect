## Spool Dir Source Connectors를 Connect에 신규 생성
 
특정 디렉토리에 CSV/TSV 등의 형태로 만들어진 파일들을 Kafka broker로 전송하는 Spool Dir Source Connector를 생성  
 
## 수행 순서
**- Confluent Hub에서 Spool Dir Source Connector zip 파일을 다운로드 받음**
https://www.confluent.io/hub/jcustenborder/kafka-connect-spooldir 

**- 다운로드 받은 Connector zip 파일을 실습 VM의 홈 디렉토리에 이동 후 압축 해제하고 lib 디렉토리명을 spooldir_source로 지정하고 ~/connector_plugins 디렉토리 밑의 서브 디렉토리로 복사**

**- Connect 재 기동 필요. 기존 Connect Worker 프로세스를 죽이고 다시 connect_start.sh로 기동**

**- 재 기동 후 아래 curl 명령어로 Connector가 제대로 Connect로 로딩 되었는지 확인**

```js
curl –X GET –H “Content-Type: application/json” http://localhost:8083/connector-plugins
```` 


