#!/usr/bin/env python3
"""
Red Hat Cases & Knowledge Base MCP Server for K2A Enterprise Monitoring

Provides tools for:
- Searching Red Hat Knowledge Base for solutions
- Creating support cases
- Managing existing cases
- Getting case status and updates
"""

import argparse
import asyncio
import os
from datetime import datetime
from typing import Any, Optional

import httpx
from fastmcp import FastMCP

# Configuration
REDHAT_API_URL = os.getenv("REDHAT_API_URL", "https://api.access.redhat.com")
REDHAT_API_TOKEN = os.getenv("REDHAT_API_TOKEN", "")
REDHAT_OFFLINE_TOKEN = os.getenv("REDHAT_OFFLINE_TOKEN", "")
KB_SEARCH_ENABLED = os.getenv("KB_SEARCH_ENABLED", "true").lower() == "true"
CASE_CREATION_ENABLED = os.getenv("CASE_CREATION_ENABLED", "true").lower() == "true"
CASE_DEFAULT_SEVERITY = os.getenv("CASE_DEFAULT_SEVERITY", "3")
CASE_DEFAULT_PRODUCT = os.getenv("CASE_DEFAULT_PRODUCT", "OpenShift Container Platform")
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")

# SSO Token URL
SSO_TOKEN_URL = "https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token"

# Create MCP server
mcp = FastMCP(
    "Red Hat Cases MCP Server",
    dependencies=["httpx", "beautifulsoup4"],
)

# Token cache
_access_token: Optional[str] = None
_token_expires_at: Optional[datetime] = None


async def get_access_token() -> str:
    """Get or refresh the access token using the offline token."""
    global _access_token, _token_expires_at

    # Use direct API token if available
    if REDHAT_API_TOKEN:
        return REDHAT_API_TOKEN

    # Check if token is still valid
    if _access_token and _token_expires_at and datetime.utcnow() < _token_expires_at:
        return _access_token

    # Refresh token using offline token
    if not REDHAT_OFFLINE_TOKEN:
        raise ValueError("No REDHAT_API_TOKEN or REDHAT_OFFLINE_TOKEN configured")

    async with httpx.AsyncClient() as client:
        response = await client.post(
            SSO_TOKEN_URL,
            data={
                "grant_type": "refresh_token",
                "client_id": "rhsm-api",
                "refresh_token": REDHAT_OFFLINE_TOKEN,
            },
        )
        response.raise_for_status()
        token_data = response.json()

        _access_token = token_data["access_token"]
        # Set expiry 60 seconds before actual expiry
        _token_expires_at = datetime.utcnow()

        return _access_token


async def redhat_api_request(
    method: str,
    endpoint: str,
    json_data: dict = None,
    params: dict = None,
) -> dict:
    """Make a request to the Red Hat API."""
    token = await get_access_token()

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    async with httpx.AsyncClient(timeout=60.0) as client:
        url = f"{REDHAT_API_URL}{endpoint}"

        if method == "GET":
            response = await client.get(url, headers=headers, params=params)
        elif method == "POST":
            response = await client.post(url, headers=headers, json=json_data)
        elif method == "PUT":
            response = await client.put(url, headers=headers, json=json_data)
        else:
            raise ValueError(f"Unsupported method: {method}")

        response.raise_for_status()
        return response.json() if response.content else {}


@mcp.tool()
async def kb_search(
    query: str,
    product: str = None,
    limit: int = 10,
    doc_type: str = "solution",
) -> dict:
    """
    Search Red Hat Knowledge Base for solutions.

    Args:
        query: Search query (e.g., "pod crashloopbackoff memory")
        product: Product to filter by (default: OpenShift Container Platform)
        limit: Maximum number of results (default: 10)
        doc_type: Document type - "solution", "article", "errata" (default: solution)

    Returns:
        List of KB articles matching the query
    """
    if not KB_SEARCH_ENABLED:
        return {"error": "KB search is disabled"}

    if not product:
        product = CASE_DEFAULT_PRODUCT

    params = {
        "q": query,
        "rows": limit,
        "documentKind": doc_type,
    }

    if product:
        params["product"] = product

    try:
        # Use Hydra search API
        result = await redhat_api_request(
            "GET",
            "/hydra/rest/search/kcs",
            params=params,
        )

        articles = []
        for doc in result.get("response", {}).get("docs", []):
            articles.append({
                "id": doc.get("id"),
                "title": doc.get("title"),
                "abstract": doc.get("abstract"),
                "url": doc.get("view_uri"),
                "documentKind": doc.get("documentKind"),
                "lastModified": doc.get("lastModifiedDate"),
                "severity": doc.get("severity"),
                "solution": doc.get("solution_text", ""),
            })

        return {
            "total": result.get("response", {}).get("numFound", 0),
            "query": query,
            "product": product,
            "articles": articles,
        }

    except Exception as e:
        return {
            "error": str(e),
            "query": query,
            "articles": [],
        }


@mcp.tool()
async def kb_get_article(article_id: str) -> dict:
    """
    Get full details of a Knowledge Base article.

    Args:
        article_id: KB article ID (e.g., "123456")

    Returns:
        Full article content including solution steps
    """
    if not KB_SEARCH_ENABLED:
        return {"error": "KB search is disabled"}

    try:
        result = await redhat_api_request(
            "GET",
            f"/hydra/rest/articles/{article_id}",
        )

        return {
            "id": result.get("id"),
            "title": result.get("title"),
            "abstract": result.get("abstract"),
            "issue": result.get("issue"),
            "environment": result.get("environment"),
            "resolution": result.get("resolution"),
            "rootCause": result.get("root_cause"),
            "diagnosticSteps": result.get("diagnostic_steps"),
            "url": result.get("view_uri"),
            "product": result.get("product"),
            "version": result.get("version"),
            "lastModified": result.get("lastModifiedDate"),
        }

    except Exception as e:
        return {"error": str(e), "article_id": article_id}


@mcp.tool()
async def case_create(
    summary: str,
    description: str,
    severity: str = None,
    product: str = None,
    version: str = None,
    cluster_id: str = None,
) -> dict:
    """
    Create a new Red Hat support case.

    Args:
        summary: Brief summary of the issue
        description: Detailed description including steps to reproduce
        severity: Case severity - "1" (Urgent), "2" (High), "3" (Normal), "4" (Low)
        product: Product name (default: OpenShift Container Platform)
        version: Product version (e.g., "4.14")
        cluster_id: OpenShift cluster ID for automatic attachment

    Returns:
        Created case details including case number
    """
    if not CASE_CREATION_ENABLED:
        return {"error": "Case creation is disabled"}

    if not severity:
        severity = CASE_DEFAULT_SEVERITY
    if not product:
        product = CASE_DEFAULT_PRODUCT

    case_data = {
        "summary": summary,
        "description": description,
        "severity": severity,
        "product": product,
    }

    if version:
        case_data["version"] = version

    # Add K2A signature
    case_data["description"] += "\n\n---\nCase created automatically by K2A Enterprise Monitoring Agent"

    try:
        result = await redhat_api_request(
            "POST",
            "/support/v1/cases",
            json_data=case_data,
        )

        return {
            "status": "success",
            "caseNumber": result.get("caseNumber"),
            "caseId": result.get("id"),
            "summary": summary,
            "severity": severity,
            "product": product,
            "url": f"https://access.redhat.com/support/cases/#/case/{result.get('caseNumber')}",
        }

    except Exception as e:
        return {
            "status": "error",
            "error": str(e),
            "summary": summary,
        }


@mcp.tool()
async def case_get(case_number: str) -> dict:
    """
    Get details of an existing support case.

    Args:
        case_number: Red Hat case number (e.g., "03123456")

    Returns:
        Case details including status and comments
    """
    try:
        result = await redhat_api_request(
            "GET",
            f"/support/v1/cases/{case_number}",
        )

        return {
            "caseNumber": result.get("caseNumber"),
            "summary": result.get("summary"),
            "description": result.get("description"),
            "severity": result.get("severity"),
            "status": result.get("status"),
            "product": result.get("product"),
            "version": result.get("version"),
            "createdDate": result.get("createdDate"),
            "lastModifiedDate": result.get("lastModifiedDate"),
            "owner": result.get("owner"),
            "url": f"https://access.redhat.com/support/cases/#/case/{case_number}",
        }

    except Exception as e:
        return {"error": str(e), "caseNumber": case_number}


@mcp.tool()
async def case_add_comment(
    case_number: str,
    comment: str,
    is_public: bool = True,
) -> dict:
    """
    Add a comment to an existing support case.

    Args:
        case_number: Red Hat case number
        comment: Comment text to add
        is_public: Whether the comment should be public (default: True)

    Returns:
        Status of the comment addition
    """
    try:
        comment_data = {
            "text": comment,
            "public": is_public,
        }

        await redhat_api_request(
            "POST",
            f"/support/v1/cases/{case_number}/comments",
            json_data=comment_data,
        )

        return {
            "status": "success",
            "caseNumber": case_number,
            "message": "Comment added successfully",
        }

    except Exception as e:
        return {
            "status": "error",
            "error": str(e),
            "caseNumber": case_number,
        }


@mcp.tool()
async def case_list(
    status: str = "open",
    limit: int = 20,
) -> dict:
    """
    List support cases.

    Args:
        status: Case status filter - "open", "closed", "all" (default: open)
        limit: Maximum number of cases to return

    Returns:
        List of cases matching the criteria
    """
    try:
        params = {
            "limit": limit,
        }

        if status != "all":
            params["status"] = status

        result = await redhat_api_request(
            "GET",
            "/support/v1/cases",
            params=params,
        )

        cases = []
        for case in result.get("cases", []):
            cases.append({
                "caseNumber": case.get("caseNumber"),
                "summary": case.get("summary"),
                "severity": case.get("severity"),
                "status": case.get("status"),
                "product": case.get("product"),
                "createdDate": case.get("createdDate"),
                "lastModifiedDate": case.get("lastModifiedDate"),
            })

        return {
            "total": len(cases),
            "status_filter": status,
            "cases": cases,
        }

    except Exception as e:
        return {"error": str(e), "cases": []}


@mcp.tool()
async def case_escalate(
    case_number: str,
    reason: str,
) -> dict:
    """
    Request escalation for a support case.

    Args:
        case_number: Red Hat case number
        reason: Reason for escalation request

    Returns:
        Status of the escalation request
    """
    # Add escalation comment
    escalation_comment = f"""
ESCALATION REQUESTED

Reason: {reason}

Requested by: K2A Enterprise Monitoring Agent
Time: {datetime.utcnow().isoformat()}Z

Please prioritize this case as automatic remediation has been attempted without success.
"""

    return await case_add_comment(
        case_number=case_number,
        comment=escalation_comment,
        is_public=True,
    )


@mcp.tool()
async def redhat_health() -> dict:
    """
    Check Red Hat API connectivity and authentication.

    Returns:
        Health status of the Red Hat API connection
    """
    try:
        token = await get_access_token()
        token_valid = bool(token)

        return {
            "healthy": token_valid,
            "api_url": REDHAT_API_URL,
            "kb_enabled": KB_SEARCH_ENABLED,
            "case_creation_enabled": CASE_CREATION_ENABLED,
            "default_product": CASE_DEFAULT_PRODUCT,
        }

    except Exception as e:
        return {
            "healthy": False,
            "error": str(e),
            "api_url": REDHAT_API_URL,
        }


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(description="Red Hat Cases MCP Server")
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
