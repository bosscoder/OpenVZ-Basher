## OpenVZ Basher
A set of simple bash scripts to install and manage OpenVZ containers.

### What's the need for this?
If you aren't sharing your awesome server with others, then there's no need to waste ram on those bloated OpenVZ control panels with GUIs! Do everything in bash command line, easy and fast.

### Requirements:
* A **fresh install** of CentOS 6 64 bit
* IPv4 Internet access
* Root access to the server
* Oodles of CPU and RAM (duh..)
* Oodles of disk space for CTs and templates

### Private IP network (NAT)
A private NAT IP network (192.168.1.0/24) will be created for your convenience, each internal IP is assigned a range of 20 public ports plus 1 dedicated port for SSH.<br>
To access these ports, simply use public_ip:assigned_port.<br>
Example: If the IP is 192.168.1.1, then the assigned SSH port will be 122, and available NAT ports are 101-120.<br>
Example: If the IP is 192.168.1.13, then the assigned SSH port will be 1322, and available NAT ports are 1301-1320.<br>
Example: If the IP is 192.168.1.100, then the assigned SSH port will be 10022, and available NAT ports are 10001-10020.

### How do I use these scripts?
*Run ALL commands with root user*

#### To install OpenVZ Bash Manager
*This will install OpenVZ Bash Manager with all dependencies, only run this on a clean CentOS 6 server!*
*A reboot is required after installation to use OpenVZ Bash Manager.*

``# wget -O /tmp/ovzinstaller.sh https://git.io/ovzinstaller --no-check-certificate && bash /tmp/ovzinstaller.sh``

or

``# curl -kLo /tmp/ovzinstaller.sh https://git.io/ovzinstaller && bash /tmp/ovzinstaller.sh``

#### To run OpenVZ Bash Manager
``# ovzmanager``

#### To update OpenVZ Bash Manager
``# ovzmanager update``