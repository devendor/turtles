Userns LXD, nested Docker, and accellerated GPU graphics
========================================================

LXD profile with nested docker and accelerated GPU support for JetBrains toolbox.

`Prettier`_, `github`_, `medium`_.

Why?
----

There are certainly more use cases for this type of container, but in my case, I'm using it to contain development environments without losing the advantages of direct access to runtime system from advanced tools like `pycharm`_ or `Idea`_.

There are certainly other approaches to the issue of getting an advanced IDE in the same process space as your running app including remote debugging and various IDEs that have moved toward a client server models or brower model instead of a direct GUI application. I find the latter to be a great idea, but I don't like to waste time figuring out new IDEs with usually more limited language support and very different UI designs.

For my money, jetbrains gives me a consistent layout and functionality accross all of the languages I currently program in with deep support in each language.  The trade off is often remote debugging or contaminating your workstation with development jobs that come and go.

This approach eliminates most of the drawbacks and keeps things clean and safe.

Priors
------

I strongly recommend checking out my turtles article for background, as I don't intend to recap nested docker, LXD, and cloud-init here.

See Turtles `on github`_, `on Devendor Tech`_ for prettiest formatting, and `on medium`_ for a walkthrough of nested container support for LXD.

My Environment
--------------

The following details of my workstation environment effect the lxd profile I use for turning up a new development environment.

* Local UID/GID: 1000
* local user: rferguson
* Ubuntu 18.04
* Nvidia GPU
* Jetbrains toolbox installed to ~/.local on host.

How To
------

Starting where `Turtles`_ left off.

#. Get and edit the new devUser.yml profile.

   .. code-block:: console

      rferguson@myhost$ git clone https://github.com/devendor/turtles.git

#. Edit the profile to suit your environment as noted in TODO tags.

   .. code-block:: console

      rferguson@myhost$ vim turtles/devUser.yml


#. Create a lxd profile and import devUser.yml to it.

   .. code-block:: console

      rferguson@myhost$ lxc profile create devUser
      rferguson@myhost$ lxc profile edit devUser <devUser.yml


#. Launch a new dev machine.

   .. code-block:: console

      rferguson@myhost$ lxc launch b dev1 -p devUser -p default
      rferguson@myhost$ lxc exec dev1 -- tail -f /var/log/cloud-init-output.log

#. Map a project dir if desired.

   .. code-block:: console

      rferguson@myhost$ lxc config device add dev1 myproject \
         disk source=/home/rferguson/code path=/home/me/code

#. Launch pycharm.

   .. code-block:: console

      rferguson@myhost$ lxc exec dev1 -- runuser me -c "pycharm ~/code" &

Final thoughts
--------------

You wil have to do some initial setup unless you also map your IDE setting directory, but it can be nice to use
one of the settings sync options of this particular ide and keep per instance settings separated and use the
various settings sync options to syncronize or archive IDE settings on a per-project basis.

Mapping user rferguson to user me has pragmatic value since I can now image the entire dev environment and give
it to the new guy or push it somewhere else and run it under a different local host user. Me@dev1 is also a shorter
PS1 for cleaner looking docs.

There is a lot that isn't covered here.  The docker nesting are already in `turtles`_ and there is some good
information on the details of GPU features of LXD containers from existing sources.

Happy coding!

devUser.yml Profile
-------------------

.. note:: Checkout `devUser.yml`_ on github as this is unmaintained.

.. code-block:: yaml

   name: devUser
   description: LXD profile with nested docker and accelerated GPU support for JetBrains toolbox.
   config:
     environment.LANG: en_US.UTF-8
     environment.LANGUAGE: en_US:en
     environment.DISPLAY: :0.0
     environment.XAUTHORITY: /home/me/.Xauthority
     nvidia.runtime: "true"  # TODO only if you have an nvidia GPU.
     raw.idmap: |  # TODO Set your UID/GID
       both 1000 1000
     linux.kernel_modules: ip_tables,btrfs
     security.nesting: "true"
     security.privileged: "false"
     user.user-data: |-
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
         - usermod -aG docker me
         - systemctl start docker
         - docker image pull hello-world
         - docker run --rm hello-world
         - apt-get install -y
           x11-apps
           mesa-utils
           alsa-utils
           libxtst6
           libgtk-3-common
           libswt-gtk-3-java
           libnvidia-gl-390  # TODO validate appropriate gl library for your env.
         - "export DISPLAY=:0.0 XAUTHORITY=/home/me/.Xauthority"
         - nvidia-smi
         - runuser me -c "glxinfo -B"
         - runuser me -c "glxgears -info" &
         - sleep 12
         - killall glxgears
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
               "storage-driver": "btrfs"
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
         - path: /bin/pycharm
           permissions: '0755'
           owner: root:root  # TODO Check your install path.
           content: "\
             #!/bin/bash\n\
             exec $( ls -1c ~/.local/share/JetBrains/Toolbox/apps/\
             PyCharm-P/ch-0/*/bin/pycharm.sh | head -1) $@\n"
       users:
         - name: me
           groups:
             - adm
           lock_passwd: true
           shell: /bin/bash
           uid: 1000  # TODO Swap to your numeric UID/GID
           gid: 1000
           ssh-authorized-keys:  # TODO Add your own keys
             - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDPS4YhPW5BkRbYkazwX7s0bFcFefVv30\
               l5qXA0oxWKxM3vlN8eAinmU8ejZ7PgdpzLLnhgm3Kt8HrLYdWzYjoRCeF9Fp+fMcU8KL7I\
               s4KOrCSPKodHOIlV3AtqmNtb9zTwiwCHqPkY9JeaWfiXe2c675jOA5ZkMsaHuaEjbqCYgd\
               I6boQJI7S/haPFzWDr/rbkijjw87t9nh3NP1Oy11QDqavqzjURyika1eBsHKAheBHkVUgt\
               oUu43rMsGLjL/gyD5XNJntdSuENYWH rferguson@booger"
             - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC8hW43gyNrayfJwjxZ80HKWboRvpDRnS\
               LhEKGwDfBqfx5aaF67mmIhOE+fsUTed1Odoqo5iprQYEWoTSA6C2RX9G9BBoUVCiA7DMIf\
               dBTfJ5G3mO1I8ZZazttQ2qp5/e9z4mpYzL410YZyZ6XrgWoazQpDGdb2pkSmADo8jc/rED\
               yM+ZWRBNDOS4gxUPk5oy8HbpZmK380JYvvGNSZCj4QSe5IZa/bQx6NL88mEF/+BHEW6JFw\
               +Awv7c1+GHDL5iYQnTAY+XG1BQdDwuziRFm8eWPYamgUd+4JKptcf1gW6W1EnIQ2i4OR2L\
               R1/BIXwG0FMfs3gJlM1Wbh/giYSt8p rferguson@mendota"
             - "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCg51sNuYolkEw52oIKw3OKzlso2UyS0h\
               0+R9t5wQYGMk6SfS0PHFd6epwWP1aHnJJnyLIZGPB/qaiWz4dTJEhl5eRaBO0ca6/SbMCu\
               wjCCE/6IMPphj79v14hXfOG42dF/wZN3AF2VJwI3xVcxAyEkEIgAb79X4wUO2nN6xli5ET\
               Q+YxPVfxD8+A0B1p25Ef1NdnUdGHOBCkpV4rgcO2fLQHIspMlL/JDJ9CUyCvy5XM7elN37\
               iOdEUysGCavTcA0MeUxjkFdyzJt+MNVve4t+hOF6p/HnIvhcGxME6CQRyX3rM5bPbWy1ER\
               e7BXJmg4SZmG5QccaTzqcCBJyFTJDX rferguson@c302ca"
           sudo:
             - ALL=(ALL) NOPASSWD:ALL
   devices:  # TODO Swap in your home dir path.
     Xauthority:
       path: /home/me/.Xauthority
       source: /home/rferguson/.Xauthority
       type: disk
     nvgpu:
       type: gpu
       uid: "0"
       gid: "0"
     x11:
       path: /tmp/.X11-unix/X0
       source: /tmp/.X11-unix/X0
       type: disk
     melocal:
       source: /home/rferguson/.local
       path: /home/me/.local
       type: disk


.. _on github: https://github.com/devendor/turtles.git
.. _on Devendor Tech: https://devendortech.com/articles/Docker_in_LXD_Guest.html
.. _on Medium: https://medium.com/devendor-tech/turtles-2ccf91c86853
.. _pycharm: https://www.jetbrains.com/pycharm/
.. _idea: https://www.jetbrains.com/idea/ 
.. _toobox: https://www.jetbrains.com/toolbox/app/?fromMenu
.. _turtles: https://www.devendortech.com/articles/Docker_in_LXD_Guest.html
.. _prettier: https://www.devendortech.com/articles/devuser_lxd.html
.. _github: https://github.com/devendor/turtles.git
.. _medium: https://medium.com/devendor-tech/devuserlxd-1193be4897b0
.. _devUser.yml: https://raw.githubusercontent.com/devendor/turtles/master/devUser.yml

