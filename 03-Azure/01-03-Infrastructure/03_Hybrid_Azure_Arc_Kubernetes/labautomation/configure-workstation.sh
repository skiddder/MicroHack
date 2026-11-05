#!/bin/bash
set -euo pipefail
umask 077
export DEBIAN_FRONTEND=noninteractive
export ANSIBLE_NOCOLOR=1
export ANSIBLE_DISPLAY_ARGS_TO_STDOUT=false

work=/opt/microhack/workstation
mkdir -p "$work/ansible" "$work/scripts"
trap 'rm -f /opt/microhack/workstation/config.json /opt/microhack/workstation/ansible/inventory.json /opt/microhack/workstation/ansible/extra-vars.json /opt/microhack/workstation/ansible/kubeconfig' EXIT
printf '%s' "${MICROHACK_CONFIG:?Missing protected Run Command configuration}" | base64 -d > "$work/config.json"
unset MICROHACK_CONFIG
printf '%s' '__PLAYBOOK__' | base64 -d > "$work/ansible/playbook-workstation.yml"
printf '%s' '__COLLECTIONS__' | base64 -d > "$work/ansible/requirements.yml"
printf '%s' '__WSL_TOOLS__' | base64 -d > "$work/scripts/setup-wsl-tools.sh"
printf '%s' '__VERIFY__' | base64 -d > "$work/ansible/verify-workstation.yml"
printf '%s' '__PYTHON_REQUIREMENTS__' | base64 -d > "$work/requirements.txt"

apt-get update
apt-get install -y python3-venv python3-pip
python3 -m venv "$work/venv"
"$work/venv/bin/pip" install --disable-pip-version-check -r "$work/requirements.txt"
export ANSIBLE_COLLECTIONS_PATH="$work/collections"
"$work/venv/bin/ansible-galaxy" collection install -r "$work/ansible/requirements.yml"

python3 - "$work" <<'PY'
import base64
import json
import pathlib
import shlex
import sys

work = pathlib.Path(sys.argv[1])
config = json.loads((work / "config.json").read_text())
inventory = {"all": {"children": {"workstations": {
    "hosts": {"workstation": {"ansible_host": config["workstation_ip"]}},
    "vars": {
        "ansible_user": config["admin_user"],
        "ansible_password": config["admin_password"],
        "ansible_connection": "winrm",
        "ansible_winrm_port": 5986,
        "ansible_winrm_scheme": "https",
        "ansible_winrm_transport": "basic",
        "ansible_winrm_server_cert_validation": "ignore"
    }
}}}}
(work / "ansible/inventory.json").write_text(json.dumps(inventory))
prefix = config["lab_prefix"]
environment = {
    "user_number": prefix,
    "onprem_resource_group": config["onprem_resource_group"],
    "arc_resource_group": config["resource_group"],
    "arc_cluster_name": f"{prefix}-k8s-arc-enabled",
    "location": config["location"],
    "acr_name": config["acr_name"],
    "workspace_name": config["workspace_name"],
    "master_ip": config["master_ip"],
    "admin_user": config["admin_user"]
}
exports = "\n".join(f"export {key}={shlex.quote(value)}" for key, value in environment.items()) + "\n"
kubeconfig = pathlib.Path("/etc/rancher/k3s/k3s.yaml").read_text().replace("127.0.0.1", config["master_ip"])
(work / "ansible/kubeconfig").write_text(kubeconfig)
(work / "ansible/extra-vars.json").write_text(json.dumps({
    "context_base64": base64.b64encode(exports.encode()).decode(),
    "kubeconfig_path": str(work / "ansible/kubeconfig")
}))
PY

cd "$work/ansible"
"$work/venv/bin/ansible-playbook" -i inventory.json playbook-workstation.yml
"$work/venv/bin/ansible-playbook" -i inventory.json verify-workstation.yml --extra-vars @extra-vars.json

deadline=$((SECONDS + 600))
while ! kubectl get nodes -o json | python3 -c '
import json, sys
nodes = json.load(sys.stdin)["items"]
if len(nodes) != 3 or not all(any(c["type"] == "Ready" and c["status"] == "True" for c in n["status"]["conditions"]) for n in nodes):
    sys.exit("Expected exactly three Ready K3s nodes.")
'; do
    if (( SECONDS >= deadline )); then
        echo "Timed out waiting for exactly three Ready K3s nodes." >&2
        exit 1
    fi
    sleep 10
done
echo "Workstation tools and all three K3s nodes verified. Arc onboarding is left to the participant."
