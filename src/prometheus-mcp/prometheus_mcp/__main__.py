#!/usr/bin/env python3
"""
Prometheus MCP Server for K2A Enterprise Monitoring

Provides tools for:
- Querying Prometheus metrics (instant and range queries)
- Retrieving active alerts
- Getting alert rules
- Checking Prometheus health and targets
"""

import argparse
import asyncio
import os
from datetime import datetime, timedelta
from typing import Any

import httpx
from fastmcp import FastMCP

# Configuration from environment
PROMETHEUS_URL = os.getenv("PROMETHEUS_URL", "http://localhost:9090")
PROMETHEUS_TOKEN = os.getenv("PROMETHEUS_TOKEN", "")
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")

# Create MCP server
mcp = FastMCP(
    "Prometheus MCP Server",
    dependencies=["httpx", "prometheus-api-client"],
)


def get_headers() -> dict[str, str]:
    """Get HTTP headers for Prometheus API requests."""
    headers = {"Content-Type": "application/json"}
    if PROMETHEUS_TOKEN:
        headers["Authorization"] = f"Bearer {PROMETHEUS_TOKEN}"
    return headers


async def prometheus_request(endpoint: str, params: dict[str, Any] = None) -> dict:
    """Make a request to the Prometheus API."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        url = f"{PROMETHEUS_URL}/api/v1/{endpoint}"
        response = await client.get(url, params=params, headers=get_headers())
        response.raise_for_status()
        return response.json()


@mcp.tool()
async def prometheus_query(query: str, time: str = None) -> dict:
    """
    Execute an instant PromQL query against Prometheus.

    Args:
        query: PromQL query string (e.g., 'up{job="kubernetes-nodes"}')
        time: Optional RFC3339 or Unix timestamp for the query (default: now)

    Returns:
        Query result with metric values
    """
    params = {"query": query}
    if time:
        params["time"] = time

    result = await prometheus_request("query", params)
    return {
        "status": result.get("status"),
        "data": result.get("data", {}),
        "resultType": result.get("data", {}).get("resultType"),
        "result": result.get("data", {}).get("result", []),
    }


@mcp.tool()
async def prometheus_query_range(
    query: str,
    start: str = None,
    end: str = None,
    step: str = "1m",
    duration_minutes: int = 60,
) -> dict:
    """
    Execute a range PromQL query against Prometheus.

    Args:
        query: PromQL query string
        start: Start time (RFC3339 or Unix timestamp). Default: duration_minutes ago
        end: End time (RFC3339 or Unix timestamp). Default: now
        step: Query resolution step (e.g., '15s', '1m', '5m')
        duration_minutes: If start not provided, query last N minutes

    Returns:
        Query result with time series data
    """
    now = datetime.utcnow()

    if not end:
        end = now.isoformat() + "Z"
    if not start:
        start = (now - timedelta(minutes=duration_minutes)).isoformat() + "Z"

    params = {
        "query": query,
        "start": start,
        "end": end,
        "step": step,
    }

    result = await prometheus_request("query_range", params)
    return {
        "status": result.get("status"),
        "resultType": result.get("data", {}).get("resultType"),
        "result": result.get("data", {}).get("result", []),
    }


@mcp.tool()
async def prometheus_alerts() -> dict:
    """
    Get all active alerts from Prometheus.

    Returns:
        List of firing and pending alerts with labels and annotations
    """
    result = await prometheus_request("alerts")
    alerts = result.get("data", {}).get("alerts", [])

    # Categorize alerts
    firing = [a for a in alerts if a.get("state") == "firing"]
    pending = [a for a in alerts if a.get("state") == "pending"]

    return {
        "status": result.get("status"),
        "total": len(alerts),
        "firing_count": len(firing),
        "pending_count": len(pending),
        "firing": firing,
        "pending": pending,
    }


@mcp.tool()
async def prometheus_rules() -> dict:
    """
    Get all alerting and recording rules from Prometheus.

    Returns:
        List of rule groups with their rules
    """
    result = await prometheus_request("rules")
    groups = result.get("data", {}).get("groups", [])

    # Summarize rules
    alerting_rules = []
    recording_rules = []

    for group in groups:
        for rule in group.get("rules", []):
            rule_info = {
                "name": rule.get("name"),
                "group": group.get("name"),
                "query": rule.get("query"),
                "health": rule.get("health"),
            }
            if rule.get("type") == "alerting":
                rule_info["state"] = rule.get("state")
                rule_info["labels"] = rule.get("labels", {})
                rule_info["annotations"] = rule.get("annotations", {})
                alerting_rules.append(rule_info)
            else:
                recording_rules.append(rule_info)

    return {
        "status": result.get("status"),
        "alerting_rules_count": len(alerting_rules),
        "recording_rules_count": len(recording_rules),
        "alerting_rules": alerting_rules,
        "recording_rules": recording_rules,
    }


@mcp.tool()
async def prometheus_targets() -> dict:
    """
    Get all scrape targets and their health status.

    Returns:
        List of active and dropped targets with health information
    """
    result = await prometheus_request("targets")
    data = result.get("data", {})

    active = data.get("activeTargets", [])
    dropped = data.get("droppedTargets", [])

    # Summarize health
    healthy = [t for t in active if t.get("health") == "up"]
    unhealthy = [t for t in active if t.get("health") != "up"]

    return {
        "status": result.get("status"),
        "active_count": len(active),
        "healthy_count": len(healthy),
        "unhealthy_count": len(unhealthy),
        "dropped_count": len(dropped),
        "unhealthy_targets": [
            {
                "job": t.get("labels", {}).get("job"),
                "instance": t.get("labels", {}).get("instance"),
                "health": t.get("health"),
                "lastError": t.get("lastError"),
            }
            for t in unhealthy
        ],
    }


@mcp.tool()
async def prometheus_metadata(metric: str = None, limit: int = 100) -> dict:
    """
    Get metadata for metrics.

    Args:
        metric: Optional metric name to filter (default: all metrics)
        limit: Maximum number of metrics to return

    Returns:
        Metric metadata including type, help text, and unit
    """
    params = {"limit": str(limit)}
    if metric:
        params["metric"] = metric

    result = await prometheus_request("metadata", params)
    return {
        "status": result.get("status"),
        "metadata": result.get("data", {}),
    }


@mcp.tool()
async def prometheus_health() -> dict:
    """
    Check Prometheus server health and readiness.

    Returns:
        Health status of the Prometheus server
    """
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            # Check health endpoint
            health_resp = await client.get(
                f"{PROMETHEUS_URL}/-/healthy", headers=get_headers()
            )
            healthy = health_resp.status_code == 200

            # Check ready endpoint
            ready_resp = await client.get(
                f"{PROMETHEUS_URL}/-/ready", headers=get_headers()
            )
            ready = ready_resp.status_code == 200

            # Get runtime info
            runtime = await prometheus_request("status/runtimeinfo")

            return {
                "healthy": healthy,
                "ready": ready,
                "url": PROMETHEUS_URL,
                "runtime": runtime.get("data", {}),
            }
        except Exception as e:
            return {
                "healthy": False,
                "ready": False,
                "url": PROMETHEUS_URL,
                "error": str(e),
            }


@mcp.tool()
async def prometheus_series(
    match: list[str], start: str = None, end: str = None
) -> dict:
    """
    Find time series matching label selectors.

    Args:
        match: List of series selectors (e.g., ['up{job="prometheus"}'])
        start: Start time for the search
        end: End time for the search

    Returns:
        List of matching time series
    """
    params = {"match[]": match}
    if start:
        params["start"] = start
    if end:
        params["end"] = end

    result = await prometheus_request("series", params)
    return {
        "status": result.get("status"),
        "series_count": len(result.get("data", [])),
        "series": result.get("data", []),
    }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Prometheus MCP Server")
    parser.add_argument(
        "--transport",
        choices=["stdio", "streamable-http"],
        default="stdio",
        help="Transport mechanism to use",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=8000,
        help="Port for HTTP transport",
    )
    args = parser.parse_args()

    if args.transport == "streamable-http":
        # Use HTTP transport with host/port configuration
        mcp.run(transport="http", host="0.0.0.0", port=args.port)
    else:
        mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
