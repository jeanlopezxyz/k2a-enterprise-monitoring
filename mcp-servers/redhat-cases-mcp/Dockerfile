# Red Hat Cases MCP Server for K2A Enterprise Monitoring
FROM registry.access.redhat.com/ubi9/python-311:latest

LABEL maintainer="K2A Team"
LABEL description="Red Hat Cases & KB MCP Server for K2A auto-remediation"
LABEL io.k8s.display-name="K2A Red Hat Cases MCP"
LABEL io.openshift.tags="mcp,redhat,support,kb,k2a"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

USER 0

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chown -R 1001:0 /app && chmod -R g=u /app

USER 1001

EXPOSE 8000

ENV REDHAT_API_URL="https://api.access.redhat.com" \
    KB_SEARCH_ENABLED="true" \
    CASE_CREATION_ENABLED="true" \
    CASE_DEFAULT_SEVERITY="3" \
    CASE_DEFAULT_PRODUCT="OpenShift Container Platform" \
    MCP_TRANSPORT="stdio" \
    LOG_LEVEL="info"

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import redhat_cases_mcp; print('OK')" || exit 1

ENTRYPOINT ["python", "-m", "redhat_cases_mcp"]
CMD ["--transport", "stdio"]
