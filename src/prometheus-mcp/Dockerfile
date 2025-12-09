# Prometheus MCP Server for K2A Enterprise Monitoring
# Based on MCP Python SDK
FROM registry.access.redhat.com/ubi9/python-311:latest

LABEL maintainer="K2A Team"
LABEL description="Prometheus MCP Server for K2A auto-remediation"
LABEL io.k8s.display-name="K2A Prometheus MCP"
LABEL io.openshift.tags="mcp,prometheus,monitoring,k2a"

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Switch to root to install dependencies
USER 0

# Create app directory
WORKDIR /app

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Create non-root user for OpenShift compatibility
RUN chown -R 1001:0 /app && \
    chmod -R g=u /app

# Switch to non-root user
USER 1001

# Expose port for HTTP transport (optional)
EXPOSE 8000

# Default environment variables
ENV PROMETHEUS_URL="http://prometheus-k8s.openshift-monitoring.svc.cluster.local:9090" \
    MCP_TRANSPORT="stdio" \
    LOG_LEVEL="info"

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import prometheus_mcp; print('OK')" || exit 1

# Entry point
ENTRYPOINT ["python", "-m", "prometheus_mcp"]
CMD ["--transport", "stdio"]
