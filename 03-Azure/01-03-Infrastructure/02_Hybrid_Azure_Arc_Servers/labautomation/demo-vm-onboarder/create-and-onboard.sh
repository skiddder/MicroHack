############################################################################################
#                                                                                          #
#    Make sure to adjust the parameters in both scripts to match your intended values!!!   #
#                                                                                          #
############################################################################################

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" || exit 1

# create the VMs
bash "$script_dir/../demo-vm-creator/create_vms.sh" || exit $?

# onboard the VMs
bash "$script_dir/arc-enable-vms.sh"