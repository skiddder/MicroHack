#!/usr/bin/env bash
set -euo pipefail

lab_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
export package_dir="$test_root/lab automation"
export calls_file="$test_root/calls"
export references_file="$test_root/references"
export playbooks_file="$test_root/playbooks"
export groups_file="$test_root/groups"
export errors_file="$test_root/unexpected-errors"
export mock_group_exists=false
cp -R -- "$lab_dir" "$package_dir"
touch "$calls_file" "$references_file" "$playbooks_file" "$groups_file" "$errors_file"

while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(find "$package_dir" -name '*.sh' -print0)

az() {
    printf '%s %s %s\n' "${1-}" "${2-}" "${3-}" >> "$calls_file"
    local arg previous="" tags="" operation="" group_name="" resource_id="" resource_group=""
    for arg in "$@"; do
        case "$previous" in
            '--tags') tags="$arg" ;;
            '--operation') operation="$arg" ;;
            '--name') group_name="$arg" ;;
            '--resource-group') resource_group="$arg" ;;
            '--resource-id') resource_id="$arg" ;;
        esac
        if [[ "$previous" == "--template-file" || "$arg" == @* ]]; then
            local path="${arg#@}"
            [[ "$path" == "$package_dir/"* && -f "$path" ]] || {
                echo "Missing or non-package setup file: $path" >&2
                return 1
            }
            printf '%s\n' "$path" >> "$references_file"
        fi
        previous="$arg"
    done
    case "$1 $2" in
        'group exists') printf '%s\n' "$mock_group_exists" ;;
        'group show') printf '/subscriptions/offline-subscription/resourceGroups/%s\n' "$group_name" ;;
        'group create')
            [[ "$tags" == 'SecurityControl=Ignore' ]] || { echo 'RG must be tagged at creation' >&2; return 1; }
            [[ "${mock_group_create_failure:-false}" != true ]] || return 1
            printf '%s\n' "$group_name" >> "$groups_file"
            printf '%s\n' '{"tags":{"SecurityControl":"Ignore"}}'
            ;;
        'tag update')
            [[ "$tags" == 'SecurityControl=Ignore' && "$operation" == Merge ]] || {
                echo 'Existing RG tags must be merged with SecurityControl=Ignore' >&2; return 1;
            }
            [[ "${mock_tag_failure:-false}" != true ]] || return 1
            printf '%s\n' "${resource_id##*/}" >> "$groups_file"
            printf '%s\n' '{"properties":{"tags":{"SecurityControl":"Ignore"}}}'
            ;;
        'deployment group')
            grep -Fxq -- "$resource_group" "$groups_file" || {
                echo 'VM deployment attempted before RG tagging' | tee -a "$errors_file" >&2; return 1;
            }
            printf '%s\n' '{}'
            ;;
        'account show') printf '%s\n' 'offline-subscription' ;;
        'ad sp') printf '%s\n' '{"tenant":"offline-tenant","appId":"offline-app","password":"offline-secret"}' ;;
        'vm list') printf '%s\n' '[{"name":"vm-linux-mh0","storageProfile":{"osDisk":{"osType":"Linux"}}},{"name":"vm-win2025-mh0","storageProfile":{"osDisk":{"osType":"Windows"}}}]' ;;
        'vm list-ip-addresses') printf '%s\n' '203.0.113.10' ;;
        *) printf '%s\n' '{}' ;;
    esac
}

jq() {
    local input query="${*: -1}"
    input="$(cat)"
    case "$query" in
        '.tenant') printf '%s\n' 'offline-tenant' ;;
        '.appId') printf '%s\n' 'offline-app' ;;
        '.password') printf '%s\n' 'offline-secret' ;;
        '.[]')
            printf '%s\n' '{"name":"vm-linux-mh0","storageProfile":{"osDisk":{"osType":"Linux"}}}' '{"name":"vm-win2025-mh0","storageProfile":{"osDisk":{"osType":"Windows"}}}'
            ;;
        '.name')
            if [[ "$input" == *Windows* ]]; then printf '%s\n' 'vm-win2025-mh0'; else printf '%s\n' 'vm-linux-mh0'; fi
            ;;
        '.id') printf '%s\n' '/offline/vm' ;;
        '.storageProfile.osDisk.osType')
            if [[ "$input" == *Windows* ]]; then printf '%s\n' 'Windows'; else printf '%s\n' 'Linux'; fi
            ;;
        *) echo "Unexpected jq query: $query" >&2; return 1 ;;
    esac
}

ansible-playbook() {
    [[ "$1" == "$package_dir/demo-vm-onboarder/"* && -f "$1" ]] || {
        echo "Playbook must resolve inside the setup package: $1" >&2
        return 1
    }
    grep -q "service_principal_id: 'offline-app'" "$1"
    grep -q "service_principal_secret: 'offline-secret'" "$1"
    printf '%s\n' "$1" >> "$playbooks_file"
}
export -f az jq ansible-playbook

cd /
bash "$package_dir/demo-vm-creator/create_vms.sh" > "$test_root/creator.log"
[[ "$(wc -l < "$calls_file")" -eq 62 ]]
[[ "$(wc -l < "$references_file")" -eq 90 ]]

bash "$package_dir/demo-vm-onboarder/arc-enable-vms.sh" > "$test_root/onboarder.log"
[[ "$(wc -l < "$playbooks_file")" -eq 2 ]]

export mock_group_exists=true
bash "$package_dir/demo-vm-onboarder/create-and-onboard.sh" > "$test_root/combined.log"
[[ "$(wc -l < "$calls_file")" -eq 142 ]]
[[ "$(wc -l < "$references_file")" -eq 180 ]]
[[ "$(wc -l < "$playbooks_file")" -eq 4 ]]
[[ ! -s "$errors_file" ]]
[[ "$(grep -c 'deployment group create' "$calls_file")" -eq 60 ]]
[[ "$(grep -c 'vm run-command' "$calls_file")" -eq 60 ]]
[[ "$(grep -c '^group create ' "$calls_file")" -eq 2 ]]
[[ "$(grep -c 'tag update' "$calls_file")" -eq 2 ]]

for script in "$package_dir/demo-vm-creator/create_vms.sh" "$package_dir/demo-vm-onboarder/arc-enable-vms.sh"; do
    if mock_tag_failure=true bash "$script" > "$test_root/tag-failure.log" 2>&1; then
        echo 'Tag failure must stop the demo entry point' >&2; exit 1
    fi
    if mock_group_exists=false mock_group_create_failure=true bash "$script" > "$test_root/create-failure.log" 2>&1; then
        echo 'Tagged RG creation failure must stop the demo entry point' >&2; exit 1
    fi
done
if mock_group_exists=invalid bash "$package_dir/demo-vm-creator/create_vms.sh" > "$test_root/exists-failure.log" 2>&1; then
    echo 'Invalid RG existence response must stop deployment' >&2; exit 1
fi
before="$(wc -l < "$calls_file")"
if mock_tag_failure=true bash "$package_dir/demo-vm-onboarder/create-and-onboard.sh" > "$test_root/combined-failure.log" 2>&1; then
    echo 'Creator tag failure must stop the combined demo before onboarding' >&2; exit 1
fi
[[ "$(wc -l < "$calls_file")" -eq $((before + 3)) ]]
[[ "$(grep -c 'deployment group create' "$calls_file")" -eq 60 ]]
[[ "$(wc -l < "$playbooks_file")" -eq 4 ]]

echo "PASS: demos resolve 180 setup references and 4 playbooks; new/existing RGs are tagged before deployment, and tag failures stop execution. All $(wc -l < "$calls_file") Azure calls were mocked."
