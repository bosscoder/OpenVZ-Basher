#!/bin/bash
# A simple script that will install OpenVZ on your server.
# Tested on CentOS 6 64bit, YUM requires minimum of 512MB RAM to work.

# Check for root account
if [[ "$EUID" -ne 0 ]]; then
    echo "Sorry, you must to run this script as root!"
    exit 1
fi

# Make sure server running is full virtualized (aka not a container)
if [[ -f /proc/user_beancounters ]] && [[ $(cat /proc/1/status | grep envID | cut -f 2) != 0 ]]; then
    echo "You need a dedicated server or KVM/XEN/VMware to use this script!"
    exit 1
fi

doinstall () {
    # If ram is less than ~500MB, quit with error 1
    tram=$(($(free -m | awk '/^Mem:/{print $2}')+$(free -m | awk '/^Swap:/{print $2}')))
    if [[ "$tram" -lt "480" ]]; then
        echo "You probably shouldn't be installing OpenVZ on such little ram system."
        exit 1
    fi

    # Updating system first
    yum update -y

    # Installing wget
    yum install -y wget

    # Adding OpenVZ Repo
    wget -P /etc/yum.repos.d/ https://download.openvz.org/openvz.repo
    rpm --import http://download.openvz.org/RPM-GPG-Key-OpenVZ

    # Installing OpenVZ Kernel
    yum install -y vzkernel

    # Installing OpenVZ tools
    yum install -y vzctl vzquota ploop

    # Setting kernel parameters
    sed -i 's/kernel.sysrq = 0/kernel.sysrq = 1/g' /etc/sysctl.conf
    sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf
    echo 'net.ipv4.conf.default.proxy_arp = 0' >> /etc/sysctl.conf
    echo 'net.ipv4.conf.all.rp_filter = 1' >> /etc/sysctl.conf
    echo 'net.ipv4.conf.default.send_redirects = 1' >> /etc/sysctl.conf
    echo 'net.ipv4.conf.all.send_redirects = 0' >> /etc/sysctl.conf
    echo 'net.ipv4.icmp_echo_ignore_broadcasts=1' >> /etc/sysctl.conf
    echo 'net.ipv4.conf.default.forwarding=1' >> /etc/sysctl.conf

    # Apply the changes
    sysctl -p

    # Making sure the templates directory exists
    if ! [[ -e /vz/template/cache ]]; then
        mkdir /vz/template/cache
    fi

    # Download sample VZ config
    wget -P /etc/vz/conf/ https://raw.githubusercontent.com/bosscoder/OpenVZ-Basher/master/ve-vswap-ovzbasher.conf-sample

    # Changing default VZ settings:
    sed -r -i 's/^#*\s*NEIGHBOUR_DEVS\s*=.*/NEIGHBOUR_DEVS=all/g' /etc/vz/vz.conf
    sed -r -i 's/^#*\s*VE_LAYOUT\s*=.*/VE_LAYOUT=simfs/g' /etc/vz/vz.conf
    sed -i 's/centos-6-x86/debian-7.0-x86_64/g' /etc/vz/vz.conf
    sed -i 's/vswap-256m/vswap-ovzbasher/g' /etc/vz/vz.conf
    sed -i "s/IPV6=\"yes\"/IPV6=\"no\"/" /etc/vz/vz.conf
    sed -r -i 's/^SELINUX=.*\s*/SELINUX=disabled/g' /etc/sysconfig/selinux

    # Load tun modules on system boot
    echo "modprobe tun" >> /etc/rc.modules 
    chmod +x /etc/rc.modules

    # Allowing everything through iptables
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -t nat -F
    iptables -t mangle -F
    iptables -F
    iptables -X
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    IPoct=11
    while [[ $IPoct -lt 255 ]]; do
        intIP=192.168.1."$IPoct"
        iptables -t nat -A PREROUTING -i eth0 -p tcp --dport "$IPoct"22 -j DNAT --to $intIP:22
        iptables -t nat -A PREROUTING -i eth0 -p tcp --dport "$IPoct"01:"$IPoct"20 -j DNAT --to $intIP
        ((IPoct++))
    done
    iptables-save > /etc/sysconfig/iptables

    # Download and install OpenVZ Bash Manager
    wget -O /usr/bin/ovzmanager https://git.io/ovzmanager --no-check-certificate && chmod +x /usr/bin/ovzmanager
}

dotempdl () {
    while true; do
        # START - Defining color codes
        ccn=$'\e[0m'
        if [[ -f /vz/template/cache/centos-6-x86-minimal.tar.gz ]]; then
            cca=$'\e[1;32m'
        else
            cca=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/centos-6-x86_64-minimal.tar.gz ]]; then
            ccb=$'\e[1;32m'
        else
            ccb=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/centos-7-x86_64-minimal.tar.gz ]]; then
            ccc=$'\e[1;32m'
        else
            ccc=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/centos-7-x86_64.tar.gz ]]; then
            ccd=$'\e[1;32m'
        else
            ccd=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/debian-7.0-x86-minimal.tar.gz ]]; then
            cce=$'\e[1;32m'
        else
            cce=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/debian-7.0-x86_64-minimal.tar.gz ]]; then
            ccf=$'\e[1;32m'
        else
            ccf=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/debian-8.0-x86_64-minimal.tar.gz ]]; then
            ccg=$'\e[1;32m'
        else
            ccg=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/debian-8.0-x86_64.tar.gz ]]; then
            cch=$'\e[1;32m'
        else
            cch=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/ubuntu-14.04-x86-minimal.tar.gz ]]; then
            cci=$'\e[1;32m'
        else
            cci=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/ubuntu-14.04-x86_64-minimal.tar.gz ]]; then
            ccj=$'\e[1;32m'
        else
            ccj=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/ubuntu-15.10-x86_64-minimal.tar.gz ]]; then
            cck=$'\e[1;32m'
        else
            cck=$'\e[1;31m'
        fi
        if [[ -f /vz/template/cache/ubuntu-16.04-x86_64.tar.gz ]]; then
            ccl=$'\e[1;32m'
        else
            ccl=$'\e[1;31m'
        fi
        # END - Defining color codes

        # Template download selector
        clear
        printf "Template names in \e[1;32mgreen\e[0m = exist on server.\n"
        printf "%s\n" "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        printf "%s\n" "|      ${cca}(a) CentOS 6 32bit Minimal${ccn}      ||      ${ccb}(b) CentOS 6 64bit Minimal${ccn}      |"
        printf "%s\n" "|      ${ccd}(c) CentOS 7 64bit Standard${ccn}     ||      ${ccc}(d) CentOS 7 64bit Minimal${ccn}      |"
        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "%s\n" "|      ${cce}(e) Debian 7 32bit Minimal${ccn}      ||      ${ccf}(f) Debian 7 64bit Minimal${ccn}      |"
        printf "%s\n" "|      ${cch}(g) Debian 8 64bit Standard${ccn}     ||      ${ccg}(h) Debian 8 64bit Minimal${ccn}      |"
        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "%s\n" "|    ${cci}(i) Ubuntu 14.04 32bit Minimal${ccn}    ||    ${ccj}(j) Ubuntu 14.04 64bit Minimal${ccn}    |"
        printf "%s\n" "|    ${cck}(k) Ubuntu 15.10 64bit Minimal${ccn}    ||    ${ccl}(l) Ubuntu 16.04 64bit Standard${ccn}   |"
        printf "%s\n" "--------------------------------------------------------------------------------"
        printf "%s\n" "|       (z) ALL Common Templates       ||        (q) Quit & Continue...        |"
        printf "%s\n" "++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        if ! [[ -z $dstatus ]]; then printf "\e[1;33m%s${ccn}\n" "$dstatus"; fi
        read -p "Please choose a template to download: " tpdlo

        case $tpdlo in
            a)
                if [[ -f /vz/template/cache/centos-6-x86-minimal.tar.gz ]]; then
                    dstatus="EXISTS: CentOS 6 32bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/centos-6-x86-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: CentOS 6 32bit minimal template."
                fi
            ;;

            b)
                if [[ -f /vz/template/cache/centos-6-x86_64-minimal.tar.gz ]]; then
                    dstatus="EXISTS: CentOS 6 64bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/centos-6-x86_64-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: CentOS 6 64bit minimal template."
                fi
            ;;

            c)
                if [[ -f /vz/template/cache/centos-7-x86_64.tar.gz ]]; then
                    dstatus="EXISTS: CentOS 7 64bit standard template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/centos-7-x86_64.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: CentOS 7 64bit standard template."
                fi
            ;;

            d)
                if [[ -f /vz/template/cache/centos-7-x86_64-minimal.tar.gz ]]; then
                    dstatus="EXISTS: CentOS 7 64bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/centos-7-x86_64-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: CentOS 7 64bit minimal template."
                fi
            ;;

            e)
                if [[ -f /vz/template/cache/debian-7.0-x86-minimal.tar.gz ]]; then
                    dstatus="EXISTS: Debian 7 32bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/debian-7.0-x86-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: Debian 7 32bit minimal template."
                fi
            ;;

            f)
                if [[ -f /vz/template/cache/debian-7.0-x86_64-minimal.tar.gz ]]; then
                    dstatus="EXISTS: Debian 7 64bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/debian-7.0-x86_64-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: Debian 7 64bit minimal template."
                fi
            ;;

            g)
                if [[ -f /vz/template/cache/debian-8.0-x86_64.tar.gz ]]; then
                    dstatus="EXISTS: Debian 8 64bit standard template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/debian-8.0-x86_64.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: Debian 8 64bit standard template."
                fi
            ;;

            h)
                if [[ -f /vz/template/cache/debian-8.0-x86_64-minimal.tar.gz ]]; then
                    dstatus="EXISTS: Debian 8 64bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/debian-8.0-x86_64-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: Debian 8 64bit minimal template."
                fi
            ;;

            i)
                if [[ -f /vz/template/cache/ubuntu-14.04-x86-minimal.tar.gz ]]; then
                    dstatus="EXISTS: Ubuntu 14.04 32bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/ubuntu-14.04-x86-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: Ubuntu 14.04 32bit minimal template."
                fi
            ;;

            j)
                if [[ -f /vz/template/cache/ubuntu-14.04-x86_64-minimal.tar.gz ]]; then
                    dstatus="EXISTS: Ubuntu 14.04 64bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/ubuntu-14.04-x86_64-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: Ubuntu 14.04 64bit minimal template."
                fi
            ;;

            k)
                if [[ -f /vz/template/cache/ubuntu-15.10-x86_64-minimal.tar.gz ]]; then
                    dstatus="EXISTS: Ubuntu 15.10 64bit minimal template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/ubuntu-15.10-x86_64-minimal.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: Ubuntu 15.10 64bit minimal template."
                fi
            ;;

            l)
                if [[ -f /vz/template/cache/ubuntu-16.04-x86_64.tar.gz ]]; then
                    dstatus="EXISTS: Ubuntu 16.04 64bit standard template."
                else
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/ubuntu-16.04-x86_64.tar.gz --no-check-certificate
                    dstatus="DOWNLOADED: Ubuntu 16.04 64bit standard template."
                fi
            ;;

            z)
                if ! [[ -f /vz/template/cache/centos-6-x86-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/centos-6-x86-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/centos-6-x86_64-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/centos-6-x86_64-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/centos-7-x86_64.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/centos-7-x86_64.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/centos-7-x86_64-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/centos-7-x86_64-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/debian-7.0-x86-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/debian-7.0-x86-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/debian-7.0-x86_64-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/debian-7.0-x86_64-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/debian-8.0-x86_64.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/debian-8.0-x86_64.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/debian-8.0-x86_64-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/debian-8.0-x86_64-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/ubuntu-14.04-x86-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/ubuntu-14.04-x86-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/ubuntu-14.04-x86_64-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/ubuntu-14.04-x86_64-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/ubuntu-15.10-x86_64-minimal.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/ubuntu-15.10-x86_64-minimal.tar.gz --no-check-certificate
                fi

                if ! [[ -f /vz/template/cache/ubuntu-16.04-x86_64.tar.gz ]]; then
                    wget -P /vz/template/cache/ https://download.openvz.org/template/precreated/ubuntu-16.04-x86_64.tar.gz --no-check-certificate
                fi
                clear
                printf "\e[1;33mDOWNLOADED: All Templates.${ccn}\n\n"
                echo "-------------------------------------------------------"
                echo "You can find more official OpenVZ templates at"
                echo "http://download.openvz.org/template/precreated/"
                echo "The templates must be stored in /vz/template/cache"
                echo "-------------------------------------------------------"
                break
            ;;

            q)
                clear
                echo "-------------------------------------------------------"
                echo "You can find more official OpenVZ templates at"
                echo "http://download.openvz.org/template/precreated/"
                echo "The templates must be stored in /vz/template/cache"
                echo "-------------------------------------------------------"
                break
            ;;

            *)
                dstatus="Invalid entry, please try again..."
            ;;
        esac
    done
}

if [[ $(uname -r) == *"stab"* ]]; then
    echo "OpenVZ Kernel detected on this server!"
    read -p "Would you like to download some OpenVZ templates instead? [y/N] " ovztpo
    case $ovztpo in
        y | yes | Y | YES)
            dotempdl
            ;;
        *)
            echo "-------------------------------------------------------"
            echo "You can find the official OpenVZ templates at"
            echo "http://download.openvz.org/template/precreated/"
            echo "The templates must be stored in /vz/template/cache"
            echo "-------------------------------------------------------"
            ;;
    esac
else
    doinstall
    clear
    echo "Congratulations! OpenVZ Basher is now installed on your server!"
    read -p "Would you like to download some OpenVZ templates now? [y/N] " ovztpo
    case $ovztpo in
        y | yes | Y | YES)
            dotempdl
            ;;
        *)
            echo "-------------------------------------------------------"
            echo "You can find the official OpenVZ templates at"
            echo "http://download.openvz.org/template/precreated/"
            echo "The templates must be stored in /vz/template/cache"
            echo "-------------------------------------------------------"
            ;;
    esac

    echo "A private NAT IP network has been created for you!"
    echo "Available IPs: 192.168.1.11 - 192.168.1.254"
    echo "-------------------------------------------------------"
    echo "A reboot is required to use the OpenVZ kernel."
    read -p "Would you like to reboot now? [y/N] " rbto
    if [[ $rbto == "y" ]] || [[ $rbto == "yes" ]] || [[ $rbto == "Y" ]] || [[ $rbto == "YES" ]]; then
        clear
        echo "Thanks for using the OpenVZ Bash Installer script!"
        echo "Rebooting system now!"
        reboot
    else
        clear
        echo "Thanks for using the OpenVZ Bash Installer script!"
        echo "Please manually reboot the server in order to use the OpenVZ kernel."
    fi
fi
