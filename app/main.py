"""
DataVault Technologies — Compliance Audit Trail API
Python FastAPI application

Simulates DataVault's FCA-regulated compliance audit trail platform.
Deployed to Kubernetes via GitOps (ArgoCD).

Interns do NOT modify this file — they write the Kubernetes manifests,
Terraform infrastructure, and GitHub Actions CI pipeline to deploy it.
"""

import os
import hashlib
import subprocess
import time
import random
from datetime import datetime
from typing import Optional
from fastapi import FastAPI, HTTPException, Header, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# This is the main application for the DataVault Compliance API
# It is a simple API that allows you to manage the audit trail and compliance records 
# ── Application setup ─────────────────────────────────────────────────────────
APP_VERSION = "2.4.2"

app = FastAPI(
    title="DataVault Compliance API",
    description="FCA-compliant audit trail platform for UK financial services",
    version=APP_VERSION,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Config from environment ───────────────────────────────────────────────────
APP_ENV = os.environ.get("APP_ENV", "development")
API_KEY = os.environ.get("API_KEY", "datavault-dev-key")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "info")

# Track startup time for uptime reporting
START_TIME = time.time()

_REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def _git_output(args: list[str], cwd: str = _REPO_ROOT) -> str:
    try:
        result = subprocess.run(
            ["git", *args],
            capture_output=True,
            text=True,
            timeout=5,
            cwd=cwd,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        pass
    return ""


def _resolve_deployment_metadata() -> tuple[str, str, str]:
    """Git commit, message, and commit time — from K8s env or local git."""
    git_commit = os.environ.get("GIT_COMMIT", "").strip()
    commit_message = os.environ.get("GIT_COMMIT_MESSAGE", "").strip()
    deployed_at = os.environ.get("GIT_DEPLOYED_AT", "").strip()

    if not git_commit:
        git_commit = _git_output(["rev-parse", "HEAD"]) or "unknown"

    if git_commit != "unknown":
        if not commit_message:
            commit_message = _git_output(["log", "-1", "--format=%s", git_commit])
        if not deployed_at:
            deployed_at = _git_output(["log", "-1", "--format=%cI", git_commit])

    return (
        git_commit,
        commit_message or "unknown",
        deployed_at or "unknown",
    )


_GIT_COMMIT, _COMMIT_MESSAGE, _DEPLOYED_AT = _resolve_deployment_metadata()

# ── In-memory audit store ─────────────────────────────────────────────────────
audit_entries: list = [
    {
        "id": "AUD-001",
        "timestamp": "2025-02-14T21:47:00Z",
        "actor": "james.thornton@datavault.io",
        "action": "DEPLOY",
        "resource": "payment-api/v2.4.0",
        "outcome": "failure",
        "detail": "Deployment failed — missing environment variable PAYMENT_GATEWAY_KEY",
        "client_id": "tier1-bank-uk",
        "severity": "HIGH"
    },
    {
        "id": "AUD-002",
        "timestamp": "2025-02-14T22:03:00Z",
        "actor": "priya.mehta@datavault.io",
        "action": "INCIDENT_DECLARED",
        "resource": "payment-api",
        "outcome": "success",
        "detail": "P1 incident declared. Client notified. Investigation started.",
        "client_id": "tier1-bank-uk",
        "severity": "CRITICAL"
    },
    {
        "id": "AUD-003",
        "timestamp": "2025-02-15T00:31:00Z",
        "actor": "james.thornton@datavault.io",
        "action": "RESTORE",
        "resource": "payment-api/v2.3.9",
        "outcome": "success",
        "detail": "Manual rollback to v2.3.9 completed. Service restored.",
        "client_id": "tier1-bank-uk",
        "severity": "HIGH"
    }
]

compliance_records: list = []

# ── Models ────────────────────────────────────────────────────────────────────
class AuditEntry(BaseModel):
    actor: str
    action: str
    resource: str
    outcome: str
    detail: str
    client_id: str
    severity: Optional[str] = "INFO"

class ComplianceRecord(BaseModel):
    client_id: str
    regulation: str
    control_id: str
    status: str
    evidence: str
    reviewed_by: str

# ── Authentication ────────────────────────────────────────────────────────────
def require_api_key(x_api_key: str = Header(default=None)):
    valid_keys = os.environ.get("API_KEY", "datavault-dev-key").split(",")
    if x_api_key not in valid_keys:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
    return x_api_key

# ── Health endpoints ──────────────────────────────────────────────────────────
@app.get("/health")
def health():
    """
    Liveness and readiness probe endpoint.
    Kubernetes calls this every 15 seconds.
    Returns 200 if the service is healthy, 503 if degraded.
    """
    uptime_seconds = int(time.time() - START_TIME)
    return {
        "status": "ok",
        "service": "datavault-api",
        "version": APP_VERSION,
        "environment": APP_ENV,
        "uptime_seconds": uptime_seconds,
        "timestamp": datetime.utcnow().isoformat(),
        "audit_entries": len(audit_entries)
    }

@app.get("/ready")
def readiness():
    """
    Readiness probe — more thorough than liveness.
    Returns 503 if the service is not ready to accept traffic.
    """
    # Simulate a startup check
    if time.time() - START_TIME < 2:
        raise HTTPException(status_code=503, detail="Service still initialising")
    return {"ready": True, "timestamp": datetime.utcnow().isoformat()}

# ── Audit trail endpoints ─────────────────────────────────────────────────────
@app.get("/api/audit")
def list_audit_entries(
    client_id: Optional[str] = None,
    severity: Optional[str] = None,
    api_key: str = Depends(require_api_key)
):
    """List audit trail entries. Supports filtering by client and severity."""
    results = audit_entries
    if client_id:
        results = [e for e in results if e.get("client_id") == client_id]
    if severity:
        results = [e for e in results if e.get("severity") == severity.upper()]
    return {
        "entries": results,
        "total": len(results),
        "filtered_by": {"client_id": client_id, "severity": severity}
    }

@app.post("/api/audit")
def create_audit_entry(entry: AuditEntry, api_key: str = Depends(require_api_key)):
    """Record a new audit entry. Every FCA-regulated action must be logged here."""
    new_entry = {
        "id": f"AUD-{len(audit_entries) + 1:03d}",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        **entry.dict()
    }
    # Generate an integrity hash so entries cannot be tampered with
    content = f"{new_entry['id']}{new_entry['timestamp']}{entry.actor}{entry.action}"
    new_entry["integrity_hash"] = hashlib.sha256(content.encode()).hexdigest()[:16]

    audit_entries.append(new_entry)
    return new_entry

@app.get("/api/audit/{entry_id}")
def get_audit_entry(entry_id: str, api_key: str = Depends(require_api_key)):
    for entry in audit_entries:
        if entry["id"] == entry_id:
            return entry
    raise HTTPException(status_code=404, detail=f"Audit entry {entry_id} not found")

# ── Compliance records ────────────────────────────────────────────────────────
@app.get("/api/compliance")
def list_compliance_records(api_key: str = Depends(require_api_key)):
    return {"records": compliance_records, "total": len(compliance_records)}

@app.post("/api/compliance")
def create_compliance_record(record: ComplianceRecord, api_key: str = Depends(require_api_key)):
    new_record = {
        "id": f"COMP-{len(compliance_records) + 1:03d}",
        "created_at": datetime.utcnow().isoformat(),
        **record.dict()
    }
    compliance_records.append(new_record)
    return new_record

# ── Client management ─────────────────────────────────────────────────────────
clients = {
    "tier1-bank-uk": {
        "id": "tier1-bank-uk",
        "name": "First Capital Bank UK",
        "regulation": "FCA",
        "sla_uptime": "99.9%",
        "contract_value": "£340,000/year"
    },
    "insurance-corp": {
        "id": "insurance-corp",
        "name": "British Insurance Corporation",
        "regulation": "FCA",
        "sla_uptime": "99.5%",
        "contract_value": "£180,000/year"
    }
}

@app.get("/api/clients")
def list_clients(api_key: str = Depends(require_api_key)):
    return {"clients": list(clients.values()), "total": len(clients)}

@app.get("/api/clients/{client_id}")
def get_client(client_id: str, api_key: str = Depends(require_api_key)):
    client = clients.get(client_id)
    if not client:
        raise HTTPException(status_code=404, detail=f"Client {client_id} not found")
    # Include their audit entry count
    client_audits = [e for e in audit_entries if e.get("client_id") == client_id]
    return {**client, "audit_entry_count": len(client_audits)}

# ── Deployment simulation (for GitOps demo) ───────────────────────────────────
@app.get("/api/deployment/status")
def deployment_status():
    """Shows current deployment info — useful for demonstrating GitOps rollout."""
    return {
        "version": APP_VERSION,
        "environment": APP_ENV,
        "deployed_at": _DEPLOYED_AT,
        "pod_name": os.environ.get("HOSTNAME", "unknown"),
        "git_commit": _GIT_COMMIT,
        "commit_message": _COMMIT_MESSAGE,
        "message": "This version was deployed via GitOps — every change is a Git commit.",
    }
