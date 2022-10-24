# MySQL 설치 및 환경 구성

### 실습 VM에 MySQL DB 설치 및 테이블 생성

## MySQL 설치

- sudo apt update 로 실습 VM Package update 먼저 적용후 mysql-server 설치

```bash
sudo apt-get update
sudo apt-get install mysql-server
```

- mysql 설치 버전 확인하고 접속 port 오픈

```bash
mysql --version
sudo ufw allow mysql
```

- mysql에 접속하여 mysql root password 변경

```bash
# mysql client 수행하여 접속
sudo mysql
# mysql root 패스워드 변경
mysql> alter user 'root'@'localhost' identified with mysql_native_password by 'mysql';
```

- mysql에 root 사용자로 방금 생성한 패스워드 입력하여 접속 확인

```bash
mysql -u root -p
```

- 필요하다면 시스템 기동시 mysql도 함께 기동 등록

```bash
sudo systemctl enable mysql
```

### MySQL 실습 데이터 구축

- root로 접속하여 새로운 Database로 om 생성

```sql
mysql -u root -p
mysql> create database om;
mysql> show databases;
```

- 새롭게 생성한 om 데이터베이스에 접속하여 실습에 사용할 테이블 생성

```sql
mysql> use om;

-- 아래 Create Table 스크립트수행. customers, products, orders, order_items 테이블 생성
CREATE TABLE customers (
	customer_id int NOT NULL,
	email_address varchar(255) NOT NULL,
	full_name varchar(255) NOT NULL,
	primary key(customer_id)
) ENGINE=InnoDB ;

```