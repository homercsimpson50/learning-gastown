"""
Gas Town Gateway Sidecar — Token-proxying for external services.

Agents call this gateway instead of external APIs directly.
The gateway injects auth tokens server-side — agents never see credentials.

Endpoints:
  /github/<path>   — Proxy GitHub API calls
  /jira/<path>     — Proxy Jira API calls
  /slack/<method>  — Proxy Slack API calls
  /health          — Check which services are configured
"""

import os
import re
import logging
import urllib.parse

import requests
from flask import Flask, Response, request, jsonify

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s")

# Load secrets from sealed env file
SECRETS = {}
env_file = os.environ.get("SECRETS_FILE", "/secrets/secrets.env")
if os.path.exists(env_file):
    with open(env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, val = line.split("=", 1)
                SECRETS[key.strip()] = val.strip()

# Route configs
JIRA_ALLOWED_PROJECTS = set(
    p for p in os.environ.get("JIRA_ALLOWED_PROJECTS", "").split(",") if p
)
GITHUB_ALLOWED_REPOS = set(
    r for r in os.environ.get("GITHUB_ALLOWED_REPOS", "").split(",") if r
)

# Auth token for container-to-gateway authentication
GATEWAY_TOKEN = os.environ.get("GATEWAY_TOKEN", "")

TIMEOUT = 15
MAX_PAYLOAD_BYTES = 1 * 1024 * 1024  # 1MB


# --- Middleware ---

@app.before_request
def check_auth():
    """Require Bearer token if GATEWAY_TOKEN is set."""
    if not GATEWAY_TOKEN:
        return  # No auth configured — open access on gt-net
    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    if token != GATEWAY_TOKEN:
        return jsonify({"error": "unauthorized"}), 401


@app.before_request
def check_payload_size():
    """Reject oversized payloads."""
    if request.content_length and request.content_length > MAX_PAYLOAD_BYTES:
        return jsonify({"error": "payload too large"}), 413


def validate_path(api_path):
    """Reject path traversal and normalization attacks."""
    if ".." in api_path or "//" in api_path:
        logging.warning(f"BLOCKED path traversal attempt: {api_path}")
        return False
    normalized = urllib.parse.normpath(api_path)
    # normpath strips leading slash and collapses slashes
    if normalized != api_path:
        logging.warning(f"BLOCKED non-normalized path: {api_path} (normalized: {normalized})")
        return False
    if not re.match(r'^[a-zA-Z0-9/_.\-]+$', api_path):
        logging.warning(f"BLOCKED invalid characters in path: {api_path}")
        return False
    return True


# --- GitHub Proxy ---

@app.route("/github/<path:api_path>", methods=["GET", "POST", "PATCH"])
def github_proxy(api_path):
    """Proxy GitHub API calls. Agents call gateway:9999/github/repos/org/repo/..."""
    token = SECRETS.get("GITHUB_TOKEN")
    if not token:
        return jsonify({"error": "GITHUB_TOKEN not configured"}), 500

    if not validate_path(api_path):
        return jsonify({"error": "invalid path"}), 400

    # Enforce repo allowlist
    if GITHUB_ALLOWED_REPOS:
        match = re.match(r"repos/([^/]+/[^/]+)", api_path)
        if match and match.group(1) not in GITHUB_ALLOWED_REPOS:
            logging.warning(f"BLOCKED github access to {match.group(1)}")
            return jsonify({"error": "repo not in allowlist"}), 403

    # Block dangerous endpoints
    blocked = ["admin", "delete", "transfer", "installation", "app"]
    if any(seg in api_path.split("/") for seg in blocked):
        logging.warning(f"BLOCKED dangerous github path: {api_path}")
        return jsonify({"error": "endpoint blocked by policy"}), 403

    resp = requests.request(
        method=request.method,
        url=f"https://api.github.com/{api_path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
        },
        params=request.args,
        json=request.get_json(silent=True) if request.is_json else None,
        timeout=TIMEOUT,
    )
    logging.info(f"github {request.method} /{api_path} -> {resp.status_code}")
    return Response(resp.content, status=resp.status_code,
                    content_type=resp.headers.get("content-type", "application/json"))


# --- Jira Proxy ---

@app.route("/jira/<path:api_path>", methods=["GET", "POST", "PUT"])
def jira_proxy(api_path):
    """Proxy Jira API calls. Agents call gateway:9999/jira/issue/PROJ-123."""
    token = SECRETS.get("JIRA_TOKEN")
    email = SECRETS.get("JIRA_EMAIL")
    base_url = SECRETS.get("JIRA_URL")
    if not all([token, email, base_url]):
        return jsonify({"error": "Jira credentials not configured"}), 500

    if not validate_path(api_path):
        return jsonify({"error": "invalid path"}), 400

    # Enforce project allowlist — require a known project key in the path
    if JIRA_ALLOWED_PROJECTS:
        has_allowed_project = any(f"{proj}-" in api_path for proj in JIRA_ALLOWED_PROJECTS)
        # Also block endpoints that don't reference a specific issue
        safe_prefixes = ("issue/", "search")
        if not has_allowed_project and not api_path.startswith(safe_prefixes):
            logging.warning(f"BLOCKED jira path without allowed project: {api_path}")
            return jsonify({"error": "project not in allowlist"}), 403
        if has_allowed_project:
            match = re.search(r"([A-Z][A-Z0-9]+)-\d+", api_path)
            if match and match.group(1) not in JIRA_ALLOWED_PROJECTS:
                logging.warning(f"BLOCKED jira access to project {match.group(1)}")
                return jsonify({"error": "project not in allowlist"}), 403

    # Block admin/user management and destructive endpoints
    blocked = ["admin", "user", "permissions", "role", "myself", "serverInfo"]
    if any(seg in api_path.split("/") for seg in blocked):
        logging.warning(f"BLOCKED dangerous jira path: {api_path}")
        return jsonify({"error": "endpoint blocked by policy"}), 403

    if request.method == "DELETE":
        logging.warning(f"BLOCKED DELETE on jira /{api_path}")
        return jsonify({"error": "DELETE not allowed"}), 403

    resp = requests.request(
        method=request.method,
        url=f"{base_url}/rest/api/3/{api_path}",
        auth=(email, token),
        params=request.args,
        json=request.get_json(silent=True) if request.is_json else None,
        timeout=TIMEOUT,
    )
    logging.info(f"jira {request.method} /{api_path} -> {resp.status_code}")
    return Response(resp.content, status=resp.status_code,
                    content_type=resp.headers.get("content-type", "application/json"))


# --- Slack Proxy ---

SLACK_ALLOWED_METHODS = {
    "chat.postMessage", "chat.update",
    "conversations.history", "conversations.list",
    "reactions.add", "files.upload",
}

@app.route("/slack/<path:api_path>", methods=["GET", "POST"])
def slack_proxy(api_path):
    """Proxy Slack API calls. Agents call gateway:9999/slack/chat.postMessage."""
    token = SECRETS.get("SLACK_TOKEN")
    if not token:
        return jsonify({"error": "SLACK_TOKEN not configured"}), 500

    if api_path not in SLACK_ALLOWED_METHODS:
        logging.warning(f"BLOCKED slack method: {api_path}")
        return jsonify({"error": f"slack method '{api_path}' not allowed"}), 403

    resp = requests.post(
        f"https://slack.com/api/{api_path}",
        headers={"Authorization": f"Bearer {token}"},
        json=request.get_json(silent=True) if request.is_json else None,
        data=request.form if not request.is_json else None,
        timeout=TIMEOUT,
    )
    logging.info(f"slack {api_path} -> {resp.status_code}")
    return Response(resp.content, status=resp.status_code,
                    content_type=resp.headers.get("content-type", "application/json"))


# --- Health ---

@app.route("/health")
def health():
    services = {
        "github": "GITHUB_TOKEN" in SECRETS,
        "jira": all(k in SECRETS for k in ["JIRA_TOKEN", "JIRA_EMAIL", "JIRA_URL"]),
        "slack": "SLACK_TOKEN" in SECRETS,
    }
    return jsonify({"status": "ok", "services": services})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9999)
