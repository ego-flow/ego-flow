# EC2 Data Operations

이 문서는 EgoFlow production 배포에서 데이터를 보존하면서 schema 변경과 설정 변경을 수행하기 위한 최소 운영 기준을 정리한다.

## Change Classes

| Class | 예시 | 기본 정책 |
| --- | --- | --- |
| `Class A` | backend/dashboard 코드 변경, worker 로직 변경, additive migration, proxy 설정 변경 | 일반 배포 가능. immutable SHA, smoke test, rollback snapshot 확인 |
| `Class B` | `TARGET_DIRECTORY` 변경, path rewrite 포함 migration, 대량 backfill, 중요 테이블/인덱스 변경 | 사전 backup 필수. 작업 전 검증과 작업 후 데이터 무결성 확인 필요 |
| `Class C` | `down -v`, data directory 삭제, raw/datasets 삭제, 운영 reset | production 기본 금지. 명시적 승인 + backup/restore 계획 없이는 수행 금지 |

## Migration Policy

- production schema 변경은 `prisma migrate deploy` 기반 비파괴 migration을 기본값으로 사용한다.
- additive migration은 `Class A`로 취급하되, 배포 전 migration SQL과 영향 범위를 검토한다.
- destructive migration은 `Class B` 이상으로 취급한다.
- `nullable -> non-null`, column rename, data backfill, table drop은 backup 계획과 rollback 기준이 없으면 배포하지 않는다.
- production에서 `down -v`, `/opt/egoflow/data/*` 삭제는 표준 migration 절차가 아니다.

## Seed Policy

현재 seed는 아래 두 항목만 보장한다.

- `id=admin` 사용자 row가 없을 때만 생성
- `settings.key=target_directory` row가 없을 때만 생성

운영 기준:

- 기존 admin 계정이 있으면 seed는 비밀번호를 덮어쓰지 않는다.
- 기존 `target_directory` setting이 있으면 seed는 값을 덮어쓰지 않는다.
- seed는 운영 데이터 입력용이 아니라 bootstrap row 보장용으로만 취급한다.
- seed 로직이 바뀌는 배포는 운영 영향 검토 대상이다.

## `TARGET_DIRECTORY` Change Procedure

`TARGET_DIRECTORY` 변경은 일반 `config.json` 수정이 아니다. backend 부팅 시 파일 이동과 DB path rewrite가 함께 실행되므로 `Class B` 작업으로 취급한다.

### Preflight

1. source path와 destination path를 절대경로 기준으로 확정한다.
2. destination이 비어 있는지 확인한다.
3. source/destination이 nested 관계가 아닌지 확인한다.
4. active stream이 없는지 확인한다.
5. PostgreSQL backup을 만든다.
6. `${DATA_ROOT}/datasets`, `${DATA_ROOT}/raw` snapshot 또는 복사본을 만든다.
7. 현재 `/opt/egoflow/config/{config.json,.env,.env.compose}`와 `/opt/egoflow/releases/latest.json`을 보관한다.

### Apply

1. 새 `TARGET_DIRECTORY`를 `config.json`에 반영한다.
2. immutable image SHA와 기존 config snapshot을 기록한다.
3. `deploy/ec2/deploy.sh deploy`를 실행한다.
4. backend 로그에서 `migrating target_directory` 메시지와 오류 여부를 확인한다.

### Validate

1. `deploy/ec2/deploy.sh smoke-test` 실행
2. 샘플 `videos` row의 `vlmVideoPath`, `dashboardVideoPath`, `thumbnailPath`가 새 경로를 가리키는지 확인
3. 실제 파일이 새 경로에 존재하는지 확인
4. dashboard 재생과 thumbnail 접근 확인

### Rollback

1. compose stack 정지
2. 이전 config snapshot을 `/opt/egoflow/config`로 복원
3. PostgreSQL backup 복원
4. datasets/raw snapshot 복원
5. 이전 image SHA로 다시 배포
6. smoke test와 샘플 데이터 검증 재실행

## Backup Minimum

production 변경 전 최소 보관 항목:

- PostgreSQL dump 또는 filesystem snapshot
- Redis persistence snapshot
- `${DATA_ROOT}/datasets` snapshot 또는 복사본
- `${DATA_ROOT}/raw` snapshot 또는 복사본
- `/opt/egoflow/config/config.json`
- `/opt/egoflow/config/.env`
- `/opt/egoflow/config/.env.compose`
- 배포 대상 backend/dashboard image SHA

`deploy/ec2/deploy.sh`는 각 배포마다 `/opt/egoflow/releases/release-*/` 아래에 `config.json`, `.env`, `.env.compose` snapshot과 metadata를 남긴다. 이 snapshot은 rollback 참고 자료이며, DB/filesystem backup을 대체하지는 않는다.

## Restore Minimum

권장 복구 순서:

1. 복구할 release metadata와 image SHA 확인
2. compose stack 정지
3. PostgreSQL 복구
4. Redis 복구가 필요하면 함께 적용
5. `${DATA_ROOT}/datasets`와 `${DATA_ROOT}/raw` 복구
6. `/opt/egoflow/config` 복구
7. 대상 image SHA로 재배포
8. smoke test 실행
9. 샘플 repository/video의 파일 경로와 playback 검증

## Production Prohibitions

아래 작업은 production 표준 운영 절차가 아니다.

- `docker compose ... down -v`
- `rm -rf /opt/egoflow/data/postgres`
- `rm -rf /opt/egoflow/data/redis`
- `rm -rf /opt/egoflow/data/raw`
- `rm -rf /opt/egoflow/data/datasets`
- backup 없이 `TARGET_DIRECTORY` 변경

## Deployment Data Checklist

### Before Deploy

1. 변경을 `Class A/B/C` 중 하나로 분류
2. migration SQL과 seed 변경 여부 확인
3. `TARGET_DIRECTORY` 변경 여부 확인
4. backup 필요 여부와 위치 확인
5. deploy할 image SHA와 config diff 확인

### After Deploy

1. `docker compose ... ps` 확인
2. `deploy/ec2/deploy.sh smoke-test` 실행
3. dashboard login 확인
4. worker 오류 로그 확인
5. 샘플 `videos` row와 실제 파일 경로 확인
6. 필요 시 RTMP/HLS 기본 동작 확인
