import ast
import base64
import io
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
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
    if challenge == "02":
        assert 'export workspace_name="<Log Analytics Workspace>"' in walkthrough
        assert 'export arc_resource_group="<Arc Resource Group>"' in walkthrough
        assert "sed 's/^0*//'" not in walkthrough
        monitoring = re.search(r"```bash\n(.*?)```", walkthrough, re.S).group(1)
    else:
        assert 'export data_controller_name="${participant_name}-dc"' in walkthrough
        assert 'sqlmi-${participant_name}-1' in walkthrough
        assert "sed 's/^0*//'" not in walkthrough
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

onboarding = (
    root.parent / "walkthrough" / "challenge-01" / "az_connect_k8s.sh"
).read_text(encoding="utf-8")
git_bash = pathlib.Path(r"C:\Program Files\Git\bin\bash.exe")
bash = str(git_bash) if os.name == "nt" and git_bash.exists() else shutil.which("bash")
assert bash, "Bash is required to validate the onboarding script."
subprocess.run([bash, "-n"], input=onboarding, text=True, encoding="utf-8", check=True)
setup = onboarding.split("# Registering Azure Arc providers", 1)[0]
account_command = "account show --query user.name --output tsv"
exists_command = "group exists --name rg-labuser-0009"
master_command = (
    "vm list --resource-group rg-labuser-0009-onprem "
    "--query [?ends_with(name, '-k8s-master')].name | [0] --output tsv"
)
location_command = "group show --name rg-labuser-0009 --query location --output tsv"

with tempfile.TemporaryDirectory(prefix="microhack-k8s-onboarding-") as directory:
    def check_onboarding(name, responses, expected=None, context=None, error=None, script=None):
        home = pathlib.Path(directory) / name
        home.mkdir()
        if context:
            (home / ".microhack-k8s.env").write_text(
                "\n".join(f"export {key}={shlex.quote(value)}" for key, value in context.items()),
                encoding="utf-8",
            )
        cases = []
        for command, response in responses.items():
            status, output = response if isinstance(response, tuple) else (0, response)
            redirect = " >&2" if status else ""
            cases.append(
                f"{shlex.quote(command)}) printf '%s\\n' {shlex.quote(output)}{redirect}; return {status} ;;"
            )
        stub = (
            'export HOME="$1"\naz() { case "$*" in\n'
            + "\n".join(cases)
            + '\n*) echo "Unexpected Azure command: $*" >&2; return 98 ;; esac; }\n'
        )
        environment = os.environ.copy()
        for key in ("user_number", "onprem_resource_group", "arc_resource_group", "arc_cluster_name", "location"):
            environment.pop(key, None)
        result = subprocess.run(
            [bash, "-s", "--", home.as_posix()],
            input=stub + "set -e\n" + (setup if script is None else script) + '\nprintf "RESULT=%s|%s|%s|%s\\n" "$onprem_resource_group" "$arc_resource_group" "$arc_cluster_name" "$location"\n',
            text=True,
            encoding="utf-8",
            capture_output=True,
            env=environment,
        )
        if error:
            assert result.returncode != 0 and error in result.stdout + result.stderr, result
            assert "RESULT=" not in result.stdout
        else:
            assert result.returncode == 0, result.stderr
            assert f"RESULT={'|'.join(expected)}" in result.stdout, result.stdout

    hb = {
        account_command: "labuser-0009@german.microhack.cloud",
        exists_command: "true",
        master_command: "k8stest-k8s-master",
        location_command: "swedencentral",
    }
    expected_hb = ("rg-labuser-0009-onprem", "rg-labuser-0009", "k8stest-k8s-arc-enabled", "swedencentral")
    check_onboarding("hb-no-context", hb, expected_hb)
    check_onboarding("hb-uppercase", {**hb, account_command: "LabUser-0009@german.microhack.cloud"}, expected_hb)
    check_onboarding(
        "context-priority",
        {account_command: hb[account_command]},
        ("custom-onprem", "custom-exercise", "custom-cluster", "francecentral"),
        context={
            "user_number": "k8scontext",
            "onprem_resource_group": "custom-onprem",
            "arc_resource_group": "custom-exercise",
            "arc_cluster_name": "custom-cluster",
            "location": "francecentral",
        },
    )
    check_onboarding(
        "hb-partial-context",
        {account_command: hb[account_command], location_command: "swedencentral"},
        ("rg-labuser-0009-onprem", "rg-labuser-0009", "supplied-cluster", "swedencentral"),
        context={"arc_resource_group": "rg-labuser-0009", "arc_cluster_name": "supplied-cluster"},
    )
    check_onboarding(
        "terraform-fallback",
        {
            account_command: "LabUser-37@example.test",
            "group exists --name rg-labuser-37": "false",
            "group exists --name 37-k8s-arc": "true",
            "group show --name 37-k8s-arc --query location --output tsv": "westeurope",
        },
        ("37-k8s-onprem", "37-k8s-arc", "37-k8s-arc-enabled", "westeurope"),
    )
    check_onboarding(
        "missing-groups",
        {account_command: hb[account_command], exists_command: "false", "group exists --name 9-k8s-arc": "false"},
        error="Neither 'rg-labuser-0009' nor '9-k8s-arc' exists",
    )
    check_onboarding("missing-master", {**hb, master_command: ""}, error="No K3s master VM")
    check_onboarding("empty-location", {**hb, location_command: ""}, error="Could not determine the location")
    check_onboarding(
        "lookup-denied",
        {account_command: hb[account_command], exists_command: (1, "AuthorizationFailed")},
        error="AuthorizationFailed",
    )
    check_onboarding("location-denied", {**hb, location_command: (1, "AuthorizationFailed")}, error="AuthorizationFailed")
    check_onboarding("account-denied", {account_command: (1, "Please run az login")}, error="Please run az login")

    subprocess.run([bash, "-n"], input=monitoring, text=True, encoding="utf-8", check=True)
    for label, group, workspace, cluster in (
        ("hb-0009", "rg-labuser-0009", "labuser-0009-law", "k8s7bbc1170d029-k8s-arc-enabled"),
        ("hb-0020", "rg-labuser-0020", "labuser-0020-law", "k8sc8833ecff6dd-k8s-arc-enabled"),
        ("terraform", "37-k8s-arc", "37-law", "37-k8s-arc-enabled"),
    ):
        monitoring_script = monitoring.replace("<Arc Resource Group>", group).replace("<Log Analytics Workspace>", workspace)
        list_command = f"connectedk8s list --resource-group {group} --query [].name --output tsv"
        workspace_command = f"monitor log-analytics workspace show --resource-group {group} --workspace-name {workspace} --query id -o tsv"
        workspace_id = f"/subscriptions/test/resourceGroups/{group}/providers/Microsoft.OperationalInsights/workspaces/{workspace}"
        extension_command = (
            f"k8s-extension create --name azuremonitor-containers --cluster-name {cluster} "
            f"--resource-group {group} --cluster-type connectedClusters "
            "--extension-type Microsoft.AzureMonitor.Containers --configuration-settings "
            f"azure-monitor-workspace-resource-id={workspace_id}"
        )
        responses = {list_command: cluster, workspace_command: workspace_id, extension_command: "{}"}
        check_onboarding(
            f"monitoring-{label}", responses,
            ("", group, cluster, ""),
            script=monitoring_script + f"\n[ \"$user_number\" = {shlex.quote(cluster.removesuffix('-k8s-arc-enabled'))} ]\n",
        )
        if label == "hb-0009":
            for case, response, error in (
                ("no-cluster", "", "Expected exactly one Arc cluster"),
                ("multiple-clusters", cluster + "\nother-cluster", "Expected exactly one Arc cluster"),
                ("denied", (1, "AuthorizationFailed"), "AuthorizationFailed"),
            ):
                check_onboarding(
                    f"monitoring-{case}", {list_command: response},
                    error=error, script=monitoring_script,
                )
            check_onboarding(
                "monitoring-workspace-denied",
                {list_command: cluster, workspace_command: (1, "AuthorizationFailed")},
                error="AuthorizationFailed", script=monitoring_script,
            )

llm_walkthrough = (
    root.parent / "walkthrough" / "challenge-03" / "solution-03.md"
).read_text(encoding="utf-8")
llm_blocks = re.findall(r"```bash\n(.*?)```", llm_walkthrough, re.S)
for block in llm_blocks:
    subprocess.run([bash, "-n"], input=block, text=True, encoding="utf-8", check=True)
install_blocks = [block for block in llm_blocks if block.startswith("helm install ")]
assert len(install_blocks) == 2
for block in install_blocks:
    arguments = shlex.split(block.replace("\\\n", ""))
    assert "--wait" in arguments
    assert arguments[arguments.index("--timeout") + 1] == "20m"
step_one = llm_walkthrough.split("### Step 1:", 1)[1].split("### Step 2:", 1)[0]
readiness = re.findall(r"```bash\n(.*?)```", step_one, re.S)[1]
assert "--timeout=20m &&" in readiness
for rollout_status, model_status in ((0, 0), (1, 0), (0, 1)):
    stub = f"""
kubectl() {{
    case "$*" in
        'rollout status deployment/ollama --namespace aimh --timeout=20m')
            echo ROLLOUT_CHECK
            return {rollout_status} ;;
        'exec --namespace aimh deployment/ollama -- ollama show phi4-mini:latest')
            echo MODEL_CHECK
            return {model_status} ;;
        *) echo "Unexpected kubectl command: $*" >&2; return 98 ;;
    esac
}}
"""
    result = subprocess.run(
        [bash, "-s"], input=stub + readiness,
        text=True, encoding="utf-8", capture_output=True,
    )
    assert result.returncode == (rollout_status or model_status), result
    assert ("MODEL_CHECK" in result.stdout) == (rollout_status == 0)

data_walkthrough = (
    root.parent / "walkthrough" / "challenge-04" / "solution-04.md"
).read_text(encoding="utf-8")
data_blocks = re.findall(r"```bash\n(.*?)```", data_walkthrough, re.S)
assert not re.search(r"\bexit\s+1\b", "\n".join(data_blocks))
for block in data_blocks:
    subprocess.run([bash, "-n"], input=block, text=True, encoding="utf-8", check=True)
data_setup, data_parameters = data_blocks[:2]
sqlmi_setup = next(
    line for block in data_blocks for line in block.splitlines()
    if line.startswith("export sqlmi_name=")
)
data_connection = next(
    block
    for block in data_blocks if "master_vm_name=$(az vm list" in block
)
source_parameters = (
    root.parent / "walkthrough" / "challenge-04" / "templates" / "parameters.json"
).read_text(encoding="utf-8")
with tempfile.TemporaryDirectory(prefix="microhack-k8s-data-names-") as directory:
    for label, group, workspace, prefix, master, onprem, region in (
        ("hb-0009", "rg-labuser-0009", "labuser-0009-law", "labuser-0009", "k8s7bbc1170d029-k8s-master", "rg-labuser-0009-onprem", "swedencentral"),
        ("hb-0020", "rg-labuser-0020", "labuser-0020-law", "labuser-0020", "k8sc8833ecff6dd-k8s-master", "rg-labuser-0020-onprem", "germanywestcentral"),
        ("terraform", "37-k8s-arc", "37-law", "37", "37-k8s-master", "37-k8s-onprem", "westeurope"),
    ):
        home = pathlib.Path(directory) / label
        parameters_directory = home / "walkthrough" / "challenge-04" / "templates"
        parameters_directory.mkdir(parents=True)
        (parameters_directory / "parameters.json").write_text(source_parameters, encoding="utf-8")
        (parameters_directory / "parameters-my.json").write_text("{}", encoding="utf-8")
        cluster = master.removesuffix("-k8s-master") + "-k8s-arc-enabled"
        workspace_id = "00000000-0000-0000-0000-000000000001"
        responses = {
            f"connectedk8s show --resource-group {group} --name {cluster} --query location --output tsv": region,
            f"monitor log-analytics workspace show -g {group} -n {workspace} --query customerId -o tsv": workspace_id,
            f"monitor log-analytics workspace get-shared-keys -g {group} -n {workspace} --query primarySharedKey -o tsv": "TEST/KEY&ONLY",
            f"vm list --resource-group {onprem} --query [?ends_with(name, '-k8s-master')].name | [0] --output tsv": master,
            f"vm list-ip-addresses --resource-group {onprem} --name {master} --query [0].virtualMachine.network.privateIpAddresses[0] --output tsv": "10.2.1.10",
        }
        cases = [
            f"{shlex.quote(command)}) printf '%s\\n' {shlex.quote(value)} ;;"
            for command, value in responses.items()
        ]
        stub = (
            'set -e\nexport HOME="$1"\ncd "$HOME"\n'
            f"export arc_resource_group={shlex.quote(group)} arc_cluster_name={shlex.quote(cluster)} workspace_name={shlex.quote(workspace)}\n"
            # A stale numeric value must not affect the new names.
            "export user_number=9 location=westeurope\nunset onprem_resource_group\n"
            'az() { case "$*" in\n' + "\n".join(cases)
            + '\n*) echo "Unexpected Azure command: $*" >&2; return 98 ;; esac; }\n'
            + 'kubectl() { case "$*" in\n'
            + f"{shlex.quote(f'get svc sqlmi-{prefix}-1-external-svc -n {prefix}-arc-data-controller -o jsonpath={{.spec.ports[0].nodePort}}')}) echo 31433 ;;\n"
            + '*) echo "Unexpected kubectl command: $*" >&2; return 98 ;; esac; }\n'
        )
        result = subprocess.run(
            [bash, "-s", "--", home.as_posix()],
            input=stub + data_setup + data_parameters + "\n" + sqlmi_setup + "\n" + data_connection
                + '\nprintf "RESULT=%s|%s|%s|%s\\n" "$data_controller_name" "$sqlmi_name" "$master_vm_name" "$master_ip,$node_port"\n',
            text=True, encoding="utf-8", capture_output=True,
        )
        assert result.returncode == 0, result.stderr
        assert f"RESULT={prefix}-dc|sqlmi-{prefix}-1|{master}|10.2.1.10,31433" in result.stdout
        assert "TEST/KEY&ONLY" not in result.stdout
        parameters = json.loads((parameters_directory / "parameters-my.json").read_text(encoding="utf-8"))["parameters"]
        for key, value in {
            "connectedClusterName": cluster,
            "location": region,
            "k8sExtensionName": f"{prefix}-arc-data-controller-ext",
            "namespace": f"{prefix}-arc-data-controller",
            "customLocationName": f"{prefix}-arc-data-controller",
            "dataControllerName": f"{prefix}-dc",
            "dataController_logAnalyticsWorkspaceId": workspace_id,
            "dataController_logAnalyticsPrimaryKey": "TEST/KEY&ONLY",
        }.items():
            assert parameters[key]["value"] == value, (key, parameters[key]["value"])

for scenario in ("master-denied", "master-empty", "ip-denied", "ip-empty", "port-denied", "port-empty"):
    responses = {}
    for lookup, value in (("master", "test-k8s-master"), ("ip", "10.2.1.10"), ("port", "31433")):
        if scenario == f"{lookup}-denied":
            responses[lookup] = "echo AuthorizationFailed >&2; return 1"
        elif scenario == f"{lookup}-empty":
            responses[lookup] = "return 0"
        else:
            responses[lookup] = f"echo {shlex.quote(value)}"
    stub = (
        "set -eu\nonprem_resource_group=rg-labuser-0009-onprem\n"
        "sqlmi_name=sqlmi-labuser-0009-1\nnamespace=labuser-0009-arc-data-controller\n"
        'az() { case "$*" in\n'
        + "'vm list '*) echo MASTER_LOOKUP >&2; " + responses["master"] + " ;;\n"
        + "'vm list-ip-addresses '*) echo IP_LOOKUP >&2; " + responses["ip"] + " ;;\n"
        + "*) echo UNEXPECTED_LOOKUP >&2; return 98 ;; esac; }\n"
        + "kubectl() { echo PORT_LOOKUP >&2; " + responses["port"] + "; }\n"
    )
    result = subprocess.run(
        [bash, "-s"], input=stub + data_connection + "\necho SHELL_STILL_RUNNING\n",
        text=True, encoding="utf-8", capture_output=True,
    )
    assert result.returncode == 0, result.stderr
    assert "SHELL_STILL_RUNNING" in result.stdout
    assert "Connection details:" not in result.stdout
    assert "Error: Could not retrieve" in result.stderr
    assert "UNEXPECTED_LOOKUP" not in result.stderr
    assert ("IP_LOOKUP" in result.stderr) == (not scenario.startswith("master-"))
    assert ("PORT_LOOKUP" in result.stderr) == scenario.startswith("port-")

data_template = json.loads(
    (root.parent / "walkthrough" / "challenge-04" / "templates" / "template.json").read_text(encoding="utf-8")
)
assert "defaultValue" not in data_template["parameters"]["location"]
assert json.loads(source_parameters)["parameters"]["location"]["value"] == "<LOCATION>"
for resource in data_template["resources"]:
    if resource["type"] in (
        "Microsoft.ExtendedLocation/customLocations",
        "Microsoft.ExtendedLocation/customLocations/resourceSyncRules",
        "Microsoft.AzureArcData/dataControllers",
    ):
        assert resource["location"] == "[parameters('location')]"

deployment_script = next(
    block for block in data_blocks if "az deployment group validate" in block
)
deployment_script = "\n".join(
    line for line in deployment_script.splitlines()
    if not line.startswith("read -s ")
)
for validation_status in (0, 1):
    stub = f"""
resource_group=rg-labuser-0009
DC_PASSWORD=TEST-ONLY
az() {{
    case "$*" in
        'deployment group validate '*)
            echo VALIDATION_CHECK
            return {validation_status} ;;
        'deployment group create '*)
            echo CREATE_CHECK
            return 0 ;;
        *) echo "Unexpected Azure command: $*" >&2; return 98 ;;
    esac
}}
"""
    result = subprocess.run(
        [bash, "-s"], input=stub + deployment_script,
        text=True, encoding="utf-8", capture_output=True,
    )
    assert result.returncode == validation_status, result
    assert ("CREATE_CHECK" in result.stdout) == (validation_status == 0)

with tempfile.TemporaryDirectory(prefix="microhack-k8s-region-errors-") as directory:
    for status, response in ((1, "AuthorizationFailed"), (0, "")):
        stub = (
            'export HOME="$1"\n'
            "arc_resource_group=rg-labuser-0009\narc_cluster_name=test-cluster\nworkspace_name=labuser-0009-law\n"
            'az() { case "$*" in\n'
            + f"'connectedk8s show '*) printf '%s\\n' {shlex.quote(response)}; return {status} ;;\n"
            + '*) echo "UNEXPECTED_LOOKUP" >&2; return 98 ;; esac; }\n'
        )
        result = subprocess.run(
            [bash, "-s", "--", pathlib.Path(directory).as_posix()],
            input=stub + "set -eu\n" + data_setup + "\necho SHELL_STILL_RUNNING\n",
            text=True, encoding="utf-8", capture_output=True,
        )
        assert result.returncode == 0
        assert "SHELL_STILL_RUNNING" in result.stdout
        assert "Step 1 failed" in result.stderr
        assert "UNEXPECTED_LOOKUP" not in result.stderr
        assert "Your values:" not in result.stdout

with tempfile.TemporaryDirectory(prefix="microhack-k8s-interactive-errors-") as directory:
    for scenario in (
        "missing-arc_resource_group",
        "missing-arc_cluster_name",
        "missing-workspace_name",
        "invalid-name",
        "workspace-denied",
        "key-denied",
    ):
        context = {
            "arc_resource_group": "rg-labuser-0009",
            "arc_cluster_name": "test-cluster",
            "workspace_name": "labuser-0009-law",
        }
        if scenario.startswith("missing-"):
            context.pop(scenario.removeprefix("missing-"))
        if scenario == "invalid-name":
            context["arc_resource_group"] = "rg-invalid_name"
        stub = (
            'set -eu\nexport HOME="$1"\nunset arc_resource_group arc_cluster_name workspace_name\n'
            + "\n".join(f"export {key}={shlex.quote(value)}" for key, value in context.items())
            + '\naz() { case "$*" in\n'
            + "'connectedk8s show '*) echo swedencentral ;;\n"
            + "'monitor log-analytics workspace show '*) "
            + ('echo AuthorizationFailed >&2; return 1' if scenario == "workspace-denied" else 'echo test-workspace-id')
            + " ;;\n'monitor log-analytics workspace get-shared-keys '*) echo AuthorizationFailed >&2; return 1 ;;\n"
            + '*) echo UNEXPECTED_LOOKUP >&2; return 98 ;; esac; }\n'
        )
        result = subprocess.run(
            [bash, "-s", "--", pathlib.Path(directory).as_posix()],
            input=stub + data_setup + "\necho SHELL_STILL_RUNNING\n",
            text=True, encoding="utf-8", capture_output=True,
        )
        assert result.returncode == 0, result
        assert "SHELL_STILL_RUNNING" in result.stdout
        assert "Step 1 failed" in result.stderr
        assert "Your values:" not in result.stdout
        assert "Step 1 completed" not in result.stdout
        assert "UNEXPECTED_LOOKUP" not in result.stderr

print("Validated guest artifacts, onboarding, monitoring, Ollama readiness and 3 data-service naming/template cases.")
