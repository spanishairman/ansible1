#!/bin/bash
# Изменяем диапазон адресов для резервирования. Добавляем виртуальную машину с резервированием
virsh net-update vagrant-libvirt-mgmt add ip-dhcp-range "<range start='192.168.121.21' end='192.168.121.254'/>" --live --config
virsh net-update vagrant-libvirt-mgmt delete ip-dhcp-range "<range start='192.168.121.31' end='192.168.121.254'/>" --live --config
virsh net-update vagrant-libvirt-mgmt add ip-dhcp-host "<host mac=52:54:00:27:28:84 name=Debian12-2 ip=192.168.121.11 />" --live --config
