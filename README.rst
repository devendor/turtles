.. Masks :index: role defined in sphinx but not github or docutils.

.. role:: index(raw)
   :format: html

Turtles All the Way Down: Snap(LXD(Docker))
===========================================


The state of container technology has evolved considerably since Stéphane Graber's `article
regarding Docker in LXD`_ over two years ago.  It served as a good but dated introduction to the
topic. This article updates and expands on the topic with experience gleaned from the current stable
versions of LXD on current Ubuntu LTS as of August 2018.

The walk through introduces `cloud-init`_ via `LXC Profile`_ for automatic provisioning of
unprivileged docker service instances and provides a known working storage configuration for
successfully running Docker Daemon within an unprivileged LXD guest.

We'll also introduce the `snapcraft`_ application container to install LXD which is the
recommended way to track current/stable LXD versions `as of LXD 3.0`_.

See Turtles `on github`_ for companion files, `on Devendor Tech`_ for prettiest formatting, and
`on medium`_ for related dialogue.

Summary
-------

The target configurations itemized below are known to work, but results should be relevant to
for other distribution that `support snap packages`_ and a modern linux kernel for the host os.

Storage pools are more finicky when running the Docker Service in an unprivileged/userns confined
container. Any block based storage should work which includes CEPH, or direct device delegation
when combined with the `overlay`_ driver for docker in the guest.

If you choose xfs behind an overlayfs docker filesystem, you'll need to ensure you enable
`d_type support`_.  EXT4 supports d_type by default.

Another known working option is using a `btrfs storage pool`_ in LXD and the `btrfs storage
driver`_ in Docker for graph storage.

`Overlay2`_ is known to work in a privileged LXD guest, but fails to unpack some Alpine based
images like memcached:alpine when running Docker/overlay2 in an unprivileged LXD guest.  The
error is thrown by tar from within the container, and seems to be due to an interaction between the
busybox implementation of the tar command and the overlay2 driver when unpacking layers on top of
Alpine.  Strangely, if you pull the image while running privileged, then stop the LXD guest,
switch it to unprivileged, and continue, you can still use these images within an unprivileged
lxd guest.

A combination of btrfs for docker graph storage and lvm storage for pass through persistent volumes
might provide an ideal combination of container optimization, and stable/high performance
persistent storage for your apps.

This approach should work on any combination of private and public cloud options and hardware to
allow deeper continuous deployment and automation and further decouple solutions from platforms.


:index:`LVM Pool with Overlay Docker Graph Storage`
---------------------------------------------------

Target Host Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~

* `Ubuntu Bionic 18.04 LTS`_
* `LXD 3.3`_ in a `snap application container`_
* Block based `LXD Storage Pool`_ using `LVMThin provisioning`_

Target Guest Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~

* `Docker Community Edition`_ version 18.06
* `Overlay`_ storage driver
* `cloud-init`_ to automatically provision docker server instance.

Walkthrough
~~~~~~~~~~~

This example starts on a google compute instance with the os on /dev/sda and an additional empty
disk on /dev/sdb.

#. Remove the default lxd daemon.

   .. code-block:: console

      root@ins2# apt remove --purge lxd lxd-client

#. Install lxd and thin provisioning tools.

   .. code-block:: console

      root@ins2# snap install lxd
      lxd 3.3 from 'canonical' installed
      root@ins2# apt -y install thin-provisioning-tools
      root@ins2# hash -r
      root@ins2# which lxd
      /snap/bin/lxd
      root@ins2# which lxc
      /snap/bin/lxc
      root@ins2# lxd --version
      3.3

#. Configure LXD. This shows the dialogue based lxd init method of configuring your lxd instance.

   .. code-block:: console

      root@ins2# lxd init
      Would you like to use LXD clustering? (yes/no) [default=no]: no
      Do you want to configure a new storage pool? (yes/no) [default=yes]: yes
      Name of the new storage pool [default=default]:
      Name of the storage backend to use (btrfs, dir, lvm) [default=btrfs]: lvm
      Create a new LVM pool? (yes/no) [default=yes]: yes
      Would you like to use an existing block device? (yes/no) [default=no]: yes
      Path to the existing block device: /dev/sdb
      Would you like to connect to a MAAS server? (yes/no) [default=no]: no
      Would you like to create a new local network bridge? (yes/no) [default=yes]:
      What should the new bridge be called? [default=lxdbr0]:
      What IPv4 address should be used? (CIDR subnet notation, “auto” or “none”) [default=auto]:
      What IPv6 address should be used? (CIDR subnet notation, “auto” or “none”) [default=auto]:
      Would you like LXD to be available over the network? (yes/no) [default=no]: no
      Would you like stale cached images to be updated automatically? (yes/no) [default=yes]
      Would you like a YAML "lxd init" preseed to be printed? (yes/no) [default=no]:

#. Create the cloud-init profile for our nested docker daemon. Note that we'll use the sparse
   example on git, and the default profile that adds a root disk and nic on in our default storage
   pool and network.

   .. code-block:: console

      root@ins2# lxc profile create docker
      Profile docker created

      root@ins2# git clone https://github.com/devendor/turtles.git
      Cloning into 'turtles'...
      remote: Counting objects: 3, done.
      remote: Compressing objects: 100% (2/2), done.
      remote: Total 3 (delta 0), reused 3 (delta 0), pack-reused 0
      Unpacking objects: 100% (3/3), done.

      root@ins2# lxc profile edit docker <turtles/docker.yml

      root@ins2# lxc profile show docker
      config:
        environment.LANG: en_US.UTF-8
        environment.LANGUAGE: en_US:en
        environment.LC_ALL: en_US.UTF-8
        linux.kernel_modules: ip_tables,overlay
        security.nesting: "true"
        security.privileged: "false"
        user.user-data: |
          #cloud-config
          output:
            all: '| tee -a /var/log/cloud-init-output.log'
          package_update: true
          package_upgrade: true
          runcmd:
            - set -xe
            - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
            - apt-get install -y apt-transport-https curl
            - add-apt-repository
              "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            - apt-get update
            - apt-get install -y
              docker-ce
              docker-compose
              vim
              git
              squashfuse
            - systemctl start docker
            - docker image pull hello-world
            - docker run hello-world
          write_files:
            - path: /etc/rsylog.conf
              content: |
                module(load="imuxsock")
                *.* @log.virtdmz
              owner: root:root
              permissions: '0644'
            - path: /etc/docker/daemon.json
              content: |
                {
                  "hosts": [
                      "fd://",
                      "tcp://0.0.0.0:2345"
                  ],
                  "storage-driver": "overlay"
                }
              permissions: '0644'
              owner: root:root
            - path: /etc/systemd/system/docker.service.d/override.conf
              content: |
                [Service]
                ExecStart=
                ExecStart=/usr/bin/dockerd
              permissions: '0644'
              owner: root:root
          users:
            - name: rferguson
              groups:
                - adm
                - sudo
              lock_passwd: true
              shell: /bin/bash
              ssh-authorized-keys:
                - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDPS4YhP...
              sudo:
                - ALL=(ALL) NOPASSWD:ALL
      description: Docker instance config.
      devices: {}
      name: docker
      used_by: []

      root@ins2# lxc profile show default
      config: {}
      description: Default LXD profile
      devices:
        eth0:
          name: eth0
          nictype: bridged
          parent: lxdbr0
          type: nic
        root:
          path: /
          pool: default
          type: disk
      name: default
      used_by: []

#. Pull the ubuntu bionic lxd image.  Note that 'b' is just an alias for ubuntu-bionic.

   .. code-block:: console

      root@ins2# lxc image copy ubuntu-daily:b local: --copy-aliases --verbose
      Image copied successfully!

#. Now we can simply launch a new instance and watch it build. Note that the first time you use
   the new image the container creation is slow.  This is due to loading the new image onto an
   lvm sparse volume.  Subsequent containers start with a snapshot and initialize much faster.

   .. code-block:: console

      root@ins2# lxc launch b dkr001 -p docker -p default &&
         sleep 3 &&
         lxc exec dkr001 -- tail -f /var/log/cloud-init-output.log
      Creating dkr001
      Starting dkr001
      Cloud-init v. 18.2 running 'init-local' at Mon, 06 Aug 2018 20:20:16 +0000. Up 3.00 seconds.
      Cloud-init v. 18.2 running 'init' at Mon, 06 Aug 2018 20:20:20 +0000. Up 7.00 seconds.
      ci-info: ++++++++++++++++++++++++Net device info+++++++++++++++++++++++++++++++++++++++
      ci-info: +--------+------+---------------+---------------+--------+-------------------+
      ci-info: | Device |  Up  | Address       |      Mask     | Scope  |     Hw-Address    |
      ci-info: +--------+------+---------------+---------------+--------+-------------------+
      ci-info: |  eth0  | True | 10.194.72.222 | 255.255.255.0 | global | 00:16:3e:2e:92:71 |
      ci-info: |  eth0  | True | fd42:.../64   |       .       | global | 00:16:3e:2e:92:71 |
      ci-info: |  eth0  | True | fe80.../64    |       .       |  link  | 00:16:3e:2e:92:71 |
      ci-info: |   lo   | True | 127.0.0.1     |   255.0.0.0   |  host  |         .         |
      ci-info: |   lo   | True | ::1/128       |       .       |  host  |         .         |
      ci-info: +--------+------+---------------+---------------+--------+-------------------+
      ...
      The following additional packages will be installed:
        aufs-tools cgroupfs-mount golang-docker-credential-helpers libltdl7
      ...
      + systemctl start docker
      + docker image pull hello-world
      Using default tag: latest
      latest: Pulling from library/hello-world
      9db2ca6ccae0: Pulling fs layer
      9db2ca6ccae0: Verifying Checksum
      9db2ca6ccae0: Download complete
      9db2ca6ccae0: Pull complete
      Digest: sha256:4b8ff392a12ed9ea17784bd3c9a8b1fa3299cac44aca35a85c90c5e3c7afacdc
      Status: Downloaded newer image for hello-world:latest
      + docker run hello-world

      Hello from Docker!
      This message shows that your installation appears to be working correctly.

      To generate this message, Docker took the following steps:
       1. The Docker client contacted the Docker daemon.
       2. The Docker daemon pulled the "hello-world" image from the Docker Hub.
          (amd64)
       3. The Docker daemon created a new container from that image which runs the
          executable that produces the output you are currently reading.
       4. The Docker daemon streamed that output to the Docker client, which sent it
          to your terminal.

      To try something more ambitious, you can run an Ubuntu container with:
       $ docker run -it ubuntu bash

      Share images, automate workflows, and more with a free Docker ID:
       https://hub.docker.com/

      For more examples and ideas, visit:
       https://docs.docker.com/engine/userguide/

      Cloud-init v. 18.2 running 'modules:final' at Mon, 06 Aug 2018 20:20:24 +0000. Up 11.00 seconds.
      Cloud-init v. 18.2 finished at Mon, 06 Aug 2018 20:21:40 +0000. Datasource DataSourceNoCloud [seed=/var/lib/cloud/seed/nocloud-net][dsmode=net].  Up 87.00 seconds

:index:`BTRFS LXD Pool with BTRFS Docker Graph Storage`
-------------------------------------------------------

Target Host Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~

* `Ubuntu Bionic 18.04 LTS`_
* `LXD 3.3`_ in a `snap application container`_
* Block based `LXD Storage Pool`_ using `LVMThin provisioning`_ for persistent passthrough volumes.
* `btrfs storage pool`_ for LXD guest filesystems.


Target Guest Configuration
~~~~~~~~~~~~~~~~~~~~~~~~~~

* `Docker Community Edition`_ version 18.06
* `btrfs storage driver`_
* `cloud-init`_ to automatically provision docker server instance.

Walkthrough
~~~~~~~~~~~

For this example, I've partitioned sdb and will use sdb1 to back my btrfs storage pool, then add
an additional LVM storage pool on sdb2 for passthrough persistent volumes.

#. Listing the partitions for reference.

   .. code-block:: console

      root@ins2# fdisk -l /dev/sdb
      Disk /dev/sdb: 10 GiB, 10737418240 bytes, 20971520 sectors
      Units: sectors of 1 * 512 = 512 bytes
      Sector size (logical/physical): 512 bytes / 4096 bytes
      I/O size (minimum/optimal): 4096 bytes / 4096 bytes
      Disklabel type: dos
      Disk identifier: 0xdaf0a82b

      Device     Boot    Start      End  Sectors Size Id Type
      /dev/sdb1           2048 10487807 10485760   5G 83 Linux
      /dev/sdb2       10487808 20971519 10483712   5G 8e Linux LVM

#. Install lxd and thin provisioning tools as we did above.


   .. code-block:: console

      # Remove the default lxd daemon.
      root@ins2# apt remove --purge lxd lxd-client

      # Install lxd and thin provisioning tools.
      root@ins2# snap install lxd
      lxd 3.3 from 'canonical' installed
      root@ins2# apt -y install thin-provisioning-tools

      root@ins2# hash -r
      root@ins2# which lxc
      /snap/bin/lxc
      root@ins2# lxd --version
      3.3


#. Configure LXD. This shows the dialogue based lxd init method of configuring your lxd instance.
   Note that we select btrfs and /dev/sdb1 in this example.

   .. code-block:: console

      root@ins2# lxd init
      Would you like to use LXD clustering? (yes/no) [default=no]:
      Do you want to configure a new storage pool? (yes/no) [default=yes]:
      Name of the new storage pool [default=default]: default
      Name of the storage backend to use (btrfs, ceph, dir, lvm, zfs) [default=zfs]: btrfs
      Create a new BTRFS pool? (yes/no) [default=yes]:
      Would you like to use an existing block device? (yes/no) [default=no]: yes
      Path to the existing block device: /dev/sdb1
      Would you like to connect to a MAAS server? (yes/no) [default=no]:
      Would you like to create a new local network bridge? (yes/no) [default=yes]:
      What should the new bridge be called? [default=lxdbr0]:
      What IPv4 address should be used? (CIDR subnet notation, “auto” or “none”) [default=auto]:
      What IPv6 address should be used? (CIDR subnet notation, “auto” or “none”) [default=auto]:
      Would you like LXD to be available over the network? (yes/no) [default=no]:
      Would you like stale cached images to be updated automatically? (yes/no) [default=yes]
      Would you like a YAML "lxd init" preseed to be printed? (yes/no) [default=no]:

#. Add the lvm pool for persistent storage.

   .. code-block:: console

      root@ins2# lxc storage create lvmPool lvm source=/dev/sdb2 lvm.vg_name=lxdVG \
            volume.block.filesystem=xfs

      Storage pool lvmPool created

      root@ins2# lxc storage ls
      +---------+-------------+--------+---------------------------+---------+
      |  NAME   | DESCRIPTION | DRIVER |           SOURCE          | USED BY |
      +---------+-------------+--------+---------------------------+---------+
      | default |             | btrfs  | 135289d9-...-4c0c8c4fe0f2 | 1       |
      +---------+-------------+--------+---------------------------+---------+
      | lvmPool |             | lvm    | lxdVG                     | 0       |
      +---------+-------------+--------+---------------------------+---------+

#. Create and load our profile again.

   .. code-block:: console

      root@ins2# lxc profile create docker
      Profile docker created

      root@ins2# git clone https://github.com/devendor/turtles.git
      Cloning into 'turtles'...
      remote: Counting objects: 3, done.
      remote: Compressing objects: 100% (2/2), done.
      remote: Total 3 (delta 0), reused 3 (delta 0), pack-reused 0
      Unpacking objects: 100% (3/3), done.

      root@ins2# lxc profile edit docker <turtles/docker-btrfs.yml

#. At this point you can pull in the lxd guest image and and launch and docker instance with the
   same steps we used above and the root filesystem of your guest will be on btrfs with docker
   running it's guest in btrfs.

   .. code-block:: console

      root@ins2# lxc image copy ubuntu-daily:b local: --copy-aliases --verbose
      root@ins2# lxc launch b dkr001 -p docker -p default

#. Enter the lxd guest and verify the results.

   .. code-block:: console

      root@ins2# lxc exec --mode interactive dkr002 -- bash -i

      root@dkr002:~# root@dkr002:~# grep ' / ' /proc/mounts
      /dev/sdb1 / btrfs rw,relatime,ssd,space_cache,user_subvol_rm_allowed,subvolid=265\
                        ,subvol=/containers/dkr002/rootfs 0 0

      root@dkr002:~# docker pull centos
      ...
      Status: Downloaded newer image for centos:latest

      root@dkr002:~# docker run --rm centos /bin/grep -- ' / ' /proc/mounts
      /dev/sdb1 / btrfs rw,relatime,ssd,space_cache,user_subvol_rm_allowed,subvol=...

Working with the container
--------------------------

The examples below start with the btrfs docker guest setup in the steps above.

:index:`LXD Proxy Devices`
~~~~~~~~~~~~~~~~~~~~~~~~~~

`LXD proxy devices`_ allow you to expose container connections through the host OS.  The example
below shows the protocol translation feature by forwarding between a unix socket on the host to a
tcp socket in the container.


.. code-block:: console

   root@ins2# apt install docker.io

   root@ins2# lxc config device add dkr002  dkr002_socket proxy \
     listen=unix:/root/dckr002-socket connect=tcp:127.0.0.1:2345
   Device dkr002_socket added to dkr002

   root@ins2# docker -H unix:///root/dckr002-socket images
   REPOSITORY          TAG                 IMAGE ID            CREATED             SIZE
   centos              latest              5182e96772bf        20 hours ago        200MB
   hello-world         latest              2cb0d9787c4d        3 weeks ago         1.85kB


DNS Resolution
~~~~~~~~~~~~~~

By default, lxd guests are added to a dnsmasq nameserver listening on your lxdbr0 interface.  The
steps below just tell the local resolver to use the dnsmasq instance for resolution.

.. code-block:: console

   root@ins2# echo -e "DNS=10.45.7.1\nCache=no\nDomains=lxd\n" >> /etc/systemd/resolved.conf

   root@ins2# systemctl restart systemd-resolved.service

   root@ins2# cat /etc/resolv.conf
   # This file is managed by man:systemd-resolved(8). Do not edit.
   # ...

   nameserver 10.0.7.1
   nameserver 169.254.169.254
   search lxd c.graphite-ruler-163617.internal google.internal

   root@ins2# systemctl restart systemd-resolved.service

   root@ins2# ping dkr002
   PING dkr002(dkr002.lxd (fd42:a35c:c565:bb31:216:3eff:fec4:3a26)) 56 data bytes
   64 bytes from dkr002.lxd (...): icmp_seq=1 ttl=64 time=0.058 ms

:index:`Using persistent lxd data volumes`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The myData volume created below persists even when we delete the LXD container it's attached to
and can be used to persist data on ephemeral LXD guests or even ephemeral Docker guests in
ephemeral LXD guests.

You can also pass block devices or bind mounts into the container directly.

.. code-block:: console

   root@ins2# lxc storage volume create
   Description:
     Create new custom storage volumes

   Usage:
     lxc storage volume create [<remote>:]<pool> <volume> [key=value...] [flags]

   Flags:
         --target   Cluster member name

   Global Flags:
         --debug         Show all debug messages
         --force-local   Force using the local unix socket
     -h, --help          Print help
     -v, --verbose       Show all information messages
         --version       Print version number

   root@ins2# lxc storage volume create lvmPool myData size=1GB \
                      block.mount_options=noatime
   Storage volume myData created

   root@ins2# lxc storage volume  attach lvmPool myData dkr002 data /data

   # using out lxd proxy to the docker daemon.
   root@ins2# export DOCKER_HOST=unix:///root/dckr002-socket
   root@ins2# docker pull postgres
   ...
   Digest: sha256:9625c2fb34986a49cbf2f5aa225d8eb07346f89f7312f7c0ea19d82c3829fdaa
   Status: Downloaded newer image for postgres:latest

   # validate the volume mount
   root@ins2# docker run --rm  -i  -v /data:/var/lib/postgres/data postgres \
       /bin/grep myData

   /proc/mounts /dev/lxdVG/custom_myData /var/lib/postgres/data xfs rw,noatime,...

   # start a postgres container in the nested docker.
   root@ins2# docker run --rm  -d -p 0.0.0.0:5432:5432 -v /data:/var/lib/postgres/data postgres

   # access postgres via the docker-proxy port via the lxd guest by name.
   root@ins2# psql -h dkr002 -U postgres
   psql (10.4 (Ubuntu 10.4-0ubuntu0.18.04))
   Type "help" for help.

   postgres=# ^D

:index:`Exploring the namespaces`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Direct namespace exploration and manipulation is one area that is extremely useful, but seldom
covered as it falls outside the envelope of the container systems built on top of kernel namespaces.

.. code-block:: console

   # From the host postgres is userns shifted +1000000 via lxd container.
   root@ins2# ps -ef |grep postgres
   1000999   5466  5444  0 16:54 ?        00:00:00 postgres
   1000999   5585  5466  0 16:55 ?        00:00:00 postgres: checkpointer process
   1000999   5586  5466  0 16:55 ?        00:00:00 postgres: writer process
   1000999   5587  5466  0 16:55 ?        00:00:00 postgres: wal writer process
   1000999   5588  5466  0 16:55 ?        00:00:00 postgres: autovacuum launcher process
   1000999   5589  5466  0 16:55 ?        00:00:00 postgres: stats collector process
   1000999   5590  5466  0 16:55 ?        00:00:00 postgres: bgworker: logical replication
   root      5772  7987  0 17:17 pts/1    00:00:00 grep --color=auto postgres

   # pstree showing uid and namespace shifts of parents starting with postgres pid 5590
   root@ins2# pstree -Salus 5590
   systemd
     └─lxd,mnt
         └─systemd,1000000,cgroup,ipc,mnt,net,pid,user,uts
             └─dockerd
                 └─docker-containe --config /var/run/docker/containerd/containerd.toml
                     └─docker-containe -namespace moby -workdir ...
                         └─postgres,1000999,ipc,mnt,net,pid,uts
                             └─postgres

   # manually entiner the docker postgres namespaces.
   root@ins2# nsenter -a -t 5590 /bin/sh -i

   # ps -ef
   UID        PID  PPID  C STIME TTY          TIME CMD
   postgres     1     0  0 16:07 ?        00:00:00 postgres
   postgres    59     1  0 16:07 ?        00:00:00 postgres: checkpointer process
   postgres    60     1  0 16:07 ?        00:00:00 postgres: writer process
   postgres    61     1  0 16:07 ?        00:00:00 postgres: wal writer process
   postgres    62     1  0 16:07 ?        00:00:00 postgres: autovacuum launcher process
   postgres    63     1  0 16:07 ?        00:00:00 postgres: stats collector process
   postgres    64     1  0 16:07 ?        00:00:00 postgres: bgworker: logical 
   root       103     0  0 16:44 ?        00:00:00 /bin/sh -i
   root       104   103  0 16:44 ?        00:00:00 ps -ef

   # df
   Filesystem               1K-blocks    Used Available Use% Mounted on
   /dev/sdb1                  5242880 1700328   3377016  34% /
   tmpfs                        65536       0     65536   0% /dev
   tmpfs                       865052       0    865052   0% /sys/fs/cgroup
   /dev/sdb1                  5242880 1700328   3377016  34% /etc/hosts
   shm                          65536       8     65528   1% /dev/shm
   /dev/lxdVG/custom_myData   1041644   34368   1007276   4% /var/lib/postgres/data
   udev                        852148       0    852148   0% /dev/tty
   tmpfs                       865052       0    865052   0% /proc/acpi
   tmpfs                       865052       0    865052   0% /proc/scsi
   tmpfs                       865052       0    865052   0% /sys/firmware
   ^D

   # listing namespaces associated with a pid.
   root@ins2# lsns -o UID,NS,TYPE,PID,PPID,NPROCS,COMMAND -p 5590
       UID         NS TYPE     PID  PPID NPROCS COMMAND
   1000000 4026532240 user    5438 20517     28 /usr/bin/docker-proxy -proto tcp
             -host-ip 0.0.0.0 -host-port 5432 -container-ip 172.17.0.2 -container-port 5432
   1000000 4026532309 cgroup  5438 20517     27 /usr/bin/docker-proxy -proto tcp
             -host-ip 0.0.0.0 -host-port 5432 -container-ip 172.17.0.2 -container-port 5432
   1000999 4026532321 mnt     5466  5444      7 postgres
   1000999 4026532322 uts     5466  5444      7 postgres
   1000999 4026532323 ipc     5466  5444      7 postgres
   1000999 4026532324 pid     5466  5444      7 postgres
   1000999 4026532326 net     5466  5444      7 postgres


Note that lsns COMMAND and PID output is just the lowest PID in the namespace and doesn't represent
where the namespace started.

:index:`Snap namespaces`
~~~~~~~~~~~~~~~~~~~~~~~~

The lxd application is running in it's own mount namespace within snap.

.. code-block:: console

   # list mount namespaces
   # Note, command/pid is just the lowest pid in a shared namespace.
   root@ins2# lsns -t mnt
           NS TYPE NPROCS   PID USER            COMMAND
   4026531840 mnt     151     1 root            /sbin/init
   4026531861 mnt       1    13 root            kdevtmpfs
   4026532203 mnt       1   406 root            /lib/systemd/systemd-udevd
   4026532204 mnt       1   634 systemd-network /lib/systemd/systemd-networkd
   4026532205 mnt       1  5093 systemd-resolve /lib/systemd/systemd-resolved
   4026532209 mnt       5 15756 root            /bin/sh /snap/lxd/8011/commands/daemon.start
   4026532210 mnt       1   859 _chrony         /usr/sbin/chronyd
   4026532211 mnt       1 13644 lxd             dnsmasq --strict-order --bind-interfaces ..
   4026532241 mnt      18  5438 1000000         /usr/bin/docker-proxy -proto tcp ...
   4026532308 mnt       1 17080 1000000         /lib/systemd/systemd-udevd
   4026532310 mnt       1 17285 1000100         /lib/systemd/systemd-networkd
   4026532311 mnt       1 17299 1000101         /lib/systemd/systemd-resolved
   4026532321 mnt       7  5466 1000999         postgres

The namespace used by the LXD snap is 4026532209.  We can view all 5 of the processes in that
namespace with some flags on ps.

.. code-block:: console

   # showing mntns associated with a process.
   root@ins2# ps -eo pid,ppid,mntns,pgrp,args --sort +mntns,+pgrp |grep 4026532209
   15756     1 4026532209 15756 /bin/sh /snap/lxd/8011/commands/daemon.start
   15908     1 4026532209 15756 lxcfs /var/snap/lxd/common/var/lib/lxcfs -p ...
   15921 15756 4026532209 15756 lxd --logfile /var/snap/lxd/common/lxd/logs/lxd.log
   16374     1 4026532209 16373 dnsmasq --strict-order --bind-interfaces ... 
   16954     1 4026532209 16954 [lxc monitor] /var/snap/lxd/common/lxd/containers dkr002

The snap container uses the squashfs snap-core image as it's rootfs.  This corresponds to
/snap/core/4917 outside of the mount namespace and the hostfs is relocated to
/var/lib/snap/hostfs with pivotroot.

.. code-block:: console

   # Manually entering the snap mountns
   root@ins2# nsenter -a -t 15756

   root@ins2# df
   Filesystem               1K-blocks    Used Available Use% Mounted on
   /dev/sda1                  9983232 1920444   8046404  20% /var/lib/snapd/hostfs
   tmpfs                       173012     936    172076   1% /var/lib/snapd/hostfs/run
   tmpfs                         5120       0      5120   0% /var/lib/snapd/hostfs/run/lock
   tmpfs                       173008       0    173008   0% /var/lib/snapd/hostfs/run/user/1001
   /dev/loop0                   50560   50560         0 100% /snap/google-cloud-sdk/45
   /dev/loop1                   89088   89088         0 100% /
   /dev/sda15                  106858    3433    103426   4% /var/lib/snapd/hostfs/boot/efi
   /dev/loop2                   55936   55936         0 100% /snap/lxd/8011
   udev                        852148       0    852148   0% /dev
   tmpfs                       865052       0    865052   0% /dev/shm
   tmpfs                       865052       0    865052   0% /sys/fs/cgroup
   none                        865052       0    865052   0% /var/lib
   tmpfs                       865052       8    865044   1% /run
   tmpfs                       865052     120    864932   1% /etc
   tmpfs                          100       0       100   0% /var/snap/lxd/common/lxd/shmounts
   tmpfs                          100       0       100   0% /var/snap/lxd/common/lxd/devlxd
   /dev/sdb1                  5242880 1700376   3376952  34% /var/snap/lxd/common/lxd/storage-pools/default
   /dev/loop3                   89088   89088         0 100% /snap/core/5145
   /dev/loop4                   50816   50816         0 100% /snap/google-cloud-sdk/46
   /dev/lxdVG/custom_myData   1041644   34368   1007276   4% /var/snap/lxd/common/lxd/devices/dkr002/disk.data.data

   root@ins2# grep " / " /proc/mounts
   /dev/loop1 / squashfs ro,nodev,relatime 0 0

:index:`Snap and LVM Thinpools`
-------------------------------

.. todo:: Figure out interaction between lvm_thinpool autoextend and snap mountns.

One of the strange side effects of burying your LVM storage pool behind a mount namespaces is
that monitoring the pool is less straight forward.  LVM events don't seem to propagate through to
the host namespace where dmeventd is running.

I haven't done the work to examine how this this would effect dmeventd and `automatic extension`_
of thin pools, but this detail is essential if you intend to oversubscribe thin pools with the
expectation that automatic extension will kick in.  Failure to extend a full thinpool can result
in corruption.

.. code-block:: console

   root@ins2# lxc storage volume create lvmPool test
   Storage volume test created

   root@ins2# lvs -a
     LV                  VG    Attr       LSize  Pool        Origin Data%  Meta%
     LXDThinPool         lxdVG twi-aotz-- <3.00g                    0.59   0.01
     [LXDThinPool_tdata] lxdVG Twi-ao---- <3.00g
     [LXDThinPool_tmeta] lxdVG ewi-ao----  1.00g
     custom_myData       lxdVG Vwi-aotz--  1.00g LXDThinPool        0.68
     [lvol0_pmspare]     lxdVG ewi-------  1.00g

   root@ins2# vgscan --cache
     Reading volume groups from cache.
     Found volume group "lxdVG" using metadata type lvm2

   root@ins2# lvs -a
     LV                  VG    Attr       LSize  Pool        Origin Data%  Meta%
     LXDThinPool         lxdVG twi-aotz-- <3.00g                    0.59   0.01
     [LXDThinPool_tdata] lxdVG Twi-ao---- <3.00g
     [LXDThinPool_tmeta] lxdVG ewi-ao----  1.00g
     custom_myData       lxdVG Vwi-aotz--  1.00g LXDThinPool        0.68
     custom_test         lxdVG Vwi-a-tz-- 10.00g LXDThinPool        0.11
     [lvol0_pmspare]     lxdVG ewi-------  1.00g


Miscelaneous Tips
-----------------

:index:`Cloud-init in LXD Guests`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When working with cloud-init, the key config->user.user-data one large string that contains a
second yaml document written to the cloud-init seed files via template in the lxd image. The
centos images don't have cloud config installed currently, but it's relatively easy to create an
image with templates based on the ubuntu image templates.

.. code-block:: console

   root@ins2# lxc config template list dkr002
   +------------------------+
   |        FILENAME        |
   +------------------------+
   | cloud-init-meta.tpl    |
   +------------------------+
   | cloud-init-network.tpl |
   +------------------------+
   | cloud-init-user.tpl    |
   +------------------------+
   | cloud-init-vendor.tpl  |
   +------------------------+
   | hostname.tpl           |
   +------------------------+
   root@ins2# lxc config template show dkr002 cloud-init-user.tpl
   {{ config_get("user.user-data", properties.default) }}
   root@ins2#

The embedded yaml does present a challenge for linting as it's seen as a string and not tested.
The `yaml2json.py` utility can help with this issue.  Yaml2json.py makes it easy to extract the
user-data embedded yaml document for linting, and you can pass it back through yaml2json.py to
validate nesting and structure as well.

.. code-block:: console

   # stream the string value of the key at obj->config->user.user-data
   shell# ./yaml2json.py config user.user-data 

   # Convert that extracted yaml string to json.
   # if this fails, it's malformed yaml.
   shell# ./yaml2json.py config user.user-data | ./yaml2json -

   # You can lint the embedded yaml to find the problem like so.
   shell# ./yaml2json.py config user.user-data > cinit.yml
   shell# yamllint cinit.yml

I also recommend working from a file, and pushing your edits by passing the file to stdin.  By
default *lxc profile edit name* opens the profile in an editor for direct editing, but if you have
an error in the embedded yaml string quoting, it will fix it for you by converting it to a quoted
and escaped string.  That can be fixed with yaml2json, but it's better to just avoid the direct
edit convenience feature to keep whitespace clean.  

Incidentally, if you notice your profile comes back with a odd doublequoted representation of the
embedded cloud-init yaml, it is probably a trailing whitespace error.


:index:`LXD files of interest`
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Several ephemeral files are generated by LXD. These should not be edited directly, but they can
provide useful insight when troubleshooting and tuning various settings.  Note that LXD is a web
service based management layer on top of the lxc engine so `lxc.conf`_ and the LXC documentation
is a good place to explore when your digging deep.


.. csv-table::

   Description, Path
   per container logs and ephemeral `lxc.conf`_, /var/snap/lxd/common/lxd/logs/{container}/
   ephemeral container apparmor files, /var/snap/lxd/common/lxd/security/apparmor/{container}
   ephemeral container seccomp apparmor files, /var/snap/lxd/common/lxd/security/seccomp/{container}
   SQLite db. LXD settings., /var/snap/lxd/common/lxd/database/local.db
   `instance type definitions`_, /var/snap/lxd/common/lxd/cache/instance_types.yaml
   LXD daemon log file, /var/snap/lxd/common/lxd/logs/lxd.log

Overuse of `cloud-init`_
~~~~~~~~~~~~~~~~~~~~~~~~

Cloud init is really very cool and a step toward an image build technology that is not dependent
on the container technology once `cloud-init`_ is installed in your base image.

My opinion is that it also has a ton of features which are an invitation to use it past it's sweet
spot.

A better approach may be using cloud-init to install ansible, puppet, or chef and use those tools to
do the complex build.  The advantage to something like ansible over cloud-init, is that ansible is
a more capable state machine.  If it fails halfway through, it stops there, and you can
troubleshoot the failed step without repeating all of the steps leading to that failed
step on each troubleshooting iteration.

Using a advanced toolset at the start also gives you more options as you bump into cases
that are not easily addressed by cloud-init toolset. It also builds your team's experience
behind a tool with more use cases beyond container initialization.

That said, between ansible, lxd, and cloud-init, there is pretty good momentum behind yaml defined
automation which can quickly develop as a core skill on a devops team.

Update `containerd`_
--------------------

The latest devUser.yml file `on github`_ has a couple of fixes for updated versions of docker-ce.
Newer version try to use modprobe to load overlay before starting containerd which doesn't work and 
the listen fd:// argument appears to be deprecated in favor of unix:// in dockerd's config.

There are serveral other minor changes as devUser is actively used, but those changes are not being
back ported to the other profiles referenced here. If you run into issues, it's a good idea to check
the lates devUser.yml for a potential fix.

.. _article regarding Docker in LXD: https://stgraber.org/2016/04/13/lxd-2-0-docker-in-lxd-712/
.. _snapcraft: https://docs.snapcraft.io/core/install
.. _LXD 3.3: https://linuxcontainers.org/lxd/news/#lxd-33-release-announcement
.. _Ubuntu Bionic 18.04 LTS: https://wiki.ubuntu.com/BionicBeaver/ReleaseNotes?_ga=2.137095344
   .1263404634.1533563555-1028494520.1527093469
.. _Docker Community Edition: https://store.docker.com/editions/community/docker-ce-server-ubuntu
.. _Docker CE install repository: https://docs.docker.com/install/linux/docker-ce/ubuntu/#install-
   using-the-repository
.. _LXD Storage Pool: https://github.com/lxc/lxd/blob/master/doc/storage.md#lvm
.. _cloud-init: https://cloudinit.readthedocs.io/en/latest/
.. _as of LXD 3.0: https://linuxcontainers.org/lxd/news/#availability-as-a-snap-package-from-
   upstream
.. _LVMThin provisioning: http://man7.org/linux/man-pages/man7/lvmthin.7.html
.. _snap application container: https://docs.snapcraft.io/snaps/
.. _LXC Profile: https://github.com/lxc/lxd/blob/master/doc/profiles.md
.. _support snap packages: https://docs.snapcraft.io/core/install
.. _d_type support: https://linuxer.pro/2017/03/what-is-d_type-and-why-docker-overlayfs-need-it/
.. _Overlay2: https://docs.docker.com/storage/storagedriver/overlayfs-driver/
.. _overlay: https://docs.docker.com/storage/storagedriver/overlayfs-driver/
.. _btrfs storage pool: https://github.com/lxc/lxd/blob/master/doc/storage.md#btrfs
.. _btrfs storage driver: https://docs.docker.com/storage/storagedriver/select-storage-driver/
.. _LXD proxy devices: https://github.com/lxc/lxd/blob/master/doc/containers.md#type-proxy
.. _lxc.conf: https://linuxcontainers.org/lxc/manpages//man5/lxc.container.conf.5.html
.. _automatic extension: http://man7.org/linux/man-pages/man7/lvmthin.7.html#Thin_Topics
.. _instance type definitions: https://github.com/lxc/lxd/blob/master/doc/containers.md#instance-types
.. _on github: https://github.com/devendor/turtles.git
.. _on Devendor Tech: https://devendortech.com/articles/Docker_in_LXD_Guest.html
.. _on Medium: https://medium.com/devendor-tech/turtles-2ccf91c86853
.. _containerd: https://blog.docker.com/2017/08/what-is-containerd-runtime/
