# syntax=docker/dockerfile:1.7
# sxc654/docker-archery:1.14 —— Archery（SQL 审核查询平台）v1.14.0 应用镜像
#
# 定位：只跑应用进程（gunicorn + django-q qcluster），不含 nginx、不含数据库。
#   nginx 由部署侧独立容器提供（见 docker-archery 部署仓），静态文件走共享卷：
#     应用容器 collectstatic → /opt/archery/static（卷） → nginx 容器只读挂载 /static
#
# 基座：sxc654/docker-python:3.11（见 docker-composer/python/3.11；Python 3.11 是 Django 4.1 上限）
#
# 构建分层（先装工具、后解压源码：升级 Archery 源码不触发工具层重建）：
#   1) setup.sh（随仓，与上游 v1.14.0 的 src/docker/setup.sh 一致）装外部客户端 + venv4archery
#   2) 解压 Archery-1.14.0.tar.gz（sha256 校验）
#   3) pip 安装应用依赖
#   4) 运行时归位 + 收敛体积
FROM sxc654/docker-python:3.11

ENV TZ=Asia/Shanghai \
    SOAR_VERSION=0.11.0 \
    GUNICORN_WORKERS=4 \
    GUNICORN_TIMEOUT=600

WORKDIR /opt

# 1) 1.14 需要的外部工具（Oracle InstantClient / msodbc18 / percona-toolkit / mongo shell /
#    SOAR / SQLAdvisor / my2sql）+ /opt/venv4archery。
#    必须在 /opt 下执行：脚本用相对路径落 venv4archery 与 soar/sqladvisor/my2sql。
COPY setup.sh /opt/setup.sh
RUN set -eux; \
    chmod +x /opt/setup.sh; \
    /opt/setup.sh; \
    rm -f /opt/setup.sh; \
    rm -rf /var/lib/apt/lists/*

# 2) 解压源码（校验失败即构建失败）
COPY Archery-1.14.0.tar.gz /tmp/archery.tgz
RUN set -eux; \
    echo "3a96bdf3d3d64c2c192e3bc83251356180aeeb86354934db09e2bfbeddd26ae3  /tmp/archery.tgz" | sha256sum -c -; \
    mkdir -p /opt/archery; \
    tar -xzf /tmp/archery.tgz -C /opt/archery --strip-components=1; \
    rm -f /tmp/archery.tgz

# 3) 应用依赖；redis 按上游覆盖（requirements.txt 钉的是 3.5.3）
ARG PIP_INDEX_URL=https://pypi.org/simple
RUN --mount=type=cache,target=/root/.cache/pip \
    set -eux; \
    /opt/venv4archery/bin/pip install -i "$PIP_INDEX_URL" -r /opt/archery/requirements.txt; \
    /opt/venv4archery/bin/pip install -i "$PIP_INDEX_URL" "redis>=4.1.0"

# 4) 运行时依赖 + 插件二进制归位 + 收敛体积
#   - mariadb-client：manage.py dbshell 用（初始化脚本）
#   - build-essential 装完依赖后即可移除（已编译产物不再需要 gcc；dev 头文件保留，
#     其运行时库 libmariadb3/libldap/unixodbc 仍被 venv 里的扩展依赖）
RUN set -eux; \
    apt-get update; \
    apt-get install -yq --no-install-recommends mariadb-client; \
    mv /opt/sqladvisor /opt/soar /opt/my2sql /opt/archery/src/plugins/; \
    apt-get purge -y build-essential; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /root/.cache

# 容器入口与进程管理（本项目自带，不依赖上游 startup.sh）
COPY docker-entrypoint.sh supervisord.conf /opt/archery/docker/
RUN chmod +x /opt/archery/docker/docker-entrypoint.sh

# 构建期自检：Python 依赖 / 插件二进制 / 入口脚本，缺一即构建失败
RUN set -eux; \
    /opt/venv4archery/bin/python -c "import django, MySQLdb, ldap, pyodbc, cx_Oracle, gunicorn, redis, supervisor"; \
    /opt/venv4archery/bin/supervisord --version > /dev/null; \
    test -x /opt/archery/src/plugins/soar; \
    test -x /opt/archery/src/plugins/sqladvisor; \
    test -x /opt/archery/src/plugins/my2sql; \
    test -x /opt/archery/docker/docker-entrypoint.sh; \
    echo "archery image check OK"

EXPOSE 8888

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8888/login/', timeout=3)"]

ENTRYPOINT ["/opt/archery/docker/docker-entrypoint.sh"]
