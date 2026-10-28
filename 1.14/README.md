# docker-archery:1.14

Archery v1.14.0 应用镜像：supervisord 作 PID 1，托管 gunicorn（0.0.0.0:8888）与 django-q `qcluster`。
**不含 nginx**：静态文件由应用启动时 `collectstatic` 写入 `/opt/archery/static`，部署侧 nginx 容器只读挂载同一卷。

## 组成

| 层 | 内容 |
|---|---|
| 基座 | `sxc654/docker-python:3.11` = `python:3.11-bullseye` + build-essential/pkg-config + mysqlclient/python-ldap/pyodbc 头 + archive.debian.org 源 |
| 外部客户端 | 随仓 `setup.sh`（与上游 v1.14.0 `src/docker/setup.sh` 一致）装入：Oracle InstantClient 19.21、msodbc18、percona-toolkit、mongo shell、SOAR 0.11.0、SQLAdvisor 2.1、my2sql；同时创建 `/opt/venv4archery` |
| 上游源码 | `Archery-1.14.0.tar.gz`（11.4 MB，sha256 `3a96bdf3…26ae3`）解压到 `/opt/archery` |
| Python 依赖 | `/opt/venv4archery`（`requirements.txt` + `redis>=4.1.0` 覆盖） |
| 运行时 | `mariadb-client`（`manage.py dbshell` 用）；构建末尾 `purge build-essential` + `autoremove` 收敛体积 |
| 入口 | `docker-entrypoint.sh`（collectstatic → supervisord）+ `supervisord.conf`（gunicorn/qcluster） |

## 构建分层

**先装工具、后解压源码**，升级 Archery 源码不会触发工具层重建：

1. `COPY setup.sh` → 安装外部工具 + 创建 venv（缓存层与源码无关）
2. `COPY Archery-1.14.0.tar.gz` → sha256 校验 → 解压
3. `pip install` 应用依赖
4. 运行时归位（插件二进制）→ 收敛体积 → 构建期自检

## 与上游 `hhyo/archery:v1.14.0` 的差异

| # | 差异 | 原因 |
|---|---|---|
| 1 | 基座换 `sxc654/docker-python:3.11` | 上游锁 2023-11 的 `hhyo/archery-base:sha-d8159f4`，无法重建/打补丁 |
| 2 | 源码包随仓 + `sha256sum -c`，先装工具后解压 | 构建可复现、不依赖 codeload；工具层独立缓存 |
| 3 | **去掉 nginx**，gunicorn 监听 `0.0.0.0:8888` | 反向代理交给部署侧独立 nginx 容器（可换证书/域名/限流不动镜像） |
| 4 | 自有 entrypoint + supervisord，替代上游 `startup.sh`（含 nginx） | 单容器单职责；supervisord 作 PID 1 + 日志直出，`docker stop` 优雅退出 |
| 5 | 新增 `HEALTHCHECK`（`/login/`） | compose 的 `depends_on: service_healthy` 才有意义 |
| 6 | 保留 `curl` | 排障用；上游收尾把 curl 删了 |

其余（内部路径、环境变量、启动顺序、不自动建表）与上游一致。

## 构建

```bash
docker build -t sxc654/docker-archery:1.14 .
docker build --check .
```

构建期需要访问 GitHub Releases（SOAR/SQLAdvisor/my2sql）、Oracle、Microsoft（msodbc18）、
Percona 的下载源；正式构建在 GitHub Actions 完成。

`PIP_INDEX_URL` 默认官方 PyPI，需要换源时用 `--build-arg PIP_INDEX_URL=...`。

## 构建后验证

```bash
# 依赖/插件/入口自检（构建期已跑，可复跑）
docker run --rm --entrypoint bash sxc654/docker-archery:1.14 -c \
  '/opt/venv4archery/bin/python -c "import django, MySQLdb, ldap, pyodbc, cx_Oracle, gunicorn, redis, supervisor" && ls -l /opt/archery/src/plugins/{soar,sqladvisor,my2sql}'

# 缺必需环境变量时应立即失败（预期非 0 退出）
docker run --rm sxc654/docker-archery:1.14
```

完整链路（MySQL/Redis/nginx）见部署仓 `docker-archery/docker-compose.yml`。

## 已知限制

- **仅 amd64**：所有外部客户端为 amd64 二进制，arm64 需自行替换
- **构建需外网**：8 个外部制品（Oracle/Mongo/msodbc/Percona/GitHub releases）+ pip；源码包不联网
- **不自动建表**：`manage.py migrate` 需手动执行一次（部署仓 `scripts/init-db.sh`）
- Debian 11 基座已 EOL，包源走 `archive.debian.org`（冻结、无新安全更新）；升级 bookworm 时
  `setup.sh` 里 msodbc 的 `debian/11` 路径与 percona 源要同步改
- Oracle InstantClient 再分发受 OTN 许可约束（上游同样公开分发，此处仅沿用）

## 验证记录

- [ ] `docker build --check .` 零警告
- [ ] CI 实构建通过（含构建期自检）
- [ ] 部署仓 compose 起来后 `/login/` 200、`docker logs` 有 gunicorn/qcluster 输出
- [ ] `manage.py migrate` + 初始数据成功，`supervisorctl` 两进程 RUNNING
- [ ] 推送后 `docker pull sxc654/docker-archery:1.14` 复跑
