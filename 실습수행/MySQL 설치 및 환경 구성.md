# MySQL 설치 및 환경 구성

### 실습 VM에 MySQL DB 설치 및 테이블 생성

## MySQL 설치

- sudo apt update 로 실습 VM Package update 먼저 적용후 mysql 설치

```bash
sudo apt-get update && sudo apt-get upgrade
sudo apt-get install mysql-server mysql-client
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
create user 'root'@'%' identified with mysql_native_password by 'root';
grant all privileges on *.* to 'root'@'%' with grant option;
flush privileges;
```

- mysql에 root 사용자로 방금 생성한 패스워드 입력하여 접속 확인

```bash
sudo mysql -u root -p
```

- 필요하다면 시스템 기동시 mysql도 함께 기동 등록

```bash
sudo systemctl enable mysql
```

### MySQL 실습 데이터 구축

- root로 접속하여 새로운 Database로 om 생성

```sql
sudo mysql -u root -p
mysql> create database om;
mysql> show databases;
```

- mysql에서 새로운 사용자 connect_dev 추가하고 om DB 사용 권한 할당

```sql
create user 'connect_dev'@'%' identified by 'connect_dev';
# 데이터베이스 사용권한 부여
grant all privileges on om.* to 'connect_dev'@'%' with grant option;

flush privileges;
```

- connect_dev 사용자로 mysql 접속

```sql
mysql -u connect_dev -p 
```

- om 데이터베이스에 접속하여 실습에 사용할 테이블 생성

```sql
use om;

-- 아래 Create Table 스크립트수행.
CREATE TABLE customers (
customer_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
email_address varchar(255) NOT NULL,
full_name varchar(255) NOT NULL,
system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_customers_001 on customers(system_upd);

CREATE TABLE products (
	product_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
	product_name varchar(100) NULL,
	product_category varchar(200) NULL,
	unit_price numeric NULL,
  system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_products_001 on products(system_upd);

CREATE TABLE orders (
	order_id int NOT NULL AUTO_INCREMENT PRIMARY KEY,
	order_datetime timestamp NOT NULL,
	customer_id int NOT NULL,
	order_status varchar(10) NOT NULL,
	store_id int NOT NULL,
	system_upd timestamp NOT NULL
) ENGINE=InnoDB ;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_orders_001 on orders(system_upd);

CREATE TABLE order_items (
	order_id int NOT NULL,
	line_item_id int NOT NULL,
	product_id int NOT NULL,
	unit_price numeric(10, 2) NOT NULL,
	quantity int NOT NULL,
  system_upd timestamp NOT NULL,
	primary key (order_id, line_item_id)
) ENGINE=InnoDB;

# update용 system_upd 컬럼에 인덱스 생성. 
create index idx_order_items_001 on order_items(system_upd);

select * from customers;
select * from products;
select * from orders;
select * from order_items;
```

- 한국 표준시를 mysqld 환경에 적용

```sql
cd /etc/mysql/mysql.conf.d
sudo vi mysqld.cnf
# 아래 설정을 mysqld.cnf에 추가
default_time_zone = '+09:00'
```

- mysql 재기동

```sql
sudo systemctl restart mysql
```

- time_zone 확인

```bash
show variables like '%time_zone%';
```

- systemctl로 mysql 자동등록

```bash
sudo systemctl enable mysql
```
