import ast
import base64
import io
import json
import pathlib
import re
import shlex
import sys
import tempfile
from unittest import mock
import zipfile

import yaml

root = pathlib.Path(sys.argv[1])
runner = (root / "configure-workstation.sh").read_text()
python_blocks = re.findall(r"<<'PY'\n(.*?)\nPY", runner, re.S)
assert len(python_blocks) == 1
ast.parse(python_blocks[0])
node_check = re.search(r"python3 -c '\n(.*?)\n'", runner, re.S).group(1)
ast.parse(node_check)
with zipfile.ZipFile(root / "lab-assets.zip") as archive:
    for path in ("ansible/playbook-workstation.yml", "ansible/requirements.yml"):
        assert yaml.safe_load(archive.read(path))
verification = yaml.safe_load((root / "verify-workstation.yml").read_text())
assert verification[0]["hosts"] == "workstations"
collections = yaml.safe_load((root / "collections.yml").read_text())["collections"]
assert {item["name"]: item["version"] for item in collections} == {
    "ansible.windows": "2.8.0",
    "chocolatey.chocolatey": "1.5.3",
}

with tempfile.TemporaryDirectory(prefix="microhack-k8s-python-") as directory:
    work = pathlib.Path(directory)
    (work / "ansible").mkdir()
    configuration = {
        "admin_user": "mhadmin",
        "admin_password": "test-not-a-real-password",
        "workstation_ip": "10.1.2.10",
        "master_ip": "10.1.1.10",
        "lab_prefix": "k8stest",
        "resource_group": "exercise-test",
        "onprem_resource_group": "exercise-test-onprem",
        "location": "swedencentral",
        "acr_name": "acrlabuser002012345678",
        "workspace_name": "labuser-0020-law",
    }
    (work / "config.json").write_text(json.dumps(configuration))
    read_text = pathlib.Path.read_text

    def fake_read(path, *args, **kwargs):
        if str(path).replace("\\", "/") == "/etc/rancher/k3s/k3s.yaml":
            return "server: https://127.0.0.1:6443\n"
        return read_text(path, *args, **kwargs)

    with mock.patch.object(sys, "argv", ["setup", directory]), mock.patch.object(
        pathlib.Path, "read_text", fake_read
    ):
        exec(compile(python_blocks[0], "configure-workstation.sh", "exec"), {})
    inventory = json.loads((work / "ansible/inventory.json").read_text())
    workstation = inventory["all"]["children"]["workstations"]
    assert workstation["hosts"]["workstation"]["ansible_host"] == "10.1.2.10"
    assert workstation["vars"]["ansible_password"] == configuration["admin_password"]
    exports = base64.b64decode(
        json.loads((work / "ansible/extra-vars.json").read_text())["context_base64"]
    ).decode()
    assert "export onprem_resource_group=exercise-test-onprem" in exports
    assert "export arc_resource_group=exercise-test" in exports
    assert "export location=swedencentral" in exports
    assert "export acr_name=acrlabuser002012345678" in exports
    assert "export workspace_name=labuser-0020-law" in exports
    assert configuration["admin_password"] not in exports
    for line in exports.splitlines():
        assert len(shlex.split(line)) == 2
    assert "https://10.1.1.10:6443" in (work / "ansible/kubeconfig").read_text()

for challenge in ("02", "04"):
    walkthrough = (
        root.parent / "walkthrough" / f"challenge-{challenge}" / f"solution-{challenge}.md"
    ).read_text(encoding="utf-8")
    assert 'export workspace_name="${workspace_name:-${user_number}-law}"' in walkthrough
    workspace_commands = [
        line for line in walkthrough.splitlines()
        if "az monitor log-analytics workspace " in line
    ]
    assert workspace_commands
    assert all('"$workspace_name"' in line for line in workspace_commands)

for count, ready, should_pass in ((3, True, True), (2, True, False), (3, False, False)):
    nodes = {
        "items": [
            {"status": {"conditions": [{"type": "Ready", "status": "True" if ready else "False"}]}}
            for _ in range(count)
        ]
    }
    failed = False
    with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(nodes))):
        try:
            exec(compile(node_check, "node-readiness", "exec"), {})
        except SystemExit:
            failed = True
    assert failed != should_pass

print("Validated Ansible YAML, guest Python, inventory, separate RG context and exact node readiness.")
