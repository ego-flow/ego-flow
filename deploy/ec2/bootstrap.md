# EC2 Bootstrap

이 문서는 빈 EC2 서버를 EgoFlow production 배포 대상으로 준비하는 최소 절차를 정리한다.

## Required State

- Docker Engine + Docker Compose v2
- deploy user의 Docker 실행 권한
- `/opt/egoflow/repo`
- `/opt/egoflow/data`
- `/opt/egoflow/config`
- `/opt/egoflow/releases`

## Checklist

1. Docker 설치
2. deploy user를 `docker` 그룹에 추가
3. `/opt/egoflow/data/{postgres,redis,raw,datasets}` 생성
4. `/opt/egoflow/config` 생성
5. `/opt/egoflow/releases` 생성
6. `/opt/egoflow/repo`에 저장소 clone
7. GHCR read token 준비

## Example

```bash
sudo mkdir -p /opt/egoflow/data/postgres
sudo mkdir -p /opt/egoflow/data/redis
sudo mkdir -p /opt/egoflow/data/raw
sudo mkdir -p /opt/egoflow/data/datasets
sudo mkdir -p /opt/egoflow/config
sudo mkdir -p /opt/egoflow/releases
sudo chown -R "$USER":"$USER" /opt/egoflow

git clone <repo-url> /opt/egoflow/repo
```
