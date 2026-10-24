FROM node:22-bookworm-slim AS admin
WORKDIR /build/admin_dashboard
COPY admin_dashboard/package*.json ./
RUN npm ci
COPY admin_dashboard/ ./
RUN npm run build

FROM python:3.12-slim-bookworm
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY backend/requirements-v1.txt /app/backend/requirements-v1.txt
RUN pip install --no-cache-dir -r backend/requirements-v1.txt
COPY backend/ /app/backend/
COPY --from=admin /build/admin_dashboard/dist /app/admin_dashboard/dist
RUN useradd --create-home appuser
USER appuser
EXPOSE 10000
CMD ["sh", "-c", "exec python -m uvicorn backend.main:app --host 0.0.0.0 --port ${PORT:-10000}"]
