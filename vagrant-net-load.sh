#!/bin/bash
virsh net-define vagrant-libvirt-mgmt.xml
virsh net-start vagrant-libvirt-mgmt
