# docker-archery

[Archery](https://github.com/hhyo/Archery)（SQL 审核查询平台）的**应用镜像**仓库：
**一个版本子目录 = 一个镜像**，tag 推导为 `sxc654/docker-archery:<目录名>`（GitHub Actions 构建推 Docker Hub）。

镜像里**只有应用进程**：gunicorn（0.0.0.0:8888）+ django-q `qcluster`，不含 nginx、不含数据库。
nginx 与 MySQL/Redis 由部署侧（本工作区 `docker-archery/` 的 compose）提供，静态文件走共享卷。

| 目录 | 上游版本 | Docker Hub tag | 内容 |
|---|---|---|---|
| [`1.14/`](1.14/README.md) | Archery v1.14.0 | `sxc654/docker-archery:1.14` | gunicorn + qcluster（supervisord 托管），内置 SOAR / SQLAdvisor / my2sql / Oracle·MSSQL·Mongo 客户端 |

## 目录

```text
1.14/
├── Dockerfile                  # FROM sxc654/docker-python:3.11
├── Archery-1.14.0.tar.gz       # 上游源码包（sha256 校验后解压，构建期不抓 GitHub）
├── docker-entrypoint.sh        # collectstatic → supervisord（gunicorn + qcluster）
├── supervisord.conf            # 日志直出 stdout/stderr，PID 1 收 SIGTERM
└── README.md                   # 镜像细节、与上游差异、验证记录
.github/workflows/docker-image.yml   # 动态发现 <版本>/Dockerfile → build & push
```

## 构建（本地）

```bash
cd 1.14
docker build -t sxc654/docker-archery:1.14 .
docker build --check .          # 静态检查，零警告
```

构建期需要访问 GitHub Releases（SOAR/SQLAdvisor/my2sql）、Oracle、Microsoft（msodbc18）、
Percona 的下载源；正式构建在 GitHub Actions（美区直连）完成，本地网络受限时以 CI 结果为准。

**前置**：基座 `sxc654/docker-python:3.11` 必须先发布（来自 `docker-composer/python/3.11`）。
顺序：composer CI 出基座 → 本仓 CI 出应用镜像。

## 发布

push `master` 后 `.github/workflows/docker-image.yml` 动态发现 `*/Dockerfile`，
按 `sxc654/docker-archery:<目录名>` + `:latest` 推送；需仓库级 Secrets
`DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`。新增版本只建目录 + push，workflow 零改动；
手动触发可用 `targets` 指定目录。

## 运行约定

| 项 | 值 |
|---|---|
| 端口 | `8888`（gunicorn，容器内 HTTP） |
| 必需环境变量 | `SECRET_KEY`（≥32 位）、`DATABASE_URL`、`CACHE_URL`、`CSRF_TRUSTED_ORIGINS` |
| 静态文件 | 启动时 `collectstatic` 写入 `/opt/archery/static`，由 nginx 容器只读挂载同一卷 |
| 可持久化 | `/opt/archery/{logs,downloads,media/keys,sql/migrations}`、`/opt/archery/static` |
| 进程 | supervisord（PID 1）→ gunicorn + `manage.py qcluster`，日志直出 `docker logs` |
| 不自动建表 | 首次部署需执行 `manage.py migrate` + 初始数据（见部署仓 `scripts/init-db.sh`） |
