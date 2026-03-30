# Recording-Centric Streaming Refactor

## 1. 목표

사용자 경험 기준의 핵심 단위는 `stream`이 아니라 `recording`이다.

- 사용자가 `Start Streaming`을 누르면 recording 1개가 시작된다.
- 사용자가 `Stop Streaming`을 누르거나 glasses에서 촬영 종료를 하면 recording 1개가 끝난다.
- recording 1개는 최종적으로 `Video` 1개를 만든다.

즉 최종 모델은 아래와 같다.

- `RecordingSession 1개 = 사용자 촬영 1회`
- `RecordingSession 1개 = raw segment N개`
- `RecordingSession 1개 = final Video 1개`

## 2. 현재 구조의 문제

현재 구현은 사실상 아래 모델이다.

- `recording segment complete 1회 -> videos row 1개 생성 -> worker job 1개`

이 구조의 문제:

- 사용자 stop 1회와 final video 1개가 직접 대응되지 않는다.
- 긴 recording에서 segment가 여러 개 생기면 video row도 여러 개 생긴다.
- stop 요청, 실제 stream 종료, raw file flush 완료가 한 덩어리로 다뤄지지 않는다.

현재 충돌 지점:

- [hooks.routes.ts](/home/dennis0405/ego-flow/ego-flow-server/backend/src/routes/hooks.routes.ts)
- [video-processing.worker.ts](/home/dennis0405/ego-flow/ego-flow-server/backend/src/workers/video-processing.worker.ts)
- [schema.prisma](/home/dennis0405/ego-flow/ego-flow-server/backend/prisma/schema.prisma)
- [mediamtx.yml](/home/dennis0405/ego-flow/ego-flow-server/mediamtx.yml)

## 3. 새 도메인 모델

### 3.1 RecordingSession

의미:

- 사용자의 start부터 stop까지를 대표하는 최상위 recording 엔티티

책임:

- 현재 recording의 lifecycle 상태 관리
- repository / user / device context 보존
- MediaMTX source와의 연결
- raw segment들의 부모 역할
- 최종 video와의 1:1 연결

### 3.2 RecordingSegment

의미:

- MediaMTX가 생성한 raw recording 조각

책임:

- segment 생성/완료 여부 추적
- raw 파일 경로 추적
- 최종 worker 병합 입력 제공

### 3.3 Video

의미:

- 후처리 결과로 생성되는 최종 자산

책임:

- dashboard / VLM / thumbnail 경로 보존
- 후처리 상태 보존

## 4. 상태 모델

### 4.1 RecordingSessionStatus

- `PENDING`
- `STREAMING`
- `STOP_REQUESTED`
- `FINALIZING`
- `COMPLETED`
- `FAILED`
- `ABORTED`

### 4.2 RecordingSessionEndReason

- `USER_STOP`
- `GLASSES_STOP`
- `UNEXPECTED_DISCONNECT`
- `REGISTRATION_TIMEOUT`
- `INTERNAL_ERROR`

### 4.3 RecordingSegmentStatus

- `WRITING`
- `COMPLETED`
- `FAILED`

## 5. 상태 전이 규칙

### 5.1 RecordingSession

1. `POST /streams/register` 성공
   - `PENDING`
2. RTMP publish 성공 + `stream-ready` hook 수신
   - `STREAMING`
3. 사용자가 stop 요청
   - `STOP_REQUESTED`
4. MediaMTX `stream-not-ready` 수신
   - `FINALIZING`
5. finalize worker 성공
   - `COMPLETED`
6. finalize worker 실패
   - `FAILED`
7. register 후 publish 미시작 timeout
   - `ABORTED` + `REGISTRATION_TIMEOUT`
8. 예기치 않은 disconnect
   - `FINALIZING` + `UNEXPECTED_DISCONNECT`

### 5.2 RecordingSegment

1. `recording-segment-create`
   - `WRITING`
2. `recording-segment-complete`
   - `COMPLETED`
3. flush 실패 또는 orphan cleanup
   - `FAILED`

## 6. Prisma 스키마 변경안

### 6.1 enum 추가

```prisma
enum RecordingSessionStatus {
  PENDING
  STREAMING
  STOP_REQUESTED
  FINALIZING
  COMPLETED
  FAILED
  ABORTED
}

enum RecordingSessionEndReason {
  USER_STOP
  GLASSES_STOP
  UNEXPECTED_DISCONNECT
  REGISTRATION_TIMEOUT
  INTERNAL_ERROR
}

enum RecordingSegmentStatus {
  WRITING
  COMPLETED
  FAILED
}
```

### 6.2 RecordingSession 추가

```prisma
model RecordingSession {
  id               String                    @id @default(uuid()) @db.Uuid
  repositoryId     String                    @map("repository_id") @db.Uuid
  ownerId          String                    @map("owner_id") @db.VarChar(64)
  userId           String                    @map("user_id") @db.VarChar(64)
  deviceType       String?                   @map("device_type") @db.VarChar(100)
  streamPath       String                    @map("stream_path") @db.VarChar(255)
  status           RecordingSessionStatus
  endReason        RecordingSessionEndReason? @map("end_reason")
  targetDirectory  String                    @map("target_directory") @db.VarChar(1024)
  sourceId         String?                   @map("source_id") @db.VarChar(255)
  sourceType       String?                   @map("source_type") @db.VarChar(50)
  stopRequestedAt  DateTime?                 @map("stop_requested_at")
  readyAt          DateTime?                 @map("ready_at")
  notReadyAt       DateTime?                 @map("not_ready_at")
  finalizedAt      DateTime?                 @map("finalized_at")
  createdAt        DateTime                  @default(now()) @map("created_at")
  updatedAt        DateTime                  @updatedAt @map("updated_at")

  @@index([repositoryId, status], map: "idx_recording_sessions_repo_status")
  @@index([sourceId], map: "idx_recording_sessions_source_id")
  @@index([userId, createdAt], map: "idx_recording_sessions_user_created_at")
  @@map("recording_sessions")
}
```

### 6.3 RecordingSegment 추가

```prisma
model RecordingSegment {
  id                 String                @id @default(uuid()) @db.Uuid
  recordingSessionId String                @map("recording_session_id") @db.Uuid
  sequence           Int
  rawPath            String                @map("raw_path") @db.VarChar(1024)
  durationSec        Float?                @map("duration_sec")
  status             RecordingSegmentStatus
  createdAt          DateTime              @default(now()) @map("created_at")
  completedAt        DateTime?             @map("completed_at")

  @@unique([recordingSessionId, rawPath], map: "uniq_recording_segments_session_raw_path")
  @@index([recordingSessionId, sequence], map: "idx_recording_segments_session_sequence")
  @@map("recording_segments")
}
```

### 6.4 Video 변경

```prisma
model Video {
  id                    String      @id @default(uuid()) @db.Uuid
  repositoryId          String      @map("repository_id") @db.Uuid
  recordingSessionId    String?     @unique @map("recording_session_id") @db.Uuid
  rawRecordingPath      String      @map("raw_recording_path") @db.VarChar(1024)
  streamPath            String?     @map("stream_path") @db.VarChar(255)
  deviceType            String?     @map("device_type") @db.VarChar(100)
  sessionId             String?     @map("session_id") @db.VarChar(255)
  ...
}
```

주의:

- 초기 migration 단계에서는 `sessionId`를 즉시 삭제하지 말고 deprecated 상태로 둔다.
- 새 로직 안정화 후 `sessionId` 제거 migration을 별도로 수행한다.
- `rawRecordingPath`는 “최종 처리 대상 raw 파일” 의미로 재정의한다.

## 7. Redis 키 설계

Redis는 live authorization과 실시간 상태 조회만 담당한다.

### 7.1 키 목록

- `stream:repo:{repositoryId}` -> `recordingSessionId`
- `stream:path:{repoName}` -> `recordingSessionId`
- `stream:source:{sourceId}` -> `recordingSessionId`
- `stream:recording:{recordingSessionId}` -> lightweight live cache JSON

### 7.2 live cache 필드

```json
{
  "recordingSessionId": "uuid",
  "repositoryId": "uuid",
  "repositoryName": "daily_kitchen",
  "userId": "alice",
  "deviceType": "meta_glasses_android",
  "status": "STREAMING",
  "sourceId": "publisher-123",
  "sourceType": "rtmpConn",
  "readyAt": "2026-03-30T10:00:00.000Z",
  "stopRequestedAt": null
}
```

### 7.3 TTL 정책

- `PENDING`: 90초
- `STREAMING`: 24시간
- `STOP_REQUESTED`: 24시간
- `FINALIZING`: 24시간
- 종료 확정 시:
  - `stream:repo:*` 삭제
  - `stream:path:*` 삭제
  - `stream:source:*` 삭제
  - DB가 최종 source of truth가 됨

## 8. MediaMTX hook 설계

현재는 `runOnRecordSegmentComplete`만 사용한다.  
리팩터링 후에는 아래 4개 hook을 사용한다.

### 8.1 hook 목록

- `runOnReady`
- `runOnNotReady`
- `runOnRecordSegmentCreate`
- `runOnRecordSegmentComplete`

### 8.2 backend endpoint 매핑

- `POST /api/v1/hooks/stream-ready`
- `POST /api/v1/hooks/stream-not-ready`
- `POST /api/v1/hooks/recording-segment-create`
- `POST /api/v1/hooks/recording-segment-complete`

### 8.3 권장 구현 방식

직접 query string을 조립하지 말고, shell wrapper 또는 작은 helper script로 JSON POST를 보낸다.

이유:

- path/query/source metadata escaping 안정성
- hook payload 확장 용이성
- 디버깅 편의성

### 8.4 mediamtx.yml 변경 방향

현재 [mediamtx.yml](/home/dennis0405/ego-flow/ego-flow-server/mediamtx.yml) 기준에서 아래 방향으로 수정한다.

```yaml
pathDefaults:
  source: publisher
  overridePublisher: yes
  record: yes
  recordPath: /data/raw/%path/%Y-%m-%d_%H-%M-%S-%f
  recordFormat: fmp4
  recordPartDuration: 1s
  recordSegmentDuration: 12h
  recordDeleteAfter: 0s
  runOnReady: /mediamtx-hooks/stream-ready-wrapper.sh
  runOnNotReady: /mediamtx-hooks/stream-not-ready-wrapper.sh
  runOnRecordSegmentCreate: /mediamtx-hooks/segment-create-wrapper.sh
  runOnRecordSegmentComplete: /mediamtx-hooks/segment-complete-wrapper.sh
```

`recordSegmentDuration`을 크게 잡는 이유:

- 대부분의 recording이 단일 segment가 되도록 유도
- 하지만 단일 segment를 보장하는 것은 아님
- 최종적으로는 worker 병합 로직이 1 recording = 1 video를 보장해야 함

## 9. Hook payload 명세

### 9.1 POST /api/v1/hooks/stream-ready

request body:

```json
{
  "path": "live/daily_kitchen",
  "query": "user=alice&pass=jwt",
  "source_id": "publisher-123",
  "source_type": "rtmpConn"
}
```

처리:

- `stream:path:{repoName}`로 `recordingSessionId` 조회
- `RecordingSession.status`를 `STREAMING`으로 변경
- `readyAt`, `sourceId`, `sourceType` 기록
- Redis `stream:source:{sourceId}` 연결

### 9.2 POST /api/v1/hooks/stream-not-ready

request body:

```json
{
  "path": "live/daily_kitchen",
  "source_id": "publisher-123",
  "source_type": "rtmpConn"
}
```

처리:

- `sourceId` 또는 `path` 기준으로 `recordingSessionId` 조회
- 현재 status가 `STREAMING` 또는 `STOP_REQUESTED`이면 `FINALIZING`으로 변경
- `notReadyAt` 기록
- live pointer 삭제
- finalize enqueue 가능 여부 검사

### 9.3 POST /api/v1/hooks/recording-segment-create

request body:

```json
{
  "path": "live/daily_kitchen",
  "segment_path": "/data/raw/live/daily_kitchen/2026-03-30_10-00-00-000000"
}
```

처리:

- 현재 `recordingSessionId` 조회
- `RecordingSegment` row 생성
- `status=WRITING`
- `sequence`는 session별 max+1

### 9.4 POST /api/v1/hooks/recording-segment-complete

request body:

```json
{
  "path": "live/daily_kitchen",
  "segment_path": "/data/raw/live/daily_kitchen/2026-03-30_10-00-00-000000",
  "segment_duration": 123.45
}
```

처리:

- 동일 `RecordingSegment` row를 찾아 `COMPLETED`
- `durationSec`, `completedAt` 기록
- session이 이미 `FINALIZING`이면 finalize enqueue 가능 여부 재검사

## 10. API 설계

### 10.1 시작 API

기존 endpoint는 유지하되 의미를 recording 기준으로 바꾼다.

- `POST /api/v1/streams/register`

request:

```json
{
  "repository_id": "uuid",
  "device_type": "meta_glasses_android"
}
```

response:

```json
{
  "recording_session_id": "uuid",
  "repository_id": "uuid",
  "repository_name": "daily_kitchen",
  "rtmp_url": "rtmp://host:1935/live/daily_kitchen?user=alice&pass=jwt",
  "status": "pending"
}
```

### 10.2 stop API

신규 endpoint:

- `POST /api/v1/recordings/:recordingSessionId/stop`

request:

```json
{
  "reason": "USER_STOP"
}
```

response:

```json
{
  "recording_session_id": "uuid",
  "status": "stop_requested"
}
```

처리:

- `RecordingSession.status=STOP_REQUESTED`
- `stopRequestedAt` 기록
- Redis live cache에도 `STOP_REQUESTED` 반영
- 이 API는 stream 종료 의도만 기록한다
- 실제 종료 확정은 `stream-not-ready` hook에서 처리한다

### 10.3 recording 상태 조회 API

- `GET /api/v1/recordings/:recordingSessionId`

response:

```json
{
  "id": "uuid",
  "status": "FINALIZING",
  "end_reason": "USER_STOP",
  "segment_count": 1,
  "video_id": null,
  "created_at": "2026-03-30T10:00:00.000Z",
  "ready_at": "2026-03-30T10:00:03.000Z",
  "not_ready_at": "2026-03-30T10:15:10.000Z",
  "finalized_at": null
}
```

이 endpoint는 Android 또는 dashboard에서 “저장 중 / 처리 중 / 완료” 표시용으로 사용한다.

## 11. Worker 설계

현재 [video-processing.worker.ts](/home/dennis0405/ego-flow/ego-flow-server/backend/src/workers/video-processing.worker.ts)는 raw 파일 1개를 입력으로 가정한다.  
새 구조에서는 worker가 먼저 recording의 segment를 정리해야 한다.

### 11.1 새 queue payload

```ts
interface RecordingFinalizeJobData {
  recordingSessionId: string;
  videoId: string;
  repositoryId: string;
  ownerId: string;
  repoName: string;
  targetDirectory: string;
}
```

### 11.2 worker 절차

1. `RecordingSession` 조회
2. `RecordingSegment(status=COMPLETED)` 목록 조회
3. segment가 0개면 실패 처리
4. segment가 1개면 해당 raw path를 입력 raw로 사용
5. segment가 2개 이상이면 concat/merge로 `merged raw` 생성
6. merged raw 기준으로 기존 인코딩 파이프라인 재사용
7. `Video` metadata 및 output path 업데이트
8. `RecordingSession.status=COMPLETED`
9. `finalizedAt` 기록

### 11.3 실패 시 처리

- worker 실패 -> `RecordingSession.status=FAILED`
- `Video.status=FAILED`
- `errorMessage` 기록

## 12. 서비스별 책임 재구성

### 12.1 recording-session.service.ts

새 서비스로 분리하는 것을 권장한다.

책임:

- register 처리
- live pointer 생성/삭제
- stop 요청 처리
- hook 기반 상태 전이
- finalize enqueue 조건 판정

### 12.2 segment.service.ts

책임:

- segment create / complete upsert
- sequence 부여
- orphan segment 방지

### 12.3 processing.service.ts

현재 [processing.service.ts](/home/dennis0405/ego-flow/ego-flow-server/backend/src/services/processing.service.ts)는 `VideoProcessingJobData` 기준이다.  
이를 `RecordingFinalizeJobData` 기준으로 변경하거나, 최소한 별도 queue service를 추가한다.

## 13. Android 변경사항

대상:

- [StreamViewModel.kt](/home/dennis0405/ego-flow/ego-flow-app/samples/CameraAccessAndroid/app/src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/stream/StreamViewModel.kt)

변경 내용:

1. register 응답에서 `recording_session_id` 저장
2. `activePublishSession`에 `recordingSessionId` 필드 추가
3. stop 시 `DELETE /streams/:repositoryId` 대신 `POST /recordings/:recordingSessionId/stop`
4. glasses 촬영 종료 이벤트도 동일 stop API로 연결
5. 필요 시 recording 상태 polling 추가

## 14. 구현 순서

1. Prisma schema에 `RecordingSession`, `RecordingSegment`, `Video.recordingSessionId` 추가
2. migration 생성
3. MediaMTX hook wrapper 및 endpoint 4개 추가
4. register 응답에 `recording_session_id` 추가
5. session logic을 recording-session 중심으로 재작성
6. stop API를 session-id 기준으로 추가
7. segment complete에서 `Video` 즉시 생성하는 로직 제거
8. finalize worker 구현
9. Android stop/start 연동 수정
10. 기존 `sessionId` 기반 잔존 코드 제거

## 15. 완료 기준

- 사용자 stop 1회당 final `Video`는 정확히 1개만 생성된다.
- segment가 여러 개 생겨도 final `Video`는 1개다.
- 앱 크래시 또는 네트워크 단절 후에도 `RecordingSession`이 `FINALIZING`, `FAILED`, `ABORTED` 중 하나로 수렴한다.
- `GET /streams/active`는 현재 `STREAMING`인 recording만 보여준다.
- 마지막 segment complete webhook이 stop 이후에 와도 동일 recording에 귀속된다.

## 16. 명확한 이벤트 의미

이 리팩터링에서 각 이벤트의 의미는 아래처럼 분리된다.

- `POST /streams/register`
  - recording 생성
- publish auth
  - RTMP 송출 권한 승인
- `stream-ready`
  - 실제 송출 시작 확인
- `POST /recordings/:id/stop`
  - 사용자의 종료 의도
- `stream-not-ready`
  - 실제 송출 종료 확인
- `recording-segment-complete`
  - raw 저장 조각 완료
- finalize worker
  - recording 전체를 final video 1개로 확정

즉 `stop 요청`과 `recording 완료`는 UX상 연속된 하나의 흐름이지만, 시스템 설계상으로는 반드시 분리해서 다뤄야 한다.
