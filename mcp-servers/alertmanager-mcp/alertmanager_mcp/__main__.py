#!/usr/bin/env python3
"""
AlertManager MCP Server for K2A Enterprise Monitoring

Provides tools for:
- Getting active alerts
- Creating and managing silences
- Acknowledging alerts
- Managing alert groups
"""

import argparse
import asyncio
import os
import uuid
from datetime import datetime, timedelta
from typing import Any

import httpx
from fastmcp import FastMCP

# Configuration
ALERTMANAGER_URL = os.getenv(
    "ALERTMANAGER_URL", "http://localhost:9093"
)
ALERTMANAGER_TOKEN = os.getenv("ALERTMANAGER_TOKEN", "")
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")

# Create MCP server
mcp = FastMCP(
    "AlertManager MCP Server",
    dependencies=["httpx"],
)


def get_headers() -> dict[str, str]:
    """Get HTTP headers for AlertManager API requests."""
    headers = {"Content-Type": "application/json"}
    if ALERTMANAGER_TOKEN:
        headers["Authorization"] = f"Bearer {ALERTMANAGER_TOKEN}"
    return headers


async def alertmanager_request(
    method: str, endpoint: str, json_data: dict = None
) -> dict:
    """Make a request to the AlertManager API."""
    async with httpx.AsyncClient(timeout=30.0) as client:
        url = f"{ALERTMANAGER_URL}/api/v2/{endpoint}"
        if method == "GET":
            response = await client.get(url, headers=get_headers())
        elif method == "POST":
            response = await client.post(
                url, json=json_data, headers=get_headers()
            )
        elif method == "DELETE":
            response = await client.delete(url, headers=get_headers())
        else:
            raise ValueError(f"Unsupported method: {method}")

        response.raise_for_status()

        if response.status_code == 204:
            return {"status": "success"}
        return response.json()


@mcp.tool()
async def alertmanager_alerts(
    active: bool = True,
    silenced: bool = False,
    inhibited: bool = False,
    filter_labels: dict[str, str] = None,
) -> dict:
    """
    Get alerts from AlertManager.

    Args:
        active: Include active alerts (default: True)
        silenced: Include silenced alerts (default: False)
        inhibited: Include inhibited alerts (default: False)
        filter_labels: Optional label filters (e.g., {"severity": "critical"})

    Returns:
        List of alerts matching the criteria
    """
    params = []
    if active:
        params.append("active=true")
    if silenced:
        params.append("silenced=true")
    if inhibited:
        params.append("inhibited=true")

    if filter_labels:
        for k, v in filter_labels.items():
            params.append(f"filter={k}={v}")

    endpoint = "alerts"
    if params:
        endpoint += "?" + "&".join(params)

    alerts = await alertmanager_request("GET", endpoint)

    # Categorize by severity
    critical = [
        a for a in alerts if a.get("labels", {}).get("severity") == "critical"
    ]
    warning = [
        a for a in alerts if a.get("labels", {}).get("severity") == "warning"
    ]
    info = [
        a for a in alerts if a.get("labels", {}).get("severity") not in ["critical", "warning"]
    ]

    return {
        "total": len(alerts),
        "critical_count": len(critical),
        "warning_count": len(warning),
        "info_count": len(info),
        "critical": critical,
        "warning": warning,
        "info": info,
    }


@mcp.tool()
async def alertmanager_alert_groups() -> dict:
    """
    Get alert groups from AlertManager.

    Returns:
        List of alert groups with their alerts
    """
    groups = await alertmanager_request("GET", "alerts/groups")
    return {
        "groups_count": len(groups),
        "groups": groups,
    }


@mcp.tool()
async def alertmanager_silences(active_only: bool = True) -> dict:
    """
    Get all silences from AlertManager.

    Args:
        active_only: Only return active silences (default: True)

    Returns:
        List of silences
    """
    silences = await alertmanager_request("GET", "silences")

    if active_only:
        now = datetime.utcnow()
        silences = [
            s for s in silences
            if s.get("status", {}).get("state") == "active"
        ]

    return {
        "total": len(silences),
        "silences": silences,
    }


@mcp.tool()
async def alertmanager_create_silence(
    matchers: list[dict[str, str]],
    duration_minutes: int = 60,
    created_by: str = "k2a-agent",
    comment: str = "Silence created by K2A auto-remediation",
) -> dict:
    """
    Create a new silence in AlertManager.

    Args:
        matchers: List of label matchers (e.g., [{"name": "alertname", "value": "HighCPU", "isRegex": false}])
        duration_minutes: Duration of the silence in minutes (default: 60)
        created_by: Name of the creator (default: k2a-agent)
        comment: Comment for the silence

    Returns:
        Created silence ID and details
    """
    now = datetime.utcnow()
    ends_at = now + timedelta(minutes=duration_minutes)

    silence_data = {
        "matchers": matchers,
        "startsAt": now.isoformat() + "Z",
        "endsAt": ends_at.isoformat() + "Z",
        "createdBy": created_by,
        "comment": comment,
    }

    result = await alertmanager_request("POST", "silences", silence_data)
    return {
        "status": "success",
        "silenceId": result.get("silenceID"),
        "startsAt": silence_data["startsAt"],
        "endsAt": silence_data["endsAt"],
        "matchers": matchers,
        "comment": comment,
    }


@mcp.tool()
async def alertmanager_delete_silence(silence_id: str) -> dict:
    """
    Delete (expire) a silence by ID.

    Args:
        silence_id: The ID of the silence to delete

    Returns:
        Status of the deletion
    """
    await alertmanager_request("DELETE", f"silence/{silence_id}")
    return {
        "status": "success",
        "silenceId": silence_id,
        "message": "Silence deleted successfully",
    }


@mcp.tool()
async def alertmanager_silence_alert(
    alertname: str,
    duration_minutes: int = 60,
    additional_matchers: list[dict[str, str]] = None,
    comment: str = None,
) -> dict:
    """
    Silence a specific alert by name.

    Args:
        alertname: Name of the alert to silence
        duration_minutes: Duration in minutes (default: 60)
        additional_matchers: Additional label matchers
        comment: Optional comment

    Returns:
        Created silence details
    """
    matchers = [
        {"name": "alertname", "value": alertname, "isRegex": False}
    ]

    if additional_matchers:
        matchers.extend(additional_matchers)

    if not comment:
        comment = f"Silencing alert '{alertname}' for {duration_minutes} minutes - K2A auto-remediation"

    return await alertmanager_create_silence(
        matchers=matchers,
        duration_minutes=duration_minutes,
        comment=comment,
    )


@mcp.tool()
async def alertmanager_receivers() -> dict:
    """
    Get all configured receivers.

    Returns:
        List of configured notification receivers
    """
    receivers = await alertmanager_request("GET", "receivers")
    return {
        "receivers_count": len(receivers),
        "receivers": receivers,
    }


@mcp.tool()
async def alertmanager_status() -> dict:
    """
    Get AlertManager status and configuration.

    Returns:
        AlertManager status information
    """
    status = await alertmanager_request("GET", "status")
    return {
        "cluster": status.get("cluster", {}),
        "config": status.get("config", {}),
        "uptime": status.get("uptime"),
        "versionInfo": status.get("versionInfo", {}),
    }


@mcp.tool()
async def alertmanager_health() -> dict:
    """
    Check AlertManager health.

    Returns:
        Health status
    """
    async with httpx.AsyncClient(timeout=10.0) as client:
        try:
            # Check health endpoint
            health_resp = await client.get(
                f"{ALERTMANAGER_URL}/-/healthy", headers=get_headers()
            )
            healthy = health_resp.status_code == 200

            # Check ready endpoint
            ready_resp = await client.get(
                f"{ALERTMANAGER_URL}/-/ready", headers=get_headers()
            )
            ready = ready_resp.status_code == 200

            return {
                "healthy": healthy,
                "ready": ready,
                "url": ALERTMANAGER_URL,
            }
        except Exception as e:
            return {
                "healthy": False,
                "ready": False,
                "url": ALERTMANAGER_URL,
                "error": str(e),
            }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="AlertManager MCP Server")
    parser.add_argument(
        "--transport",
        choices=["stdio", "streamable-http"],
        default="stdio",
        help="Transport mechanism",
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
