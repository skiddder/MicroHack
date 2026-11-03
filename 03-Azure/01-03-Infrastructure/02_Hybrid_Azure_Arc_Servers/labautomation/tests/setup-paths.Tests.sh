#!/usr/bin/env bash
set -euo pipefail

lab_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
export package_dir="$test_root/lab automation"
export calls_file="$test_root/calls"
export references_file="$test_root/references"
export playbooks_file="$test_root/playbooks"
cp -R -- "$lab_dir" "$package_dir"
touch "$calls_file" "$references_file" "$playbooks_file"

while IFS= read -r -d '' script; do
    bash -n "$script"
done < <(find "$package_dir" -name '*.sh' -print0)

az() {
    printf '%s %s %s\n' "${1-}" "${2-}" "${3-}" >> "$calls_file"
    local arg previous=""
    for arg in "$@"; do
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
[[ "$(wc -l < "$calls_file")" -eq 61 ]]
[[ "$(wc -l < "$references_file")" -eq 90 ]]

bash "$package_dir/demo-vm-onboarder/arc-enable-vms.sh" > "$test_root/onboarder.log"
[[ "$(wc -l < "$playbooks_file")" -eq 2 ]]

bash "$package_dir/demo-vm-onboarder/create-and-onboard.sh" > "$test_root/combined.log"
[[ "$(wc -l < "$calls_file")" -eq 136 ]]
[[ "$(wc -l < "$references_file")" -eq 180 ]]
[[ "$(wc -l < "$playbooks_file")" -eq 4 ]]
[[ "$(grep -c 'deployment group create' "$calls_file")" -eq 60 ]]
[[ "$(grep -c 'vm run-command' "$calls_file")" -eq 60 ]]

echo 'PASS: standalone and combined demos resolve 180 setup references and 4 playbooks from an isolated path with spaces. All 136 Azure calls were mocked.'
