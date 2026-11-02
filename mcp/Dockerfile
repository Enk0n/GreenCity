FROM python:3.11-slim
WORKDIR /app

RUN pip install --no-cache-dir "mcp[cli]<2" psycopg2-binary

COPY server.py /app/server.py

ENTRYPOINT ["python", "server.py"]