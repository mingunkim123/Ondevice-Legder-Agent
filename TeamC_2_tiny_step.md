# C팀 팀원 2 초미세 실행 체크리스트

이 문서는 `README.md`, `CLAUDE.md`, `TEAM_C_MEMBER2_GUIDE.md`를 기준으로 C팀 팀원 2가 해야 할 일을 아주 작은 단위로 나눈 체크리스트다.

목표는 고민을 줄이고, 위에서부터 하나씩 체크하면서 작업을 진행하는 것이다.

---

## 0. 내가 맡은 일 확인

- [ ] Step 1. `README.md`를 연다.
- [ ] Step 2. Linear 워크스페이스 이름이 `daedongje-yonsei-server`인지 확인한다.
- [ ] Step 3. 팀 이름이 `Back`인지 확인한다.
- [ ] Step 4. C팀 라벨이 `Team-C`인지 확인한다.
- [ ] Step 5. 홈 기능 라벨이 `H-홈`인지 확인한다.
- [ ] Step 6. `TEAM_C_MEMBER2_GUIDE.md`를 연다.
- [ ] Step 7. 내가 맡은 도메인이 홈 화면 공개 API인지 확인한다.
- [ ] Step 8. 내가 먼저 할 기능이 `H-01`인지 확인한다.
- [ ] Step 9. `H-01`의 API가 `GET /api/home/banners`인지 확인한다.
- [ ] Step 10. 다음 기능들이 남아 있음을 확인한다.

```text
1. H-01 메인 배너 조회
2. H-03 부스 클릭 로그 저장
3. H-03 오늘의 인기 부스 조회
4. H-02 현재 진행 중인 공연 조회
5. H-02/H-03 A팀/B팀 연동 보완
```

---

## 1. 첫 번째 Linear 이슈 만들기

- [ ] Step 1. 브라우저를 연다.
- [ ] Step 2. Linear에 접속한다.
- [ ] Step 3. 워크스페이스 `daedongje-yonsei-server`에 들어간다.
- [ ] Step 4. `Back` 팀으로 들어간다.
- [ ] Step 5. 새 이슈 만들기 버튼을 누른다.
- [ ] Step 6. 제목에 아래 문장을 입력한다.

```text
[H-01] 메인 배너 조회 API 구현
```

- [ ] Step 7. 팀 라벨 `Team-C`를 추가한다.
- [ ] Step 8. 기능 라벨 `H-홈`을 추가한다.
- [ ] Step 9. 타입 라벨 `Feature`를 추가한다.
- [ ] Step 10. 본문에 아래 내용을 붙여넣는다.

```markdown
## 배경 / 목적
홈 화면에서 노출할 메인 홍보 배너 목록을 제공한다.

## 작업 내용
- [ ] 배너 응답 DTO를 정의한다.
- [ ] GET /api/home/banners API를 구현한다.
- [ ] 공통 ApiResponse 형식으로 응답한다.
- [ ] Swagger 설명을 추가한다.
- [ ] 테스트를 작성하거나 수동 검증한다.

## 완료 조건 (DoD)
- GET /api/home/banners가 정상 응답한다.
- 응답 배열의 정렬 기준이 명확하다.
- 공통 응답 형식을 지킨다.
- 프론트가 참고할 수 있는 응답 필드가 정리되어 있다.

## 참고 자료
- README.md
- TEAM_C_MEMBER2_GUIDE.md
```

- [ ] Step 11. 이슈를 생성한다.
- [ ] Step 12. 생성된 이슈 키를 확인한다.
- [ ] Step 13. 이슈 키를 메모한다.

```text
이슈 키: BACK-__
Function ID: H-01
```

---

## 2. Linear에서 브랜치 만들기

- [ ] Step 1. 방금 만든 Linear 이슈 상세 화면을 연다.
- [ ] Step 2. `Create branch` 버튼을 찾는다.
- [ ] Step 3. `Create branch` 버튼을 누른다.
- [ ] Step 4. 자동 생성된 브랜치명을 확인한다.
- [ ] Step 5. 브랜치명이 `feature/`로 시작하는지 확인한다.
- [ ] Step 6. 브랜치명에 `BACK-__` 이슈 키가 들어갔는지 확인한다.
- [ ] Step 7. 브랜치명에 한글이 없는지 확인한다.
- [ ] Step 8. 한글이 있으면 영어로 바꾼다.
- [ ] Step 9. 추천 브랜치명은 아래 형태다.

```text
feature/BACK-__-home-banner-api
```

- [ ] Step 10. 브랜치를 생성한다.
- [ ] Step 11. 브랜치명을 메모한다.

```text
브랜치명: feature/BACK-__-home-banner-api
```

---

## 3. Codex에게 작업 시작 정보 주기

- [ ] Step 1. Codex에게 이슈 키를 알려준다.
- [ ] Step 2. Codex에게 Function ID를 알려준다.
- [ ] Step 3. Codex에게 브랜치명을 알려준다.
- [ ] Step 4. 아래 형식으로 보내면 된다.

```text
이슈 키: BACK-__
Function ID: H-01
브랜치명: feature/BACK-__-home-banner-api
이 작업부터 진행해줘.
```

- [ ] Step 5. Codex가 현재 브랜치가 `dev`인지 확인하게 둔다.
- [ ] Step 6. Codex가 원격 브랜치를 가져오게 둔다.
- [ ] Step 7. Codex가 Linear 브랜치로 체크아웃하게 둔다.
- [ ] Step 8. Codex가 구현 전에 코드 구조를 읽게 둔다.

---

## 4. H-01 구현 전 결정할 것

- [ ] Step 1. 배너 데이터를 DB에서 관리할지 정한다.
- [ ] Step 2. 아직 운영 방식이 없으면 DB 기반으로 할지 팀에 확인한다.
- [ ] Step 3. 임시 고정 데이터로 시작할지 정한다.
- [ ] Step 4. 배너 응답 필드 후보를 확인한다.

```text
id
imageUrl
linkUrl
displayOrder
```

- [ ] Step 5. 노출 기간이 필요한지 생각한다.
- [ ] Step 6. 노출 기간이 필요하면 `startAt`, `endAt`을 후보에 넣는다.
- [ ] Step 7. 활성화 여부가 필요한지 생각한다.
- [ ] Step 8. 활성화 여부가 필요하면 `isActive`를 후보에 넣는다.
- [ ] Step 9. 정렬 기준을 `displayOrder ASC`로 둘지 정한다.
- [ ] Step 10. 빈 배너 목록이면 빈 배열을 반환할지 정한다.

---

## 5. H-01 코드 구현 체크리스트

- [ ] Step 1. 현재 패키지 구조를 확인한다.
- [ ] Step 2. 공통 응답 클래스 이름을 확인한다.
- [ ] Step 3. 기존 Controller 작성 방식을 확인한다.
- [ ] Step 4. 기존 Service 작성 방식을 확인한다.
- [ ] Step 5. 기존 DTO 작성 방식을 확인한다.
- [ ] Step 6. 기존 Swagger 어노테이션 작성 방식을 확인한다.
- [ ] Step 7. 홈 도메인 패키지를 만들 위치를 정한다.
- [ ] Step 8. `HomeController`를 만든다.
- [ ] Step 9. `HomeService`를 만든다.
- [ ] Step 10. `BannerResponse` DTO를 만든다.
- [ ] Step 11. DB 기반이면 `HomeBanner` 엔티티를 만든다.
- [ ] Step 12. DB 기반이면 `HomeBannerRepository`를 만든다.
- [ ] Step 13. DB 기반이면 Flyway migration 파일 번호를 확인한다.
- [ ] Step 14. DB 기반이면 새 migration 파일을 만든다.
- [ ] Step 15. migration에 배너 테이블 DDL을 작성한다.
- [ ] Step 16. Service에서 배너 목록을 조회한다.
- [ ] Step 17. Service에서 정렬 기준을 적용한다.
- [ ] Step 18. Controller에서 `GET /api/home/banners`를 연결한다.
- [ ] Step 19. Controller 응답을 `ApiResponse`로 감싼다.
- [ ] Step 20. Swagger 설명을 추가한다.
- [ ] Step 21. 정상 응답 테스트를 작성한다.
- [ ] Step 22. 빈 목록 응답 테스트를 작성한다.
- [ ] Step 23. DB 기반이면 정렬 테스트를 작성한다.
- [ ] Step 24. 테스트를 실행한다.
- [ ] Step 25. 실패한 테스트가 있으면 원인을 확인한다.
- [ ] Step 26. 실패한 테스트를 수정한다.
- [ ] Step 27. 다시 테스트를 실행한다.
- [ ] Step 28. Swagger UI에서 API가 보이는지 확인한다.
- [ ] Step 29. 수동으로 API를 호출해본다.
- [ ] Step 30. 응답 형식이 공통 포맷인지 확인한다.

---

## 6. H-01 커밋과 푸시

- [ ] Step 1. `git status`를 확인한다.
- [ ] Step 2. 내가 의도한 파일만 바뀌었는지 확인한다.
- [ ] Step 3. `git diff`를 확인한다.
- [ ] Step 4. migration 파일이 있다면 엔티티와 컬럼명이 맞는지 확인한다.
- [ ] Step 5. 테스트 파일이 빠지지 않았는지 확인한다.
- [ ] Step 6. 변경 파일을 stage한다.
- [ ] Step 7. `git diff --staged`를 확인한다.
- [ ] Step 8. 첫 커밋 메시지를 정한다.

```text
feat: H-01 배너 조회 API 구현 (BACK-__)
```

- [ ] Step 9. 커밋한다.
- [ ] Step 10. 커밋 직후 원격 브랜치에 푸시한다.
- [ ] Step 11. Linear 이슈에 커밋이 연결됐는지 확인한다.

---

## 7. H-01 PR 만들기

- [ ] Step 1. GitHub에서 새 PR 화면을 연다.
- [ ] Step 2. base 브랜치가 `dev`인지 확인한다.
- [ ] Step 3. compare 브랜치가 내 `feature/BACK-__-home-banner-api`인지 확인한다.
- [ ] Step 4. PR 제목을 작성한다.

```text
feat: 메인 배너 조회 API 구현
```

- [ ] Step 5. PR 본문 템플릿이 뜨는지 확인한다.
- [ ] Step 6. 관련 이슈에 GitHub 이슈 번호를 넣는다.
- [ ] Step 7. Function ID에 `H-01`을 넣는다.
- [ ] Step 8. 작업 내용을 한국어로 적는다.
- [ ] Step 9. 테스트 결과를 적는다.
- [ ] Step 10. 리뷰 참고사항을 적는다.
- [ ] Step 11. 체크리스트에서 실제 완료한 것만 체크한다.
- [ ] Step 12. C팀 팀장을 리뷰어로 추가한다.
- [ ] Step 13. 다른 팀 도메인 파일을 수정했다면 해당 팀 팀장도 리뷰어로 추가한다.
- [ ] Step 14. PR을 생성한다.
- [ ] Step 15. Linear 이슈 상태가 `In Review`로 바뀌었는지 확인한다.

---

## 8. 두 번째 이슈: H-03 부스 클릭 로그 저장

- [ ] Step 1. H-01 PR을 올린다.
- [ ] Step 2. Linear로 돌아간다.
- [ ] Step 3. 새 이슈 만들기 버튼을 누른다.
- [ ] Step 4. 제목을 입력한다.

```text
[H-03] 부스 클릭 로그 저장 API 구현
```

- [ ] Step 5. 라벨 `Team-C`를 붙인다.
- [ ] Step 6. 라벨 `H-홈`을 붙인다.
- [ ] Step 7. 타입 `Feature`를 붙인다.
- [ ] Step 8. 본문에 클릭 로그 저장 목적을 적는다.
- [ ] Step 9. 완료 조건에 로그 저장, migration, 테스트를 적는다.
- [ ] Step 10. 이슈를 생성한다.
- [ ] Step 11. 이슈 키를 메모한다.
- [ ] Step 12. `Create branch`를 누른다.
- [ ] Step 13. 브랜치명을 영어로 만든다.

```text
feature/BACK-__-booth-click-log-api
```

- [ ] Step 14. Codex에게 이슈 키, Function ID, 브랜치명을 알려준다.

---

## 9. H-03 클릭 로그 구현 체크리스트

- [ ] Step 1. 클릭 로그에 저장할 필드를 정한다.
- [ ] Step 2. 최소 필드로 `id`를 둔다.
- [ ] Step 3. 최소 필드로 `boothId`를 둔다.
- [ ] Step 4. 최소 필드로 `clickedAt`을 둔다.
- [ ] Step 5. 방문자 식별자가 필요한지 팀에 확인한다.
- [ ] Step 6. 필요 없으면 이번 PR에서는 방문자 식별자를 넣지 않는다.
- [ ] Step 7. 기존 부스 도메인 구조를 확인한다.
- [ ] Step 8. 부스 존재 검증을 지금 할지 정한다.
- [ ] Step 9. A팀 구조와 충돌 가능성이 있으면 존재 검증을 후속으로 미룬다.
- [ ] Step 10. `BoothClickLog` 엔티티를 만든다.
- [ ] Step 11. `BoothClickLogRepository`를 만든다.
- [ ] Step 12. Flyway migration 번호를 확인한다.
- [ ] Step 13. 클릭 로그 테이블 migration을 만든다.
- [ ] Step 14. `booth_id` 인덱스를 추가한다.
- [ ] Step 15. `clicked_at` 인덱스를 추가한다.
- [ ] Step 16. 클릭 저장 Service를 만든다.
- [ ] Step 17. `POST /api/booths/{boothId}/clicks` Controller를 만든다.
- [ ] Step 18. 성공 응답 형식을 정한다.
- [ ] Step 19. 데이터 없는 성공 응답이면 `ApiResponse.successEmpty()` 패턴을 확인한다.
- [ ] Step 20. 저장 성공 테스트를 작성한다.
- [ ] Step 21. 잘못된 `boothId` 테스트가 필요한지 정한다.
- [ ] Step 22. 테스트를 실행한다.
- [ ] Step 23. API를 수동 호출한다.
- [ ] Step 24. DB에 클릭 로그가 저장됐는지 확인한다.
- [ ] Step 25. 커밋한다.
- [ ] Step 26. 커밋 직후 푸시한다.
- [ ] Step 27. PR을 올린다.

---

## 10. 세 번째 이슈: H-03 오늘의 인기 부스 조회

- [ ] Step 1. 클릭 로그 저장 PR 상태를 확인한다.
- [ ] Step 2. 클릭 로그 저장 PR이 머지됐는지 확인한다.
- [ ] Step 3. 아직 머지 전이면 같은 브랜치 의존성이 없는지 확인한다.
- [ ] Step 4. Linear에서 새 이슈를 만든다.
- [ ] Step 5. 제목을 입력한다.

```text
[H-03] 오늘의 인기 부스 조회 API 구현
```

- [ ] Step 6. 라벨 `Team-C`를 붙인다.
- [ ] Step 7. 라벨 `H-홈`을 붙인다.
- [ ] Step 8. 타입 `Feature`를 붙인다.
- [ ] Step 9. 이슈를 생성한다.
- [ ] Step 10. 브랜치를 생성한다.

```text
feature/BACK-__-popular-booths-api
```

- [ ] Step 11. Codex에게 이슈 키, Function ID, 브랜치명을 알려준다.

---

## 11. H-03 인기 부스 구현 체크리스트

- [ ] Step 1. "오늘"의 기준 시간대를 정한다.
- [ ] Step 2. 서버 기준 시간대를 확인한다.
- [ ] Step 3. 오늘 시작 시각을 정한다.
- [ ] Step 4. 오늘 종료 시각 대신 현재 시각까지 조회할지 정한다.
- [ ] Step 5. 조회 범위를 `오늘 00:00:00`부터 `현재`까지로 둔다.
- [ ] Step 6. 인기 부스 개수를 정한다.
- [ ] Step 7. 기본값을 TOP 3 또는 TOP 5 중 하나로 정한다.
- [ ] Step 8. 응답 필드를 정한다.

```text
rank
boothId
clickCount
```

- [ ] Step 9. A팀 연동 후 추가할 필드를 메모한다.

```text
boothName
organizationName
thumbnailUrl
mainMenu
```

- [ ] Step 10. Repository 집계 쿼리를 작성한다.
- [ ] Step 11. `boothId`로 그룹화한다.
- [ ] Step 12. 클릭 수를 센다.
- [ ] Step 13. 클릭 수 내림차순으로 정렬한다.
- [ ] Step 14. 동률이면 `boothId` 오름차순으로 정렬한다.
- [ ] Step 15. 결과 개수를 제한한다.
- [ ] Step 16. Service에서 순위를 붙인다.
- [ ] Step 17. `GET /api/home/popular-booths` Controller를 만든다.
- [ ] Step 18. 데이터가 없을 때 빈 배열을 반환한다.
- [ ] Step 19. 정렬 테스트를 작성한다.
- [ ] Step 20. 기간 필터 테스트를 작성한다.
- [ ] Step 21. 결과 개수 제한 테스트를 작성한다.
- [ ] Step 22. 테스트를 실행한다.
- [ ] Step 23. API를 수동 호출한다.
- [ ] Step 24. 응답 순위가 맞는지 확인한다.
- [ ] Step 25. 커밋한다.
- [ ] Step 26. 커밋 직후 푸시한다.
- [ ] Step 27. PR을 올린다.

---

## 12. 네 번째 이슈: H-02 현재 진행 중인 공연 조회

- [ ] Step 1. B팀 공연 데이터가 이미 있는지 확인한다.
- [ ] Step 2. 없으면 응답 계약부터 먼저 만들기로 정한다.
- [ ] Step 3. Linear에서 새 이슈를 만든다.
- [ ] Step 4. 제목을 입력한다.

```text
[H-02] 현재 진행 중인 공연 API 1차 구현
```

- [ ] Step 5. 라벨 `Team-C`를 붙인다.
- [ ] Step 6. 라벨 `H-홈`을 붙인다.
- [ ] Step 7. 타입 `Feature`를 붙인다.
- [ ] Step 8. 이슈를 생성한다.
- [ ] Step 9. 브랜치를 생성한다.

```text
feature/BACK-__-current-performance-api
```

- [ ] Step 10. Codex에게 이슈 키, Function ID, 브랜치명을 알려준다.

---

## 13. H-02 구현 체크리스트

- [ ] Step 1. 공연 응답 필드 후보를 정한다.

```text
performanceId
title
stageName
startsAt
endsAt
```

- [ ] Step 2. 썸네일이 필요한지 B팀에 확인한다.
- [ ] Step 3. 장소명이 필요한지 B팀에 확인한다.
- [ ] Step 4. 동시에 여러 공연이 진행될 수 있는지 B팀에 확인한다.
- [ ] Step 5. 진행 중 공연이 없을 때 응답을 정한다.
- [ ] Step 6. `null`로 줄지 빈 상태 DTO로 줄지 정한다.
- [ ] Step 7. 시간 조건을 정한다.

```text
startsAt <= now < endsAt
```

- [ ] Step 8. Controller 경로를 만든다.

```text
GET /api/home/current-performance
```

- [ ] Step 9. 응답 DTO를 만든다.
- [ ] Step 10. Service를 만든다.
- [ ] Step 11. B팀 테이블이 있으면 Repository 조회를 연결한다.
- [ ] Step 12. B팀 테이블이 없으면 교체 가능한 구조로 빈 응답 또는 임시 구현을 만든다.
- [ ] Step 13. 현재 공연 있음 테스트를 작성한다.
- [ ] Step 14. 현재 공연 없음 테스트를 작성한다.
- [ ] Step 15. 시작 시각 경계 테스트를 작성한다.
- [ ] Step 16. 종료 시각 경계 테스트를 작성한다.
- [ ] Step 17. 테스트를 실행한다.
- [ ] Step 18. API를 수동 호출한다.
- [ ] Step 19. 커밋한다.
- [ ] Step 20. 커밋 직후 푸시한다.
- [ ] Step 21. PR을 올린다.

---

## 14. 후속 이슈: A팀/B팀 연동 보완

- [ ] Step 1. H-03 인기 부스 응답에 부스 상세 정보가 필요한지 확인한다.
- [ ] Step 2. A팀에게 부스 테이블 구조를 확인한다.
- [ ] Step 3. A팀에게 부스명 필드명을 확인한다.
- [ ] Step 4. A팀에게 단체명 필드명을 확인한다.
- [ ] Step 5. A팀에게 썸네일 필드명을 확인한다.
- [ ] Step 6. A팀에게 홈 노출 제외 조건이 있는지 확인한다.
- [ ] Step 7. H-02 현재 공연 응답에 공연 상세 정보가 필요한지 확인한다.
- [ ] Step 8. B팀에게 공연 시작 시각 필드명을 확인한다.
- [ ] Step 9. B팀에게 공연 종료 시각 필드명을 확인한다.
- [ ] Step 10. B팀에게 무대명 필드명을 확인한다.
- [ ] Step 11. B팀에게 썸네일 필드명을 확인한다.
- [ ] Step 12. Linear에 연동 보완 이슈를 만든다.
- [ ] Step 13. 제목을 입력한다.

```text
[H-02/H-03] A팀/B팀 연동 보완
```

- [ ] Step 14. 라벨 `Team-C`를 붙인다.
- [ ] Step 15. 라벨 `H-홈`을 붙인다.
- [ ] Step 16. 타입 `Feature` 또는 `Improvement` 중 맞는 것을 붙인다.
- [ ] Step 17. 브랜치를 생성한다.
- [ ] Step 18. Codex에게 이슈 키, Function ID, 브랜치명을 알려준다.

---

## 15. 매 작업마다 반복할 규칙

- [ ] Step 1. Linear 이슈를 먼저 만든다.
- [ ] Step 2. 이슈 키를 확인한다.
- [ ] Step 3. Function ID를 확인한다.
- [ ] Step 4. Linear에서 브랜치를 만든다.
- [ ] Step 5. 브랜치명이 영어인지 확인한다.
- [ ] Step 6. 브랜치가 `feature/BACK-__-...` 형식인지 확인한다.
- [ ] Step 7. `dev`에서 시작했는지 확인한다.
- [ ] Step 8. 구현한다.
- [ ] Step 9. 테스트한다.
- [ ] Step 10. `git status`를 확인한다.
- [ ] Step 11. 의도한 파일만 stage한다.
- [ ] Step 12. `git diff --staged`를 확인한다.
- [ ] Step 13. 커밋 메시지에 이슈 키를 넣는다.
- [ ] Step 14. 커밋한다.
- [ ] Step 15. 바로 푸시한다.
- [ ] Step 16. PR을 만든다.
- [ ] Step 17. PR 본문에 Linear 또는 GitHub 이슈를 연결한다.
- [ ] Step 18. Function ID를 적는다.
- [ ] Step 19. 테스트 결과를 적는다.
- [ ] Step 20. 리뷰어를 추가한다.

---

## 16. Codex에게 줄 정보 템플릿

작업을 시작할 때 아래 내용을 그대로 채워서 보내면 된다.

```text
이슈 키: BACK-__
GitHub 이슈 번호: #__
Function ID: H-__
브랜치명: feature/BACK-__-영어-브랜치명
작업 범위: __ API 구현
PR 목표: __까지 구현하고 테스트 후 PR 준비
```

GitHub 이슈 번호를 아직 모르면 비워도 된다. 단, PR 생성 단계에서는 반드시 확인해야 한다.

---

## 17. 지금 바로 할 첫 행동

- [ ] Step 1. Linear에 접속한다.
- [ ] Step 2. `daedongje-yonsei-server` 워크스페이스를 연다.
- [ ] Step 3. `Back` 팀을 연다.
- [ ] Step 4. 새 이슈를 누른다.
- [ ] Step 5. 제목에 `[H-01] 메인 배너 조회 API 구현`을 입력한다.
- [ ] Step 6. `Team-C` 라벨을 붙인다.
- [ ] Step 7. `H-홈` 라벨을 붙인다.
- [ ] Step 8. `Feature` 타입을 붙인다.
- [ ] Step 9. 본문 템플릿을 붙인다.
- [ ] Step 10. 이슈를 생성한다.
- [ ] Step 11. `Create branch`를 누른다.
- [ ] Step 12. 브랜치명을 영어로 정한다.
- [ ] Step 13. 이슈 키와 브랜치명을 Codex에게 보낸다.
