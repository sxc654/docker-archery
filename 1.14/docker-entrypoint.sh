#!/usr/bin/env bash
# 容器入口：收集静态文件 → supervisord（gunicorn + qcluster）作 PID 1
# 静态文件写入 /opt/archery/static，部署侧 nginx 容器只读挂载同一卷
set -euo pipefail

cd /opt/archery
export DJANGO_SETTINGS_MODULE="${DJANGO_SETTINGS_MODULE:-archery.settings}"

# 必需配置缺失时尽早失败（settings.py: SECRET_KEY = env("SECRET_KEY") 无默认值）
: "${SECRET_KEY:?SECRET_KEY 未设置（≥32 位），请通过环境变量注入}"
: "${DATABASE_URL:?DATABASE_URL 未设置，例：mysql://user:pass@host:3306/archery}"
: "${CACHE_URL:?CACHE_URL 未设置，例：redis://:pass@host:6379/0}"

echo "[entrypoint] collectstatic → /opt/archery/static"
/opt/venv4archery/bin/python manage.py collectstatic -v0 --noinput

echo "[entrypoint] start supervisord: gunicorn 0.0.0.0:8888 + qcluster"
exec /opt/venv4archery/bin/supervisord -c /opt/archery/docker/supervisord.conf
