FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8080
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && groupadd --system --gid 10001 appgroup \
    && useradd --system --uid 10001 --gid 10001 --home-dir /app --shell /usr/sbin/nologin appuser
COPY --chown=10001:10001 main.py .
USER 10001:10001
EXPOSE 8080
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "1", "--threads", "4", "main:app"]
