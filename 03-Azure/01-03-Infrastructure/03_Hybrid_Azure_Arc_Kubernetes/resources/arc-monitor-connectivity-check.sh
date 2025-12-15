#!/usr/bin/env bash
set -euo pipefail


# ------------------------------------------------------------------------------
# Synopsis: Azure Arc NODE Monitoring Connectivity Validation Script (Public Mode)
#
# This script validates the **network connectivity requirements** specifically
# needed for **Azure Monitor / Container Insights** on **Arc-enabled Kubernetes
# clusters** operating in **public (direct) mode** — without Private Link,
# without AMPLS, and without Cluster Connect.
#
# Purpose:
# - Ensure Kubernetes nodes can successfully send logs and metrics to Azure
#   Monitor over HTTPS.
# - Validate DNS, TLS, and HTTPS access to all **required ingestion, control-
#   plane, and telemetry endpoints** used by the Azure Monitor agent (AMA/Container
#   Insights) when deployed on Arc-enabled Kubernetes.
# - Confirm outbound access for downloading extension container images and
#   retrieving artifacts from Microsoft Container Registry and Azure Blob Storage.
#
# Validated Functional Areas (Public Monitoring Mode):
#
#   Logs ingestion:
#     - *.ods.opinsights.azure.com
#     - *.ingest.monitor.azure.com
#
#   Metrics ingestion:
#     - global.handler.metrics.monitor.azure.com
#
#   Monitoring control-plane:
#     - global.handler.control.monitor.azure.com
#
#   Diagnostics telemetry:
#     - dc.services.visualstudio.com
#
#   Extension image pulls:
#     - mcr.microsoft.com
#     - *.blob.core.windows.net
#
# These endpoints correspond directly to the documented requirements in:
# “Enable monitoring for Arc-enabled Kubernetes clusters – Azure Monitor”
# (Microsoft Learn, Public Cloud / Direct Mode)
#
# Execution Context:
# - This script is intended to be run **from inside the Kubernetes cluster** so
#   that connectivity reflects the actual egress path of the Azure Monitor agent
#   pods.
#
# How to Run Inside the Cluster:
#
# 1. Start an Ubuntu diagnostic pod:
#    kubectl run arccheck --image=ubuntu:22.04 -it --restart=Never -- bash
#    
#    If you already have a suitable pod, you can exec into it instead:
#    kubectl exec -it <pod-name> -- bash
#    i.e. kubectl exec -it arccheck -- bash
#
# 2. Install required tools:
#    apt update
#    apt install -y curl dnsutils openssl ca-certificates
#
# 3. Download the script:
#    curl -sSL -o arc-node-monitoring-check.sh <RAW_GITHUB_URL>
#
# 4. Make it executable:
#    chmod +x arc-node-monitoring-check.sh
#
# 5. Run the script:
#    ./arc-node-monitoring-check.sh westeurope
#
# Output:
# - DNS, TLS, and HTTPS test results for each ingestion and control-plane endpoint
# - Success/failure summary
# - Troubleshooting hints for proxies, TLS inspection, or blocked wildcard domains
#
# Exit Codes:
# - 0 = All monitoring-related connectivity checks succeeded
# - 1 = One or more required ingestion/control-plane endpoints unreachable
#
# Intended Audience:
# - Cluster administrators validating readiness for Azure Monitor
# - Network/security teams enabling outbound rules for monitoring
# - Architects verifying hybrid cloud observability requirements
#
# ----------------------------------------------------------------------------


REGION_RAW="${1:-westeurope}"

# Normalize region to Azure FQDN segment (lowercase, remove spaces)
REGION="$(echo "$REGION_RAW" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"

CURL_TIMEOUT=7
OPENSSL_TIMEOUT=7

COLOR_OK="\033[32m"; COLOR_ERR="\033[31m"; COLOR_WARN="\033[33m"; COLOR_DIM="\033[90m"; COLOR_RESET="\033[0m"

h1(){ echo -e "\n\033[1m$1\033[0m"; }
ok(){ echo -e "${COLOR_OK}✔${COLOR_RESET} $1"; }
err(){ echo -e "${COLOR_ERR}✖${COLOR_RESET} $1"; }
warn(){ echo -e "${COLOR_WARN}⚠${COLOR_RESET} $1"; }

# Resolver selection
RESOLVER_CMD=""
if command -v dig >/dev/null 2>&1; then
  RESOLVER_CMD="dig +short"
elif command -v nslookup >/dev/null 2>&1; then
  RESOLVER_CMD="nslookup"
elif command -v getent >/dev/null 2>&1; then
  RESOLVER_CMD="getent hosts"
else
  echo "Need dig/nslookup/getent installed"; exit 2
fi

# ------------------------------------------------------------------------------
# Endpoint sets (PUBLIC monitoring mode)
# ------------------------------------------------------------------------------

# Logs ingestion (Container Insights DCE) — region specific
LOGS_ENDPOINTS=(
  "${REGION}.ingest.monitor.azure.com"
  "${REGION}.ods.opinsights.azure.com"
  # Optional legacy OMS endpoint (some agents may still ping it)
  "${REGION}.oms.opinsights.azure.com"
)

# Metrics ingestion (Managed Prometheus DCE) — region specific
METRICS_ENDPOINTS=(
  "${REGION}.metrics.ingest.monitor.azure.com"
)

# Control-plane handlers — global + region specific
CONTROL_ENDPOINTS=(
  "global.handler.control.monitor.azure.com"
  "${REGION}.handler.control.monitor.azure.com"
)

# Auth & diagnostics telemetry
AUX_ENDPOINTS=(
  "login.microsoftonline.com"
  "dc.services.visualstudio.com"
)

# Images & artifacts
ARTIFACT_ENDPOINTS=(
  "mcr.microsoft.com"
  # Use a concrete storage account host rather than base "blob.core.windows.net"
  "azuremonitorcontainerinsights.blob.core.windows.net"
)

ALL_ENDPOINTS=(
  "${LOGS_ENDPOINTS[@]}"
  "${METRICS_ENDPOINTS[@]}"
  "${CONTROL_ENDPOINTS[@]}"
  "${AUX_ENDPOINTS[@]}"
  "${ARTIFACT_ENDPOINTS[@]}"
)

PASSED=()
FAILED=()

dns_check(){
  local host="$1"
  if [[ "$RESOLVER_CMD" == "dig +short" ]]; then
    dig +short "$host" | grep -E '^[0-9a-fA-F:.]+$' >/dev/null \
      && ok "DNS resolves: $host" \
      || { err "DNS failed: $host"; return 1; }
  elif [[ "$RESOLVER_CMD" == "nslookup" ]]; then
    nslookup "$host" >/dev/null 2>&1 \
      && ok "DNS resolves: $host" \
      || { err "DNS failed: $host"; return 1; }
  else
    getent hosts "$host" >/dev/null 2>&1 \
      && ok "DNS resolves: $host" \
      || { err "DNS failed: $host"; return 1; }
  fi
}

tls_check(){
  local host="$1"
  timeout "$OPENSSL_TIMEOUT" \
    bash -c "echo | openssl s_client -servername ${host} -connect ${host}:443 >/dev/null 2>&1" \
    && ok "TLS OK: ${host}:443" \
    || { err "TLS FAILED: ${host}:443"; return 1; }
}

https_check(){
  local host="$1"
  curl -sS -I --connect-timeout "$CURL_TIMEOUT" "https://${host}" >/dev/null 2>&1 \
    && ok "HTTPS OK: https://${host}" \
    || { err "HTTPS FAILED: https://${host}"; return 1; }
}

# ------------------------------------------------------------------------------
# EXECUTION
# ------------------------------------------------------------------------------

h1 "Azure Arc NODE Monitoring Connectivity Check (Public Mode) — region: ${REGION}"

[[ -n "${HTTPS_PROXY:-}" || -n "${HTTP_PROXY:-}" ]] \
  && echo -e "${COLOR_DIM}Proxy detected. HTTPS_PROXY=${HTTPS_PROXY:-<unset>} HTTP_PROXY=${HTTP_PROXY:-<unset>}${COLOR_RESET}"

h1 "1) DNS"
for host in "${ALL_ENDPOINTS[@]}"; do
  dns_check "$host" \
    && PASSED+=("DNS:$host") \
    || FAILED+=("DNS:$host")
done

h1 "2) TLS Handshake (443)"
for host in "${ALL_ENDPOINTS[@]}"; do
  tls_check "$host" \
    && PASSED+=("TLS:$host") \
    || FAILED+=("TLS:$host")
done

h1 "3) HTTPS Reachability (443)"
for host in "${ALL_ENDPOINTS[@]}"; do
  https_check "$host" \
    && PASSED+=("HTTPS:$host") \
    || FAILED+=("HTTPS:$host")
done

h1 "Summary"
echo -e "Passed: ${COLOR_OK}${#PASSED[@]}${COLOR_RESET} | Failed: ${COLOR_ERR}${#FAILED[@]}${COLOR_RESET}"

if (( ${#FAILED[@]} > 0 )); then
  echo -e "${COLOR_ERR}Failures:${COLOR_RESET}"
  for f in "${FAILED[@]}"; do echo " - $f"; done

  echo -e "\nTroubleshooting Hints:"
  echo " - Allow outbound HTTPS (443) to *.ingest.monitor.azure.com, *.ods/oms.opinsights.azure.com"
  echo " - Allow outbound HTTPS (443) to ${REGION}.metrics.ingest.monitor.azure.com for Managed Prometheus"
  echo " - Allow global and regional handler control endpoints"
  echo " - Disable TLS inspection for these FQDNs; the agents expect end-to-end TLS"
  echo " - Ensure mcr.microsoft.com and Azure Monitor storage are reachable for extension artifacts"
  exit 1
else
  echo -e "${COLOR_OK}All Azure Monitor connectivity checks passed.${COLOR_RESET}"
  exit 0
fi