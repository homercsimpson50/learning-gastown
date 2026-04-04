FROM python:3.12-slim
RUN pip install --no-cache-dir flask requests
COPY server.py /app/server.py
WORKDIR /app
EXPOSE 9999
CMD ["python", "server.py"]
