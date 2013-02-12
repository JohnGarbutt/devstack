#!/bin/bash

uninstall()
{
    local uuid="$1"
    xe vm-unpause uuid=$uuid || true
    xe vm-shutdown uuid=$uuid || true
    xe vm-destroy uuid=$uuid
}

uninstall_template()
{
    local uuid="$1"
    xe template-uninstall template-uuid=$uuid force=true
}

clean_previous_runs()
{
    CLEAN_TEMPLATES=${CLEAN_TEMPLATES:-false}
    if $CLEAN_TEMPLATES; then
      for u in $(xe template-list other-config:os-vpx=true --minimal | sed -e 's/,/ /g'); do
        uninstall_template "$u"
      done
    fi
    
    for u in $(xe vm-list other-config:os-vpx=true --minimal | sed -e 's/,/ /g'); do
      uninstall "$u"
    done

    for u in `xe vm-list | grep -1 instance | grep uuid | sed "s/.*\: //g"`; do
        uninstall $u
    done

    for uuid in `xe vdi-list | grep -1 Glance | grep uuid | sed "s/.*\: //g"`; do
        xe vdi-destroy uuid=$uuid
    done
}
