#!/bin/bash

function wait_for_VM_to_halt() {
    $GUEST_NAME="$1"
    set +x
    echo "Waiting for the VM to halt.  Progress in-VM can be checked with vncviewer:"
    mgmt_ip=$(echo $XENAPI_CONNECTION_URL | tr -d -c '1234567890.')
    domid=$(xe vm-list name-label="$GUEST_NAME" params=dom-id minimal=true)
    port=$(xenstore-read /local/domain/$domid/console/vnc-port)
    echo "vncviewer -via $mgmt_ip localhost:${port:2}"
    while true
    do
        state=$(xe vm-list name-label="$GUEST_NAME" power-state=halted --minimal)
        if [ -n "$state" ]
        then
            break
        else
            echo -n "."
            sleep 20
        fi
    done
    set -x
}

create_ubuntu_install_template()
{
    # always update the preseed file, incase we have a newer one
    PRESEED_URL=${PRESEED_URL:-""}
    if [ -z "$PRESEED_URL" ]; then
        PRESEED_URL="${HOST_IP}/devstackubuntupreseed.cfg"
        HTTP_SERVER_LOCATION="/opt/xensource/www"
        if [ ! -e $HTTP_SERVER_LOCATION ]; then
            HTTP_SERVER_LOCATION="/var/www/html"
            mkdir -p $HTTP_SERVER_LOCATION
        fi
        cp -f $XENAPI_DIR/lib/ubuntu/devstackubuntupreseed.cfg $HTTP_SERVER_LOCATION
        MIRROR=${MIRROR:-""}
        if [ -n "$MIRROR" ]; then
            sed -e "s,d-i mirror/http/hostname string .*,d-i mirror/http/hostname string $MIRROR," \
                -i "${HTTP_SERVER_LOCATION}/devstackubuntupreseed.cfg"
        fi
    fi

    # Update the template
    $XENAPI_DIR/lib/ubuntu/install_ubuntu_template.sh $PRESEED_URL
}

inject_script_to_install_xenserver_tools()
{
    $XENAPI_DIR/lib/ubuntu/prepare_guest_template.sh "$GUEST_NAME"
}

create_template_from_vm()
{
    SNAME_PREPARED="template_prepared"
    snuuid=$(xe vm-snapshot vm="$GUEST_NAME" new-name-label="$SNAME_PREPARED")
    xe snapshot-clone uuid=$snuuid new-name-label="$TNAME"
    xe vm-destroy vm="$SNAME_PREPARED"
}

destroy_vifs()
{
  local v="$1"
  (IFS=,
  for vif in $(xe vif-list vm-uuid="$v" --minimal); do
    xe vif-destroy uuid="$vif"
  done
  unset IFS)
}

set_kernel_params()
{
  local v="$1"
  local args="$2"
  if [ "$args" != "" ]; then
    pvargs=$(xe vm-param-get param-name=PV-args uuid="$v")
    args="$pvargs $args"
    xe vm-param-set PV-args="$args" uuid="$v"
  fi
}

set_memory()
{
  local v="$1"
  local RAM="$2"
  if [ "$RAM" != "" ]; then
    RAM_MIN=$RAM
    xe vm-memory-limits-set static-min=16MiB static-max=${RAM}MiB \
                            dynamic-min=${RAM_MIN}MiB dynamic-max=${RAM}MiB \
                            uuid="$v"
  fi
}


find_network()
{
  result=$(xe network-list bridge="$1" --minimal)
  if [ "$result" = "" ]
  then
    result=$(xe network-list name-label="$1" --minimal)
  fi
  echo "$result"
}

install_ubuntu_over_network()
{

    create_ubuntu_install_template

    vm_uuid=$(xe vm-install template="$UBUNTU_INST_TEMPLATE_NAME" new-name-label="$GUEST_NAME" --minimal)
    destroy_vifs "$vm_uuid"
    xe vm-param-set uuid="$v" other-config:auto_poweron=true
    set_kernel_params "$vm_uuid" "flat_network_bridge=${VM_BR}"
    xe vm-param-set other-config:os-vpx=true uuid="$vm_uuid"
    set_memory "$vm_uuid" $OSDOMU_MEM_MB
    xe vif-create vm-uuid="$vm_uuid" network-uuid="$(find_network $MGT_BR)" device="0"

    xe vm-start vm="$GUEST_NAME"
    wait_for_VM_to_halt $GUEST_NAME

    inject_script_to_install_xenserver_tools
    
    xe vm-start vm="$GUEST_NAME"
    wait_for_VM_to_halt $GUEST_NAME

    create_template_from_vm
}

create_ubuntu_template_if_required()
{
    templateuuid=$(xe template-list name-label="$TNAME")
    if [ -z "$templateuuid" ]; then
        install_ubuntu_over_network
    fi
}

create_ubuntu_vm()
{
    xe vm-install template="$TNAME" new-name-label="$GUEST_NAME"
}