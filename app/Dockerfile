# Multi-stage build for a lightweight, secure production image
# Stage 1: Install dependencies
FROM python:3.12-slim-bookworm AS dependencies

# Install system dependencies only if needed (none required for this app)
# Set working directory for dependency installation
WORKDIR /install

# Copy and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Stage 2: Final runtime image
FROM python:3.12-slim-bookworm

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Set environment variables
# Note: TABLE_NAME is set at runtime by ECS task definition, not at build time
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH=/home/appuser/.local/bin:$PATH

# Set working directory
WORKDIR /app

# Copy installed dependencies from build stage
COPY --from=dependencies /install /home/appuser/.local

# Copy application source code
# Cache-busting build arg ensures code is always fresh in CI
ARG BUILD_ID
ENV BUILD_ID=${BUILD_ID}
COPY src/ ./src

# Change ownership to non-root user
RUN chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Expose the application port
EXPOSE 8080

# Health check for container orchestration (ALB target group also monitors /healthz endpoint)
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=2 \
    CMD python -c "import http.client; conn = http.client.HTTPConnection('localhost', 8080); conn.request('GET', '/healthz'); r = conn.getresponse(); exit(0 if r.status == 200 else 1)" || exit 1

# Run the FastAPI application with uvicorn
# Using --host 0.0.0.0 to bind to all interfaces
# Using --port 8080 as specified in requirements
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
