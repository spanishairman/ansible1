### Автоматизация администрирования. Ansible-1
#### Подготовка окружения
##### Проблема с сетевыми интерфейсами
В нашем примере используется гипервизор Qemu-KVM, библиотека Libvirt. В качестве хостовой системы - OpenSuse Leap 15.5.

Для работы Vagrant с Libvirt установлен пакет vagrant-libvirt:
```
Сведения — пакет vagrant-libvirt:
---------------------------------
Репозиторий            : Основной репозиторий
Имя                    : vagrant-libvirt
Версия                 : 0.10.2-bp155.1.19
Архитектура            : x86_64
Поставщик              : openSUSE
Размер после установки : 658,3 KiB
Установлено            : Да
Состояние              : актуален
Пакет с исходным кодом : vagrant-libvirt-0.10.2-bp155.1.19.src
Адрес источника        : https://github.com/vagrant-libvirt/vagrant-libvirt
Заключение             : Провайдер Vagrant для libvirt
Описание               : 

    This is a Vagrant plugin that adds a Libvirt provider to Vagrant, allowing
    Vagrant to control and provision machines via the Libvirt toolkit.
```
Образ операционной системы создём заранее, для этого установим [Debian Linux из официального образа netinst](https://www.debian.org/distrib/netinst)

Vagrant-libvirt при работе с виртуальными сетями использует первую сетевую карту виртуального хоста в качестве NAT-подключения для управления этим хостом. 

Можно добавить в файл Vagrantfile информацию о дополнительных сетевых интерфейсах, например так:
```
  config.vm.network :private_network,
    :type => "dhcp",
    :libvirt__network_name => "vagrant-libvirt-guests",
    :libvirt__network_address => "192.168.123.0",
    :libvirt__netmask => "255.255.255.0",
    :libvirt__dhcp_enabled => true,
    :libvirt__dhcp_start => "192.168.123.31",
    :libvirt__forward_mode => "none",
    :libvirt__always_destroy => "true"
```
Или так:
```
config.vm.network "private_network", ip: "192.168.33.10"
```
При этом, дополнительный сетевой интерфейс становится первым по порядку, а интерфейс для управления не получает динамический адрес 
от DHCP-службы libvirt и Vagrant висит с выводом сообщения:
```
Waiting for domain to get an IP address...
```
Если же явно указать номер адаптера для частной сети, например, таким образом:
```
config.vm.network "private_network", ip: "192.168.33.10", adapter: "2", type: "ip"
```
То при запуске машины с помощью команды:
```
vagrant up
```
уже ruby вылетает с выводом:
```
ERROR warden: Error occurred: no implicit conversion of String into Integer
 INFO warden: Beginning recovery process...
 INFO warden: Calling recover: #<VagrantPlugins::ProviderLibvirt::Action::CleanupOnFailure:0x0000556cc3635878>
 INFO runner: Running action: machine_action_up #<Vagrant::Action::Builder:0x00007f522c5d9898>
 INFO warden: Calling IN action: #<Vagrant::Action::Builtin::ConfigValidate:0x00007f522c8068f0>
 INFO warden: Calling IN action: #<Vagrant::Action::Builtin::Call:0x00007f522c8068c8>
 INFO runner: Running action: machine_action_up #<Vagrant::Action::Builder:0x00007f522cb8e5b8>
 INFO warden: Calling IN action: #<VagrantPlugins::ProviderLibvirt::Action::IsCreated:0x00007f522d2629c0>
 INFO warden: Calling IN action: #<VagrantPlugins::CommandUp::StoreBoxMetadata:0x00007f522d262998>
```
##### Решение
Для того, чтобы обойти возникшую проблему, будем использовать сеть управления в качестве основной и единственной.

Заранее создадим новую сеть с именем vagrant-libvirt-mgmt. Для этого используем командный файл [vagrant-net-load.sh](vagrant-net-load.sh).
```
#!/bin/bash
virsh net-define vagrant-libvirt-mgmt.xml
virsh net-start vagrant-libvirt-mgmt
```
Пример содержимого файла [vagrant-libvirt-mgmt.xml](vagrant-libvirt-mgmt.xml) с параметрами новой сети:
```
<network ipv6='no'>
  <name>vagrant-libvirt-mgmt</name>
  <uuid>9f7515fb-3f42-45ec-8285-2c96f25a72a5</uuid>
  <forward mode='nat'/>
  <bridge name='virbr1' stp='on' delay='0'/>
  <mac address='52:54:00:43:65:2b'/>
  <ip address='192.168.121.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.121.31' end='192.168.121.254'/>
      <host mac='52:54:00:27:28:83' name='Debian12' ip='192.168.121.10'/>
    </dhcp>
  </ip>
</network>
```
Здесь мы указали среди прочих параметров, диапазон выдачи ip-адресов для DHCP-сервера, а также зарезервировали 
ip-адрес "192.168.121.10" для виртуальной машины с mac-адресом сетевой карты "52:54:00:27:28:83".

Для дальнейшего изменения настроек, например, в случае добавления новой виртуальной машины, с необходимостью 
резервирования для неё ip-адреса за диапазоном выдаваемых адресов, используем командный [файл](vagrant-net-reload.sh) со следующим содержимым:
```
#!/bin/bash
# Изменяем диапазон адресов для резервирования. Добавляем виртуальную машину с резервированием
virsh net-update vagrant-libvirt-mgmt add ip-dhcp-range "<range start='192.168.121.21' end='192.168.121.254'/>" --live --config
virsh net-update vagrant-libvirt-mgmt delete ip-dhcp-range "<range start='192.168.121.31' end='192.168.121.254'/>" --live --config
virsh net-update vagrant-libvirt-mgmt add ip-dhcp-host "<host mac=52:54:00:27:28:84 name=Debian12-2 ip=192.168.121.11 />" --live --config
```
В этом примере также изменяется диапазон адресов, исключённых из автоматической выдачи.

Все изменения, вносимые таким образом, применяются "на лету" и не требуют перезапуска виртуальной сети.
Теперь, после подготовки сетевой инфраструктуры, создадим [Vagrantfile](Vagrantfile).

Нас интересует следующий блок настроек:
```
  config.vm.provider "libvirt" do |lv|
    lv.memory = "2048"
    lv.cpus = "2"
    lv.title = "Debian12"
    lv.description = "Виртуальная машина на базе дистрибутива Debian Linux"
    lv.management_network_name = "vagrant-libvirt-mgmt"
    lv.management_network_address = "192.168.121.0/24"
    lv.management_network_keep = "true"
    lv.management_network_mac = "52:54:00:27:28:83"
  end
```
в нём мы указали имя уже созданной сети "vagrant-libvirt-mgmt", в которой заданы:
  - адресация, 
  - mac-адрес сетевого интерфейса создаваемой виртуальной машины, именно он был указан для резервирования в файле [vagrant-libvirt-mgmt.xml](vagrant-libvirt-mgmt.xml),
  - ключ "lv.management_network_keep" со значением "true".
Последний параметр указывает vagrant, что при уничтожении виртуальной машины, удалять сеть "vagrant-libvirt-mgmt" не нужно, 
только если она не была создана в процессе разворачивания данной виртальной машины.
#### Ansible
Вывод параметров подключения к виртуальной машине:
```
max@localhost:~/vagrant/vg3> vagrant ssh-config 
Host Debian12
  HostName 192.168.121.10
  User vagrant
  Port 22
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  PasswordAuthentication no
  IdentityFile /home/max/vagrant/vg3/.vagrant/machines/Debian12/libvirt/private_key
  IdentitiesOnly yes
  LogLevel FATAL
```
Содержимое [inventory](staging/hosts) файла ./staging/hosts:
```
[webserver]
Debian12 ansible_host=192.168.121.10 ansible_port=22 ansible_private_key_file=/home/max/vagrant/vg3/.vagrant/machines/Debian12/libvirt/private_key
```
Файл [ansible.cfg](ansible.cfg):
```
[defaults]
inventory = staging/hosts
remote_user = vagrant
host_key_checking = False
retry_files_enabled = False
```
Проверка пинга управляемой виртуальной машины:
```
max@localhost:~/vagrant/vg3> ansible Debian12 -m ping
[WARNING]: Platform linux on host Debian12 is using the discovered Python interpreter at /usr/bin/python3, but future installation of another Python interpreter could change this. See
https://docs.ansible.com/ansible/2.9/reference_appendices/interpreter_discovery.html for more information.
Debian12 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```
Проверка версии ядра, установленного на управляемой машине:
```
max@localhost:~/vagrant/vg3> ansible Debian12 -m command -a "uname -r"
[WARNING]: Platform linux on host Debian12 is using the discovered Python interpreter at /usr/bin/python3, but future installation of another Python interpreter could change this. See
https://docs.ansible.com/ansible/2.9/reference_appendices/interpreter_discovery.html for more information.
Debian12 | CHANGED | rc=0 >>
6.1.0-21-amd64
```
Файл [nginx.yml](nginx.yml):
```
---
- name: NGINX | Install and configure nginx
  hosts: webserver
  become: true
  vars:
    nginx_listen_port: 8080
  tasks:
    - name: update
      apt:
        update_cache=yes
      tags:
        - update apt

    - name: NGINX | Install Nginx
      apt:
        name: nginx
        state: latest
      notify:
        - restart nginx
      tags:
        - nginx-package

    - name: NGINX | Create nginx config file from template
      template:
        src: templates/nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify:
        - reload nginx
      tags:
        - nginx-configuration

  handlers:
    - name: restart nginx
      systemd:
        name: nginx
        state: restarted
        enabled: true

    - name: reload nginx
      systemd:
        name: nginx
        state: reloaded
```
Где содержимое файла [nginx.cfg.j2](templates/nginx.conf.j2):
```
# {{ ansible_managed }}
events {
    worker_connections 1024;
}

http {
    server {
        listen       {{ nginx_listen_port }} default_server;
        server_name  default_server;
        root         /usr/share/nginx/html;

        location / {
        }
    }
}
```
Проверяем файл:
```
yamllint nginx.yml
```
и запускаем:
```
max@localhost:~/vagrant/vg3> ansible-playbook nginx.yml 

PLAY [NGINX | Install and configure nginx] ****************************************************************************************************************************************************

TASK [Gathering Facts] ************************************************************************************************************************************************************************
[WARNING]: Platform linux on host Debian12 is using the discovered Python interpreter at /usr/bin/python3, but future installation of another Python interpreter could change this. See
https://docs.ansible.com/ansible/2.9/reference_appendices/interpreter_discovery.html for more information.
ok: [Debian12]

TASK [update] *********************************************************************************************************************************************************************************
changed: [Debian12]

TASK [NGINX | Install Nginx] ******************************************************************************************************************************************************************
changed: [Debian12]

TASK [NGINX | Create nginx config file from template] *****************************************************************************************************************************************
changed: [Debian12]

RUNNING HANDLER [restart nginx] ***************************************************************************************************************************************************************
changed: [Debian12]

RUNNING HANDLER [reload nginx] ****************************************************************************************************************************************************************
changed: [Debian12]

PLAY RECAP ************************************************************************************************************************************************************************************
Debian12                   : ok=6    changed=5    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0   

max@localhost:~/vagrant/vg3>
```
Проверяем доступность сайта:
```
max@localhost:~/vagrant/vg3> curl http://192.168.121.10:8080
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```
Готово!
