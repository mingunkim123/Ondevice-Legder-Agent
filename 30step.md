# shop-app 상품 CRUD 구현 30단계 진행 문서

이 문서는 6주차 복습 과제인 `shop-app` 상품 CRUD API를 하나씩 구현하기 위한 체크리스트입니다.  
각 단계가 끝날 때마다 실행 또는 확인을 하고 다음 단계로 넘어가면 됩니다.

> 참고: Java 패키지명에는 `-`를 사용할 수 없으므로 `com.example.shopapp` 형태로 진행합니다.

## 1. 프로젝트 생성 준비

- [ ] 1. Spring Initializr에 접속한다.
- [ ] 2. 프로젝트 옵션을 아래처럼 설정한다.
  - Project: Gradle
  - Language: Java
  - Spring Boot: 안정 버전 선택
  - Java: 17
  - Name: `shop-app`
  - Package name: `com.example.shopapp`

## 2. 의존성 추가

- [ ] 3. Dependencies에 아래 항목을 추가한다.
  - Spring Web
  - Spring Data JPA
  - MySQL Driver
  - Lombok
  - Springdoc OpenAPI

- [ ] 4. 프로젝트를 다운로드하고 IDE에서 연다.
- [ ] 5. Gradle 동기화가 정상적으로 되는지 확인한다.

## 3. MySQL DB 준비

- [ ] 6. MySQL에 접속한다.
- [ ] 7. `shop_app` 데이터베이스를 생성한다.

```sql
CREATE DATABASE shop_app
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;
```

- [ ] 8. DB 비밀번호를 환경변수 `DB_PASSWORD`로 등록한다.
  - IntelliJ 실행 설정 또는 터미널 환경변수에 등록한다.

## 4. application.properties 설정

- [ ] 9. `src/main/resources/application.properties`에 DB 설정을 작성한다.

```properties
spring.datasource.url=jdbc:mysql://localhost:3306/shop_app?serverTimezone=Asia/Seoul&characterEncoding=UTF-8
spring.datasource.username=root
spring.datasource.password=${DB_PASSWORD}
spring.datasource.driver-class-name=com.mysql.cj.jdbc.Driver

spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=true
spring.jpa.properties.hibernate.format_sql=true
```

- [ ] 10. 애플리케이션을 한 번 실행해서 DB 연결 오류가 없는지 확인한다.

## 5. 패키지 구조 생성

- [ ] 11. `src/main/java/com/example/shopapp` 아래에 패키지를 만든다.

```text
com.example.shopapp
├── controller
├── service
├── repository
├── domain
├── dto
└── exception
```

## 6. Entity 구현

- [ ] 12. `domain/Member.java`를 만든다.
  - 필드: `id`, `nickname`, `createdAt`, `updatedAt`
  - 테이블명은 `members`로 지정한다.

- [ ] 13. `domain/Product.java`를 만든다.
  - 필드: `id`, `member`, `name`, `description`, `price`, `createdAt`, `updatedAt`
  - `Product`와 `Member`는 `ManyToOne` 관계로 연결한다.

- [ ] 14. `createdAt`, `updatedAt` 자동 저장 방식을 정한다.
  - 간단하게는 `@PrePersist`, `@PreUpdate`를 사용한다.
  - 또는 Spring Data JPA Auditing을 사용해도 된다.

## 7. Repository 구현

- [ ] 15. `repository/MemberRepository.java`를 만든다.
  - `JpaRepository<Member, Long>`를 상속한다.

- [ ] 16. `repository/ProductRepository.java`를 만든다.
  - `JpaRepository<Product, Long>`를 상속한다.
  - 상품명 검색 메서드를 추가한다.

```java
List<Product> findByNameContainingOrderByCreatedAtDesc(String keyword);
```

## 8. DTO 구현

- [ ] 17. `dto/ProductCreateRequest.java`를 만든다.
  - 필드: `sellerId`, `name`, `description`, `price`

- [ ] 18. `dto/ProductUpdateRequest.java`를 만든다.
  - 필드: `name`, `description`, `price`

- [ ] 19. `dto/ProductResponse.java`를 만든다.
  - 필드: `id`, `sellerId`, `sellerNickname`, `name`, `description`, `price`, `createdAt`, `updatedAt`
  - `Product` Entity를 `ProductResponse`로 변환하는 정적 메서드를 만들어도 좋다.

## 9. 예외 처리 구조 구현

- [ ] 20. `exception/ErrorCode.java` enum을 만든다.
  - `PRODUCT_NOT_FOUND`
  - `MEMBER_NOT_FOUND`
  - `INVALID_PRODUCT_NAME`
  - `INVALID_PRODUCT_DESCRIPTION`
  - `INVALID_PRODUCT_PRICE`
  - `INTERNAL_SERVER_ERROR`

- [ ] 21. `exception/ErrorResponse.java`를 만든다.
  - 필드: `code`, `message`

- [ ] 22. `exception/CustomException.java`를 만든다.
  - `ErrorCode`를 필드로 가진 RuntimeException 형태로 구현한다.

- [ ] 23. `exception/GlobalExceptionHandler.java`를 만든다.
  - `@RestControllerAdvice` 사용
  - `CustomException` 처리
  - 예상하지 못한 예외는 `INTERNAL_SERVER_ERROR`로 처리

## 10. Service 구현

- [ ] 24. `service/ProductService.java`를 만든다.
  - 상품 등록
  - 상품 전체 조회
  - 상품 단건 조회
  - 상품 수정
  - 상품 삭제
  - 상품명 검색

- [ ] 25. 상품 등록 로직을 구현한다.
  - `sellerId`로 `Member` 조회
  - 회원이 없으면 `MEMBER_NOT_FOUND`
  - 상품명, 설명, 가격 검증
  - `Product` 저장 후 `ProductResponse` 반환

- [ ] 26. 상품 조회, 수정, 삭제 로직을 구현한다.
  - 상품이 없으면 `PRODUCT_NOT_FOUND`
  - 수정 시에도 상품명, 설명, 가격 검증
  - 삭제는 `productRepository.delete(product)` 사용

## 11. Controller 구현

- [ ] 27. `controller/ProductController.java`를 만든다.
  - 기본 경로: `/api/products`

- [ ] 28. 아래 API를 연결한다.

| Method | URL | 메서드 역할 |
| --- | --- | --- |
| `POST` | `/api/products` | 상품 등록 |
| `GET` | `/api/products` | 상품 전체 조회 |
| `GET` | `/api/products/{productId}` | 상품 단건 조회 |
| `PATCH` | `/api/products/{productId}` | 상품 수정 |
| `DELETE` | `/api/products/{productId}` | 상품 삭제 |
| `GET` | `/api/products/search?keyword={keyword}` | 상품명 검색 |

## 12. 테스트 데이터 입력

- [ ] 29. 애플리케이션을 실행해서 `members`, `products` 테이블이 생성되었는지 확인한다.
- [ ] 30. MySQL에서 테스트용 Member 데이터를 넣는다.

```sql
INSERT IGNORE INTO shop_app.members (id, nickname, created_at, updated_at)
VALUES
    (1, '멋쟁이', NOW(), NOW()),
    (2, '사자', NOW(), NOW());
```

## 13. Swagger 테스트

아래 주소로 Swagger에 접속한다.

```text
http://localhost:8080/swagger-ui/index.html
```

Swagger에서 아래 순서로 테스트하고 캡처한다.

- [ ] 상품 등록
- [ ] 상품 전체 조회
- [ ] 상품 단건 조회
- [ ] 상품 수정
- [ ] 상품명 검색
- [ ] 상품 삭제

## 14. 최종 점검

제출 전에 아래 항목을 확인한다.

- [ ] 프로젝트가 정상 실행된다.
- [ ] DB 연결이 정상이다.
- [ ] 모든 API가 Swagger에서 호출된다.
- [ ] 에러 응답 형식이 과제 요구사항과 일치한다.

```json
{
  "code": "PRODUCT_NOT_FOUND",
  "message": "상품을 찾을 수 없습니다."
}
```

- [ ] 상품명, 상품 설명, 가격 검증이 동작한다.
- [ ] 존재하지 않는 상품 또는 회원 조회 시 404가 반환된다.
- [ ] GitHub 레포 이름을 `14-ASSIGNMENT-SPRING-{이름}` 형식으로 만든다.
- [ ] Swagger 테스트 캡처를 제출 문서에 첨부한다.

