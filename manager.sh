#!/bin/bash
# A simple script to create, destroy, rebuild OpenVZ containers.
# Tested on CentOS 6 64bit, requires OpenVZ Kernel and tools.

# Define the default settings for the script
getdefaultvar () {
    container_hostname="localhost.localdomain"
    container_template="debian-7.0-x86_64-minimal"
    container_nameserver1="8.8.8.8"
    container_nameserver2="8.8.4.4"
    container_tunstatus="ON"
    container_cpucore="1"
    container_ramsize="256M"
    container_swapsize="256M"
    container_diskquota="10G"
}

#======================================================================
# Do not edit anything past this section.
#======================================================================

# Get a random password
getrandpass () {
    container_rootpass=$(cat /dev/urandom | tr -dc _A-Z-a-z-0-9 | head -c${1:-10})
}

# Get next available container ID
getctid () {
    ctid=1
    while true; do
        checkctid=$(vzlist -a -o ctid | grep -w $ctid)
        if [[ -z $checkctid ]]; then
            break
        fi
        ((ctid++))
    done
}

# If more than 1 CPU vCores, use plural form
getcpucoreunit () {
    if [[ $container_cpucore == "1" ]]; then
        cpucoreunit="vCore"
    else
        cpucoreunit="vCores"
    fi
}

# Build container function
buildct () {
    # Calculate total ram
    ramnounit=$( echo $container_ramsize | cut -d 'M' -f 1 )
    swapnounit=$( echo $container_swapsize | cut -d 'M' -f 1 )
    container_totalram=$(expr $ramnounit + $swapnounit)"M"
    # Create a new container with template chosen
    vzctl create "$ctid" --ostemplate "$container_template"
    # Set the container to start on boot
    vzctl set "$ctid" --onboot yes --save
    # Set the IP for container
    vzctl set "$ctid" --ipadd "$container_ipaddr" --save
    # Set the CPU cores for container
    vzctl set "$ctid" --cpus "$container_cpucore" --save
    # Set the nameservers for container
    if [[ -z $container_nameserver2 ]]; then
        vzctl set "$ctid" --nameserver "$container_nameserver1" --save
    else
        vzctl set "$ctid" --nameserver "$container_nameserver1" --nameserver "$container_nameserver2" --save
    fi
    # Set the hostname for container
    vzctl set "$ctid" --hostname "$container_hostname" --save
    # Set disk quota for container, softlimit:hardlimit
    vzctl set "$ctid" --diskspace "$container_diskquota" --save
    # Set ram size for container
    vzctl set "$ctid" --ram "$container_ramsize" --swap "$container_swapsize" --save
    vzctl set "$ctid" --privvmpages "unlimited" --save
    vzctl set "$ctid" --vmguarpages "unlimited" --save
    vzctl set "$ctid" --oomguarpages "unlimited" --save
    vzctl set "$ctid" --kmemsize "$((524288 * $ramnounit))" --save
    vzctl set "$ctid" --lockedpages "$((128 * $ramnounit))" --save
    vzctl set "$ctid" --dcachesize "$((262144 * $ramnounit))" --save
    # Set root user password for container
    vzctl set "$ctid" --userpasswd root:"$container_rootpass" --save
    # Set TUN/TAP/PPP if selected
    if [[ $container_tunstatus == "ON" ]]; then
        if [[ $(vzctl status "$ctid" | grep "running") ]]; then
            vzctl stop "$ctid"
            sleep 3
        fi
        vzctl set "$ctid" --capability net_admin:on --save
        vzctl set "$ctid" --features ppp:on --save
        vzctl start "$ctid"
        sleep 3
        vzctl set "$ctid" --devnodes net/tun:rw --save
        vzctl set "$ctid" --devices c:10:200:rw --save
        vzctl set "$ctid" --devices c:108:0:rw --save
        vzctl exec "$ctid" mkdir -p /dev/net
        vzctl exec "$ctid" chmod 600 /dev/net/tun
        vzctl exec "$ctid" mknod /dev/ppp c 108 0
        vzctl exec "$ctid" chmod 600 /dev/ppp
    else
        # Start the container
        vzctl start "$ctid"
    fi
    # Outputting additional info for modify and rebuild functions
    sed -i "17i#################################################" /etc/vz/conf/$ctid.conf
    sed -i "17i# CONTAINER_ROOT_PASS:$container_rootpass" /etc/vz/conf/$ctid.conf
    sed -i "17i# CONTAINER_TUN_STATUS:$container_tunstatus" /etc/vz/conf/$ctid.conf
    sed -i "17i# CONTAINER_SWAP_SIZE:$container_swapsize" /etc/vz/conf/$ctid.conf
    sed -i "17i# CONTAINER_RAM_SIZE:$container_ramsize" /etc/vz/conf/$ctid.conf
    sed -i "17i# CONTAINER_DISK_QUOTA:$container_diskquota" /etc/vz/conf/$ctid.conf
    sed -i "17i################# DO NOT DELETE #################" /etc/vz/conf/$ctid.conf
    sed -i "17i#############  OpenVZ Bash Manager  #############" /etc/vz/conf/$ctid.conf
    sed -i "17i#################################################" /etc/vz/conf/$ctid.conf
    # Display container info after build
    clear
    if [[ $rebuild ]]; then
        actionword="rebuilt"
    else
        actionword="built"
    fi
    echo "================================================================================"
    echo "Container $ctid has been $actionword successfully!"
    echo "Root Password:           $container_rootpass"
    echo "Hostname:                $container_hostname"
    echo "Template:                $container_template"
    echo "CPU Cores:               $container_cpucore $cpucoreunit"
    echo "Disk Space:              $container_diskquota"
    echo "RAM Size:                $container_ramsize"
    echo "vSWAP Size:              $container_swapsize"
    echo "IP Address:              $container_ipaddr"
    echo "Nameservers:             $container_nameserver"
    echo "TUN/TAP/PPP:             $container_tunstatus"
    echo "================================================================================"
    read -n 1 -s -p "Press any key to continue... "
    successmsg="Container $ctid $actionword!"
    break
}

# New container function
newct () {
    echo "Inspecting system..."
    getctid
    getrandpass
    getdefaultvar
    container_ipaddr="NOT SET"
    ipaddrstatus="INVALID"
    while true; do
        if [[ "$ipaddrstatus" == "VALID" ]]; then
            ccip=$'\e[0m'
        else
            ccip=$'\e[1;31m'
        fi
        container_nameserver="$container_nameserver1$(if [[ $container_nameserver2 ]]; then echo ",$container_nameserver2"; fi)"
        getcpucoreunit
        spacecount=$(expr 23 - ${#container_ramsize})
        clear
        echo "================================================================================"
        echo "                              Create New Container                              "
        echo "================================================================================"
        echo "[1] Container ID:                      $ctid"
        echo "[2] Root Password:                     $container_rootpass"
        echo "[3] Hostname:                          $container_hostname"
        echo "[4] Template:                          $container_template"
        echo ""
        echo "[5] CPU Cores:                         $container_cpucore $cpucoreunit"
        echo "[6] Disk Space:                        $container_diskquota"
        printf "%s%$(echo $spacecount)s%s\n\n" "[7] RAM Size:   $container_ramsize" "" "vSWAP Size:   $container_swapsize"
        printf "%s${ccip}%s\e[0m\n" "[8] " "IP Address:                        $container_ipaddr"
        echo "[9] Nameservers:                       $container_nameserver"
        echo "[0] TUN/TAP/PPP:                       $container_tunstatus"
        if [[ "$ipaddrstatus" == "VALID" ]]; then
            printf "\n\e[1;32m%s\e[0m%15s%s\n\n" "[b] Build Container Now!" "" "[q] Exit to Main Menu"
        else
            printf "\n[q] Exit to Main Menu\n\n"
        fi
        if [[ $errormsg ]]; then
            printf "\e[1;31m%s\e[0m\n\n" "ERROR: $errormsg"
            unset errormsg
        fi
        if [[ $successmsg ]]; then
            printf "\e[1;32m%s\e[0m\n\n" "SUCCESS: $successmsg"
            unset successmsg
        fi
        read -p "Choose an option: " cfgopt
        case $cfgopt in
            1)
            read -p "Enter a new Container ID: " newctid
            checkctid=$(vzlist -a -o ctid | grep -w $newctid)
            if [[ -z $checkctid ]]; then
                ctid=$newctid
                successmsg="Selected container $newctid"
            else
                errormsg="Container ID $newctid is in use!"
            fi
            ;;
            2)
            read -p "Enter a new root user password: " container_rootpass
            successmsg="Root user password set to $container_rootpass"
            ;;
            3)
            read -p "Enter a new hostname: " container_hostname
            successmsg="Container hostname set to $container_hostname"
            ;;
            4)
            printf "\nAvailable templates -->\n"
            alltemp=$(ls -1 /vz/template/cache/ | sed -e 's/\.[^.]*tar.gz//')
            printf "%s\n\n" "$alltemp"
            cd /vz/template/cache/
            echo "Press TAB for autocompletion."
            read -e -p "Enter the full template name to use: " newcttemplate
            cd $currentpwd
            if [[ "$newcttemplate" == *.tar.gz ]]; then
                if ! [[ -f /vz/template/cache/$newcttemplate ]]; then
                    errormsg="The template you entered does not exist."
                else
                    container_template=$(echo $newcttemplate | sed -e 's/\.[^.]*tar.gz//')
                    successmsg="Container Template set to $container_template"
                fi
            else
                if ! [[ -f /vz/template/cache/$newcttemplate.tar.gz ]]; then
                    errormsg="The template you entered does not exist."
                else
                    container_template=$newcttemplate
                    successmsg="Container Template set to $container_template"
                fi
            fi
            ;;
            5)
            maxcpucore=$(grep -c ^processor /proc/cpuinfo)
            read -p "Enter the number of CPU vCores [max: $maxcpucore]: " newvcore
            if [[ $newvcore =~ ^-?[0-9]+$ ]]; then
                if [[ $newvcore -lt 1 ]] || [[ $newvcore -gt $maxcpucore ]]; then
                    errormsg="CPU vCore must be between 1 and $maxcpucore"
                else
                    container_cpucore=$newvcore
                    successmsg="CPU vCore set to $newvcore"
                    modify_cpu=1
                fi
            else
                errormsg="CPU vCore must be between 1 and $maxcpucore"
            fi
            ;;
            6)
            read -p "Enter amount of disk space (in GB): " newdiskquota
            if [[ $newdiskquota =~ ^-?[0-9]+$ ]]; then
                if [[ "$newdiskquota" -lt 1 ]]; then
                    errormsg="Disk quota must be 1G or more."
                else
                    container_diskquota=$newdiskquota"G"
                    successmsg="Disk quota set to $container_diskquota"
                fi
            else
                errormsg="Please enter number only, without any units."
            fi
            ;;
            7)
            read -p "Enter amount of RAM (in MB): " newram
            if [[ $newram =~ ^-?[0-9]+$ ]]; then
                container_ramsize=$newram"M"
            else
                errormsg="Please enter number only, without any units."
            fi
            if [[ -z $errormsg ]]; then
                read -p "Enter amount of vSwap (in MB): " newswap
                if [[ $newswap =~ ^-?[0-9]+$ ]]; then
                    container_swapsize=$newswap"M"
                    successmsg="RAM set to $container_ramsize, vSwap set to $container_swapsize"
                    modify_ram=1
                else
                    errormsg="Please enter number only, without any units."
                fi
            fi
            ;;
            8)
            read -p "Enter the IP address: " newipaddr
            if expr "$newipaddr" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                IFS=.
                set $newipaddr
                for quad in 1 2 3 4; do
                    if eval [ \$$quad -gt 255 ]; then
                        errormsg="$newipaddr is not a valid IP."
                        break
                    fi
                done
                if [[ -z $errormsg ]]; then
                    ipusestatus=$(grep "$newipaddr" /etc/vz/conf/*.conf)
                    if [[ -z $ipusestatus ]]; then
                        container_ipaddr=$newipaddr
                        successmsg="IP set to $newipaddr"
                        ipaddrstatus="VALID"
                    else
                        ipusectid=$(echo $ipusestatus | cut -d "/" -f 5 | cut -d "." -f 1)
                        errormsg="IP $newipaddr is used by container $ipusectid."
                    fi
                fi
            else
                errormsg="$newipaddr is not a valid IP."
            fi
            unset IFS
            ;;
            9)
            read -p "Enter first nameserver IP: " newnsip1
            if [[ -z $newnsip1 ]]; then
                echo "At least one nameserver IP is required."
            else
                if expr "$newnsip1" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                    IFS=.
                    set $newnsip1
                    for quad in 1 2 3 4; do
                        if eval [ \$$quad -gt 255 ]; then
                            errormsg="$newnsip1 is not a valid IP for nameserver 1."
                            break
                        fi
                    done
                    if [[ -z $errormsg ]]; then
                        container_nameserver1=$newnsip1
                        successmsg="Nameserver 1 set to $newnsip1"
                    fi
                else
                    errormsg="$newnsip1 is not a valid IP for nameserver 1."
                fi
            fi
            if [[ -z $errormsg ]]; then
                read -p "Enter second nameserver IP: " newnsip2
                if [[ -z $newnsip2 ]]; then
                    unset container_nameserver2
                else
                    if expr "$newnsip2" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                        IFS=.
                        set $newnsip2
                        for quad in 1 2 3 4; do
                            if eval [ \$$quad -gt 255 ]; then
                                errormsg="$newnsip2 is not a valid IP for nameserver 2."
                                break
                            fi
                        done
                        if [[ -z $errormsg ]]; then
                            container_nameserver2=$newnsip2
                            successmsg="Nameservers set to $newnsip1 and $newnsip2"
                        fi
                    else
                        errormsg="$newnsip2 is not a valid IP for nameserver 2."
                    fi
                fi
            fi
            unset IFS
            ;;
            0)
            if [[ $container_tunstatus == "ON" ]]; then
                container_tunstatus="OFF"
                successmsg="TUN/TAP/PPP set to OFF"
            elif [[ $container_tunstatus == "OFF" ]]; then
                container_tunstatus="ON"
                successmsg="TUN/TAP/PPP set to ON"
            fi
            ;;
            q)
            break
            ;;
            b)
            if [[ "$ipaddrstatus" == "VALID" ]]; then
                buildct
                break
            else
                errormsg="Invalid option entered, please try again..."
            fi
            ;;
            *)
            if [[ "$ipaddrstatus" == "VALID" ]]; then
                read -p "Build Container Now? [Y/n] " buildopt
                case $buildopt in
                    ''|y|yes|Y|YES)
                    buildct
                    break
                    ;;
                esac
            else
                errormsg="Invalid option entered, please try again..."
            fi
            ;;
        esac
    done
}

# Rebuild container function
rebuildct () {
    getctinfo="TRUE"
    ctid="NOT SET"
    ctidstatus="INVALID"
    getrandpass
    getdefaultvar
    while true; do
        if [[ $ctid =~ ^-?[0-9]+$ ]]; then
            chkctid=$(vzlist -a -o ctid | grep -w $ctid)
            if [[ -z $chkctid ]]; then
                errormsg="Container ID entered doesn't exist..."
                ctidstatus="INVALID"
            else
                ctidstatus="VALID"
            fi
        elif [[ $ctid == "NOT SET" ]]; then
            # This line serves no purpose
            ctid="NOT SET"
        else
            errormsg="Invalid Container ID, please try again..."
        fi
        container_nameserver="$container_nameserver1$(if [[ $container_nameserver2 ]]; then echo ",$container_nameserver2"; fi)"
        getcpucoreunit
        spacecount=$(expr 23 - ${#container_ramsize})
        clear
        echo "================================================================================"
        echo "                               Rebuild Container                                "
        echo "================================================================================"
        echo "[c] List all containers                [q] Exit to Main Menu"
        if ! [[ "$ctidstatus" == "VALID" ]]; then
            printf "\n\e[1;31m%s\e[0m\n\n" "Container ID:                          $ctid"
        else
            printf "\n%s\n\n" "[1] Container ID:                      $ctid"
        fi
        if [[ "$ctidstatus" == "VALID" ]]; then
            if [[ $(vzctl status "$ctid" | grep "down") ]]; then
                vzctl start "$ctid"
                sleep 3
            fi
            if [[ $getctinfo == "TRUE" ]]; then
                container_rootpass=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_ROOT_PASS' | cut -d ':' -f 2)
                container_hostname=$(cat /etc/vz/conf/$ctid.conf | grep 'HOSTNAME' | cut -d '"' -f 2)
                container_template=$(cat /etc/vz/conf/$ctid.conf | grep 'OSTEMPLATE' | cut -d '"' -f 2)
                container_cpucore=$(cat /etc/vz/conf/$ctid.conf | grep 'CPUS' | cut -d '"' -f 2)
                container_diskquota=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_DISK_QUOTA' | cut -d ':' -f 2)
                container_ramsize=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_RAM_SIZE' | cut -d ':' -f 2)
                container_swapsize=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_SWAP_SIZE' | cut -d ':' -f 2)
                container_ipaddr=$(cat /etc/vz/conf/$ctid.conf | grep 'IP_ADDRESS' | cut -d '"' -f 2)
                container_nameserver1=$(cat /etc/vz/conf/$ctid.conf | grep 'NAMESERVER' | cut -d '"' -f 2 | cut -d ' ' -f 1)
                container_nameserver2=$(cat /etc/vz/conf/$ctid.conf | grep 'NAMESERVER' | cut -d '"' -f 2 | cut -d ' ' -f 2)
                container_tunstatus=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_TUN_STATUS' | cut -d ':' -f 2)
                getcpucoreunit
                if [[ $container_nameserver1 == $container_nameserver2 ]]; then
                    unset container_nameserver2
                fi
                container_nameserver="$container_nameserver1$(if [[ $container_nameserver2 ]]; then echo ",$container_nameserver2"; fi)"
                spacecount=$(expr 23 - ${#container_ramsize})
                getctinfo="FALSE"
            fi
            echo "[2] Root Password:                     $container_rootpass"
            echo "[3] Hostname:                          $container_hostname"
            echo "[4] Template:                          $container_template"
            echo ""
            echo "[5] CPU Cores:                         $container_cpucore $cpucoreunit"
            echo "[6] Disk Space:                        $container_diskquota"
            printf "%s%$(echo $spacecount)s%s\n" "[7] RAM Size:   $container_ramsize" "" "vSWAP Size:   $container_swapsize"
            echo ""
            echo "[8] IP Address:                        $container_ipaddr"
            echo "[9] Nameservers:                       $container_nameserver"
            echo "[0] TUN/TAP/PPP:                       $container_tunstatus"
            echo "[r] Rebuild Container Now!"
            echo ""
        fi
        if [[ $errormsg ]]; then
            printf "\e[1;31m%s\e[0m\n\n" "ERROR: $errormsg"
            unset errormsg
        fi
        if [[ $successmsg ]]; then
            printf "\e[1;32m%s\e[0m\n\n" "SUCCESS: $successmsg"
            unset successmsg
        fi
        if ! [[ "$ctidstatus" == "VALID" ]]; then
            read -p "Enter Container ID or Choose a Menu Option: " rbldopt
            if [[ $rbldopt =~ ^-?[0-9]+$ ]]; then
                checkctid=$(vzlist -a -o ctid | grep -w $rbldopt)
                if [[ -z $checkctid ]]; then
                    errormsg="Container ID $rbldopt is invalid!"
                else
                    ctid=$rbldopt
                    successmsg="Selected container $rbldopt"
                    getctinfo="TRUE"
                fi
            elif [[ $rbldopt == "c" ]]; then
                getctlist
            elif [[ $rbldopt == "q" ]]; then
                break
            else
                errormsg="Invalid option entered, please try again..."
            fi
        else
            read -p "Choose an option: " rbldopt
            case $rbldopt in
                1)
                read -p "Enter a Container ID: " newctid
                checkctid=$(vzlist -a -o ctid | grep -w $newctid)
                if [[ -z $checkctid ]]; then
                    errormsg="Container ID $newctid is invalid!"
                else
                    ctid=$newctid
                    successmsg="Selected container $newctid"
                    getctinfo="TRUE"
                fi
                ;;
                2)
                read -p "Enter a new root user password: " container_rootpass
                successmsg="Root user password set to $container_rootpass"
                ;;
                3)
                read -p "Enter a new hostname: " container_hostname
                successmsg="Container hostname set to $container_hostname"
                ;;
                4)
                printf "\nAvailable templates -->\n"
                alltemp=$(ls -1 /vz/template/cache/ | sed -e 's/\.[^.]*tar.gz//')
                printf "%s\n\n" "$alltemp"
                cd /vz/template/cache/
                echo "Press TAB for autocompletion."
                read -e -p "Enter the full template name to use: " newcttemplate
                cd $currentpwd
                if [[ "$newcttemplate" == *.tar.gz ]]; then
                    if ! [[ -f /vz/template/cache/$newcttemplate ]]; then
                        errormsg="The template you entered does not exist."
                    else
                        container_template=$(echo $newcttemplate | sed -e 's/\.[^.]*tar.gz//')
                        successmsg="Container Template set to $container_template"
                    fi
                else
                    if ! [[ -f /vz/template/cache/$newcttemplate.tar.gz ]]; then
                        errormsg="The template you entered does not exist."
                    else
                        container_template=$newcttemplate
                        successmsg="Container Template set to $container_template"
                    fi
                fi
                ;;
                5)
                maxcpucore=$(grep -c ^processor /proc/cpuinfo)
                read -p "Enter the number of CPU vCores [max: $maxcpucore]: " newvcore
                if [[ $newvcore =~ ^-?[0-9]+$ ]]; then
                    if [[ $newvcore -lt 1 ]] || [[ $newvcore -gt $maxcpucore ]]; then
                        errormsg="CPU vCore must be between 1 and $maxcpucore"
                    else
                        container_cpucore=$newvcore
                        successmsg="CPU vCore set to $newvcore"
                        modify_cpu=1
                    fi
                else
                    errormsg="CPU vCore must be between 1 and $maxcpucore"
                fi
                ;;
                6)
                read -p "Enter amount of disk space (in GB): " newdiskquota
                if [[ $newdiskquota =~ ^-?[0-9]+$ ]]; then
                    if [[ "$newdiskquota" -lt 1 ]]; then
                        errormsg="Disk quota must be 1G or more."
                    else
                        container_diskquota=$newdiskquota"G"
                        successmsg="Disk quota set to $container_diskquota"
                    fi
                else
                    errormsg="Please enter number only, without any units."
                fi
                ;;
                7)
                read -p "Enter amount of RAM (in MB): " newram
                if [[ $newram =~ ^-?[0-9]+$ ]]; then
                    container_ramsize=$newram"M"
                else
                    errormsg="Please enter number only, without any units."
                fi
                if [[ -z $errormsg ]]; then
                    read -p "Enter amount of vSwap (in MB): " newswap
                    if [[ $newswap =~ ^-?[0-9]+$ ]]; then
                        container_swapsize=$newswap"M"
                        successmsg="RAM set to $container_ramsize, vSwap set to $container_swapsize"
                        modify_ram=1
                    else
                        errormsg="Please enter number only, without any units."
                    fi
                fi
                ;;
                8)
                read -p "Enter the IP address: " newipaddr
                if expr "$newipaddr" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                    IFS=.
                    set $newipaddr
                    for quad in 1 2 3 4; do
                        if eval [ \$$quad -gt 255 ]; then
                            errormsg="$newipaddr is not a valid IP."
                            break
                        fi
                    done
                    if [[ -z $errormsg ]]; then
                        ipusestatus=$(grep "$newipaddr" /etc/vz/conf/*.conf)
                        if [[ -z $ipusestatus ]]; then
                            container_ipaddr=$newipaddr
                            successmsg="IP set to $newipaddr"
                            ipaddrstatus="VALID"
                        else
                            ipusectid=$(echo $ipusestatus | cut -d "/" -f 5 | cut -d "." -f 1)
                            errormsg="IP $newipaddr is used by container $ipusectid."
                        fi
                    fi
                else
                    errormsg="$newipaddr is not a valid IP."
                fi
                unset IFS
                ;;
                9)
                read -p "Enter first nameserver IP: " newnsip1
                if [[ -z $newnsip1 ]]; then
                    echo "At least one nameserver IP is required."
                else
                    if expr "$newnsip1" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                        IFS=.
                        set $newnsip1
                        for quad in 1 2 3 4; do
                            if eval [ \$$quad -gt 255 ]; then
                                errormsg="$newnsip1 is not a valid IP for nameserver 1."
                                break
                            fi
                        done
                        if [[ -z $errormsg ]]; then
                            container_nameserver1=$newnsip1
                            successmsg="Nameserver 1 set to $newnsip1"
                        fi
                    else
                        errormsg="$newnsip1 is not a valid IP for nameserver 1."
                    fi
                fi
                if [[ -z $errormsg ]]; then
                    read -p "Enter second nameserver IP: " newnsip2
                    if [[ -z $newnsip2 ]]; then
                        unset container_nameserver2
                    else
                        if expr "$newnsip2" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                            IFS=.
                            set $newnsip2
                            for quad in 1 2 3 4; do
                                if eval [ \$$quad -gt 255 ]; then
                                    errormsg="$newnsip2 is not a valid IP for nameserver 2."
                                    break
                                fi
                            done
                            if [[ -z $errormsg ]]; then
                                container_nameserver2=$newnsip2
                                successmsg="Nameservers set to $newnsip1 and $newnsip2"
                            fi
                        else
                            errormsg="$newnsip2 is not a valid IP for nameserver 2."
                        fi
                    fi
                fi
                unset IFS
                ;;
                0)
                if [[ $container_tunstatus == "ON" ]]; then
                    container_tunstatus="OFF"
                    successmsg="TUN/TAP/PPP set to OFF"
                elif [[ $container_tunstatus == "OFF" ]]; then
                    container_tunstatus="ON"
                    successmsg="TUN/TAP/PPP set to ON"
                fi
                ;;
                q)
                break
                ;;
                r)
                if [[ "$ctidstatus" == "VALID" ]]; then
                    vzctl stop $ctid
                    vzctl destroy $ctid
                    rebuild=1
                    buildct
                    break
                else
                    errormsg="Invalid option entered, please try again..."
                fi
                ;;
                *)
                if [[ "$ctidstatus" == "VALID" ]]; then
                    read -p "Rebuild Container Now? [Y/n] " buildopt
                    case $buildopt in
                        ''|y|yes|Y|YES)
                        vzctl stop $ctid
                        vzctl destroy $ctid
                        rebuild=1
                        buildct
                        break
                        ;;
                        *)
                        errormsg="Container NOT rebuilt!"
                        ;;
                    esac
                else
                    errormsg="Invalid option entered, please try again..."
                fi
                ;;
            esac
        fi

done
}

# Destroy container function
destroyct () {
    while true; do
        clear
        echo "================================================================================"
        echo "                               Destroy Container                                "
        echo "================================================================================"
        echo "[c] List all containers                [q] Exit to Main Menu"
        echo ""
        if [[ $errormsg ]]; then
            printf "\e[1;31m%s\e[0m\n\n" "ERROR: $errormsg"
            unset errormsg
        fi
        if [[ $successmsg ]]; then
            printf "\e[1;32m%s\e[0m\n\n" "SUCCESS: $successmsg"
            unset successmsg
        fi
        read -p "Enter Container ID or Choose a Menu Option: " destroyopt
        if [[ $destroyopt =~ ^-?[0-9]+$ ]]; then
            checkctid=$(vzlist -a -o ctid | grep -w $destroyopt)
            if [[ -z $checkctid ]]; then
                errormsg="Container ID $destroyopt is invalid!"
            else
                ctid=$destroyopt
                printf "\n\e[1;33mWARNING: All files will be deleted immediately%c\e[0m\n" '!'
                read -p "Confirm to destroy container $destroyopt [y/N]: " destroyconfirm
                case $destroyconfirm in
                    y|yes|Y|YES)
                    vzctl stop $destroyopt
                    vzctl destroy $destroyopt
                    successmsg="Container $destroyopt has been destroyed!"
                    break
                    ;;
                    *)
                    errormsg="Container $destroyopt has not been destroyed!"
                    break
                    ;;
                esac
            fi
        elif [[ $destroyopt == "c" ]]; then
            getctlist
        elif [[ $destroyopt == "q" ]]; then
            break
        else
            chkctid=$(vzlist -a -o ctid | grep -w $destroyopt)
            if [[ -z $chkctid ]]; then
                errormsg="Container ID entered doesn't exist..."
            fi
        fi
    done
}

# Power control function
powerct () {
    ctidstatus="INVALID"
    while true; do
        clear
        echo "================================================================================"
        echo "                            Container Power Control                             "
        echo "================================================================================"
        echo "[c] List all containers                [q] Exit to Main Menu"
        echo ""
        if [[ $ctidstatus == "VALID" ]]; then
            echo "[1] Power ON Container $pwropt"
            echo "[2] Restart Container $pwropt"
            echo "[3] Shutdown Container $pwropt"
            echo "[4] Power OFF Container $pwropt"
            echo ""
        fi
        if [[ $errormsg ]]; then
            printf "\e[1;31m%s\e[0m\n\n" "ERROR: $errormsg"
            unset errormsg
        fi
        if [[ $successmsg ]]; then
            printf "\e[1;32m%s\e[0m\n\n" "SUCCESS: $successmsg"
            unset successmsg
        fi
        if [[ $ctidstatus == "VALID" ]]; then
            read -p "Choose an option: " pwraction
            case $pwraction in
                1)
                vzctl start $pwropt
                successmsg="Container $pwropt has been Powered ON."
                break
                ;;
                2)
                vzctl restart $pwropt
                successmsg="Container $pwropt has been Restarted."
                break
                ;;
                3)
                vzctl stop $pwropt
                successmsg="Container $pwropt has been Shut Down."
                break
                ;;
                4)
                vzctl stop $pwropt --fast
                successmsg="Container $pwropt has been Powered OFF."
                break
                ;;
                c)
                getctlist
                ;;
                q)
                break
                ;;
            esac
        else
            read -p "Enter Container ID or Choose a Menu Option: " pwropt
            if [[ $pwropt =~ ^-?[0-9]+$ ]]; then
                checkctid=$(vzlist -a -o ctid | grep -w $pwropt)
                if [[ -z $checkctid ]]; then
                    errormsg="Container ID $pwropt is invalid!"
                else
                    ctid=$pwropt
                    successmsg="Selected container $pwropt"
                    ctidstatus="VALID"
                fi
            elif [[ $pwropt == "c" ]]; then
                getctlist
            elif [[ $pwropt == "q" ]]; then
                break
            else
                errormsg="Invalid option entered, please try again..."
            fi
        fi
    done
}

# Change container root user password function
modifyct () {
    getctinfo="TRUE"
    ctid="NOT SET"
    ctidstatus="INVALID"
    while true; do
        ramnounit=$( echo $container_ramsize | cut -d 'M' -f 1 )
        swapnounit=$( echo $container_swapsize | cut -d 'M' -f 1 )
        container_totalram=$(expr $ramnounit + $swapnounit)"M"
        if [[ $ctid =~ ^-?[0-9]+$ ]]; then
            chkctid=$(vzlist -a -o ctid | grep -w $ctid)
            if [[ -z $chkctid ]]; then
                errormsg="Container ID entered doesn't exist..."
                ctidstatus="INVALID"
            else
                ctidstatus="VALID"
            fi
        elif [[ $ctid == "NOT SET" ]]; then
            # This line serves no purpose
            ctid="NOT SET"
        else
            errormsg="Invalid Container ID, please try again..."
        fi
        container_nameserver="$container_nameserver1$(if [[ $container_nameserver2 ]]; then echo ",$container_nameserver2"; fi)"
        getcpucoreunit
        spacecount=$(expr 23 - ${#container_ramsize})
        clear
        echo "================================================================================"
        echo "                           Modify Container Settings                            "
        echo "================================================================================"
        echo "[c] List all containers                [q] Exit to Main Menu"
        if ! [[ "$ctidstatus" == "VALID" ]]; then
            printf "\n\e[1;31m%s\e[0m\n\n" "Container ID:                          $ctid"
        else
            printf "\n%s\n\n" "[1] Container ID:                      $ctid"
        fi
        if [[ "$ctidstatus" == "VALID" ]]; then
            if [[ $(vzctl status "$ctid" | grep "down") ]]; then
                vzctl start "$ctid"
                sleep 3
            fi
            if [[ $getctinfo == "TRUE" ]]; then
                container_rootpass=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_ROOT_PASS' | cut -d ':' -f 2)
                container_hostname=$(cat /etc/vz/conf/$ctid.conf | grep 'HOSTNAME' | cut -d '"' -f 2)
                container_template=$(cat /etc/vz/conf/$ctid.conf | grep 'OSTEMPLATE' | cut -d '"' -f 2)
                container_cpucore=$(cat /etc/vz/conf/$ctid.conf | grep 'CPUS' | cut -d '"' -f 2)
                container_diskquota=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_DISK_QUOTA' | cut -d ':' -f 2)
                container_ramsize=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_RAM_SIZE' | cut -d ':' -f 2)
                container_swapsize=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_SWAP_SIZE' | cut -d ':' -f 2)
                container_ipaddr=$(cat /etc/vz/conf/$ctid.conf | grep 'IP_ADDRESS' | cut -d '"' -f 2)
                container_nameserver1=$(cat /etc/vz/conf/$ctid.conf | grep 'NAMESERVER' | cut -d '"' -f 2 | cut -d ' ' -f 1)
                container_nameserver2=$(cat /etc/vz/conf/$ctid.conf | grep 'NAMESERVER' | cut -d '"' -f 2 | cut -d ' ' -f 2)
                container_tunstatus=$(cat /etc/vz/conf/$ctid.conf | grep 'CONTAINER_TUN_STATUS' | cut -d ':' -f 2)
                getcpucoreunit
                spacecount=$(expr 23 - ${#container_ramsize})
                if [[ $container_nameserver1 == $container_nameserver2 ]]; then
                    unset container_nameserver2
                fi
                container_nameserver="$container_nameserver1$(if [[ $container_nameserver2 ]]; then echo ",$container_nameserver2"; fi)"
                orig_tunstatus=$container_tunstatus
                orig_ipaddr=$container_ipaddr
                getctinfo="FALSE"
            fi
            echo "[2] CPU:                               $container_cpucore $cpucoreunit"
            printf "%s%$(echo $spacecount)s%s\n" "[3] RAM Size:   $container_ramsize" "" "vSWAP Size:   $container_swapsize"
            echo "[4] Disk Space:                        $container_diskquota"
            echo "[5] Root Password:                     $container_rootpass"
            echo ""
            echo "[6] IP Address:                        $container_ipaddr"
            echo "[7] Nameservers:                       $container_nameserver"
            echo "[8] Hostname:                          $container_hostname"
            echo "[9] TUN/TAP/PPP:                       $container_tunstatus"
            echo ""
            echo "[s] Save new settings to container"
            echo ""
        fi
        if [[ $errormsg ]]; then
            printf "\e[1;31m%s\e[0m\n\n" "ERROR: $errormsg"
            unset errormsg
        fi
        if [[ $successmsg ]]; then
            printf "\e[1;32m%s\e[0m\n\n" "SUCCESS: $successmsg"
            unset successmsg
        fi
        if ! [[ "$ctidstatus" == "VALID" ]]; then
            read -p "Enter Container ID or Choose a Menu Option: " mdfyopt
            if [[ $mdfyopt =~ ^-?[0-9]+$ ]]; then
                checkctid=$(vzlist -a -o ctid | grep -w $mdfyopt)
                if [[ -z $checkctid ]]; then
                    errormsg="Container ID $mdfyopt is invalid!"
                else
                    ctid=$mdfyopt
                    successmsg="Selected container $mdfyopt"
                    getctinfo="TRUE"
                fi
            elif [[ $mdfyopt == "c" ]]; then
                getctlist
            elif [[ $mdfyopt == "q" ]]; then
                break
            else
                errormsg="Invalid option entered, please try again..."
            fi
        else
            read -p "Choose an option: " mdfyopt
            case $mdfyopt in
                1)
                read -p "Enter a Container ID: " newctid
                checkctid=$(vzlist -a -o ctid | grep -w $newctid)
                if [[ -z $checkctid ]]; then
                    errormsg="Container ID $newctid is invalid!"
                else
                    ctid=$newctid
                    successmsg="Selected container $newctid"
                    getctinfo="TRUE"
                fi
                ;;
                2)
                maxcpucore=$(grep -c ^processor /proc/cpuinfo)
                read -p "Enter the number of CPU vCores [max: $maxcpucore]: " newvcore
                if [[ $newvcore =~ ^-?[0-9]+$ ]]; then
                    if [[ $newvcore -lt 1 ]] || [[ $newvcore -gt $maxcpucore ]]; then
                        errormsg="CPU vCore must be between 1 and $maxcpucore"
                    else
                        container_cpucore=$newvcore
                        successmsg="CPU vCore set to $newvcore"
                        modify_cpu=1
                    fi
                else
                    errormsg="CPU vCore must be between 1 and $maxcpucore"
                fi
                ;;
                3)
                read -p "Enter amount of RAM (in MB): " newram
                if [[ $newram =~ ^-?[0-9]+$ ]]; then
                    container_ramsize=$newram"M"
                else
                    errormsg="Please enter number only, without any units."
                fi
                if [[ -z $errormsg ]]; then
                    read -p "Enter amount of vSwap (in MB): " newswap
                    if [[ $newswap =~ ^-?[0-9]+$ ]]; then
                        container_swapsize=$newswap"M"
                        successmsg="RAM set to $container_ramsize, vSwap set to $container_swapsize"
                        modify_ram=1
                    else
                        errormsg="Please enter number only, without any units."
                    fi
                fi
                ;;
                4)
                read -p "Enter amount of disk space (in GB): " newdiskquota
                if [[ $newdiskquota =~ ^-?[0-9]+$ ]]; then
                    if [[ "$newdiskquota" -lt 1 ]]; then
                        errormsg="Disk quota must be 1G or more."
                    else
                        container_diskquota=$newdiskquota"G"
                        successmsg="Disk quota set to $container_diskquota"
                        modify_disk=1
                    fi
                else
                    errormsg="Please enter number only, without any units."
                fi
                ;;
                5)
                read -p "Enter a new root user password: " container_rootpass
                successmsg="Root user password set to $container_rootpass"
                modify_rootpass=1
                ;;
                6)
                read -p "Enter the IP address: " newipaddr
                if expr "$newipaddr" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                    IFS=.
                    set $newipaddr
                    for quad in 1 2 3 4; do
                        if eval [ \$$quad -gt 255 ]; then
                            errormsg="$newipaddr is not a valid IP."
                            break
                        fi
                    done
                    if [[ -z $errormsg ]]; then
                        ipusestatus=$(grep "$newipaddr" /etc/vz/conf/*.conf)
                        if [[ -z $ipusestatus ]]; then
                            container_ipaddr=$newipaddr
                            successmsg="IP set to $newipaddr"
                            ipaddrstatus="VALID"
                            modify_ip=1
                        else
                            ipusectid=$(echo $ipusestatus | cut -d "/" -f 5 | cut -d "." -f 1)
                            errormsg="IP $newipaddr is used by container $ipusectid."
                        fi
                    fi
                else
                    errormsg="$newipaddr is not a valid IP."
                fi
                unset IFS
                ;;
                7)
                read -p "Enter first nameserver IP: " newnsip1
                if [[ -z $newnsip1 ]]; then
                    echo "At least one nameserver IP is required."
                else
                    if expr "$newnsip1" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                        IFS=.
                        set $newnsip1
                        for quad in 1 2 3 4; do
                            if eval [ \$$quad -gt 255 ]; then
                                errormsg="$newnsip1 is not a valid IP for nameserver 1."
                                break
                            fi
                        done
                        if [[ -z $errormsg ]]; then
                            container_nameserver1=$newnsip1
                            successmsg="Nameserver 1 set to $newnsip1"
                        fi
                    else
                        errormsg="$newnsip1 is not a valid IP for nameserver 1."
                    fi
                fi
                if [[ -z $errormsg ]]; then
                    read -p "Enter second nameserver IP: " newnsip2
                    if [[ -z $newnsip2 ]]; then
                        unset container_nameserver2
                        modify_nameserver=1
                    else
                        if expr "$newnsip2" : '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*$' >/dev/null; then
                            IFS=.
                            set $newnsip2
                            for quad in 1 2 3 4; do
                                if eval [ \$$quad -gt 255 ]; then
                                    errormsg="$newnsip2 is not a valid IP for nameserver 2."
                                    break
                                fi
                            done
                            if [[ -z $errormsg ]]; then
                                container_nameserver2=$newnsip2
                                successmsg="Nameservers set to $newnsip1 and $newnsip2"
                                modify_nameserver=1
                            fi
                        else
                            errormsg="$newnsip2 is not a valid IP for nameserver 2."
                        fi
                    fi
                fi
                unset IFS
                ;;
                8)
                read -p "Enter a new hostname: " container_hostname
                successmsg="Container hostname set to $container_hostname"
                modify_hostname=1
                ;;
                9)
                if [[ $container_tunstatus == "ON" ]]; then
                    container_tunstatus="OFF"
                    successmsg="TUN/TAP/PPP set to OFF"
                elif [[ $container_tunstatus == "OFF" ]]; then
                    container_tunstatus="ON"
                    successmsg="TUN/TAP/PPP set to ON"
                fi
                if [[ $container_tunstatus == $orig_tunstatus ]]; then
                    unset modify_tun
                else
                    modify_tun=1
                fi
                ;;
                s)
                domodifyct
                break
                ;;
                c)
                getctlist
                ;;
                q)
                break
                ;;
                *)
                if [[ "$ctidstatus" == "VALID" ]]; then
                    read -p "Save changes now? [Y/n] " svchgopt
                    case $svchgopt in
                        ''|y|yes|Y|YES)
                        domodifyct
                        break
                        ;;
                        *)
                        errormsg="Container configuration not saved!"
                        ;;
                    esac
                else
                    errormsg="Invalid option entered, please try again..."
                fi
                ;;
            esac
        fi
    done
}

domodifyct () {
    if [[ $modify_cpu ]]; then
        vzctl set "$ctid" --cpus "$container_cpucore" --save
        unset modify_cpu
    fi
    if [[ $modify_ram ]]; then
        vzctl set "$ctid" --ram "$container_ramsize" --swap "$container_swapsize" --save
        vzctl set "$ctid" --privvmpages "unlimited" --save
        vzctl set "$ctid" --vmguarpages "unlimited" --save
        vzctl set "$ctid" --oomguarpages "unlimited" --save
        vzctl set "$ctid" --kmemsize "$((524288 * $ramnounit))" --save
        vzctl set "$ctid" --lockedpages "$((128 * $ramnounit))" --save
        vzctl set "$ctid" --dcachesize "$((262144 * $ramnounit))" --save
        sed -i "s/^#\s*CONTAINER_RAM_SIZE.*/# CONTAINER_RAM_SIZE:$container_ramsize/g" /etc/vz/conf/$ctid.conf
        sed -i "s/^#\s*CONTAINER_SWAP_SIZE.*/# CONTAINER_SWAP_SIZE:$container_swapsize/g" /etc/vz/conf/$ctid.conf
        unset modify_ram
    fi
    if [[ $modify_disk ]]; then
        vzctl set "$ctid" --diskspace "$container_diskquota" --save
        sed -i "s/^#\s*CONTAINER_DISK_QUOTA.*/# CONTAINER_DISK_QUOTA:$container_diskquota/g" /etc/vz/conf/$ctid.conf
        unset modify_disk
    fi
    if [[ $modify_rootpass ]]; then
        vzctl set "$ctid" --userpasswd root:"$container_rootpass" --save
        sed -i "s/^#\s*CONTAINER_ROOT_PASS.*/# CONTAINER_ROOT_PASS:$container_rootpass/g" /etc/vz/conf/$ctid.conf
        unset modify_rootpass
    fi
    if [[ $modify_ip ]]; then
        vzctl set "$ctid" --ipdel "$orig_ipaddr" --save
        vzctl set "$ctid" --ipadd "$container_ipaddr" --save
        unset modify_ip
    fi
    if [[ $modify_nameserver ]]; then
        if [[ -z $container_nameserver2 ]]; then
            vzctl set "$ctid" --nameserver "$container_nameserver1" --save
        else
            vzctl set "$ctid" --nameserver "$container_nameserver1" --nameserver "$container_nameserver2" --save
        fi
        unset modify_nameserver
    fi
    if [[ $modify_hostname ]]; then
        vzctl set "$ctid" --hostname "$container_hostname" --save
        unset modify_hostname
    fi
    if [[ $modify_tun ]]; then
        if [[ $container_tunstatus == "ON" ]]; then
            vzctl stop "$ctid"
            sleep 3
            vzctl set "$ctid" --capability net_admin:on --save
            vzctl set "$ctid" --features ppp:on --save
            vzctl start "$ctid"
            sleep 3
            vzctl set "$ctid" --devnodes net/tun:rw --save
            vzctl set "$ctid" --devices c:10:200:rw --save
            vzctl set "$ctid" --devices c:108:0:rw --save
            vzctl exec "$ctid" mkdir -p /dev/net
            vzctl exec "$ctid" chmod 600 /dev/net/tun
            vzctl exec "$ctid" mknod /dev/ppp c 108 0
            vzctl exec "$ctid" chmod 600 /dev/ppp
        else
            vzctl exec "$ctid" rm -rf /dev/net/tun
            sed -i "/^DEVNODES/d" /etc/vz/conf/$ctid.conf
            sed -i "/^DEVICES/d" /etc/vz/conf/$ctid.conf
            sed -i "/^CAPABILITY/d" /etc/vz/conf/$ctid.conf
            sed -i "/^FEATURES/d" /etc/vz/conf/$ctid.conf
        fi
        sed -i "s/^#\s*CONTAINER_TUN_STATUS.*/# CONTAINER_TUN_STATUS:$container_tunstatus/g" /etc/vz/conf/$ctid.conf
        unset modify_tun
    fi
    successmsg="Container configuration saved to /etc/vz/conf/$ctid.conf"
}

# Get all containers
getctlist () {
    vzlist -a | less
}

# Check for root account
if [[ "$EUID" -ne 0 ]]; then
    echo "Sorry, you need to run this as root"
    exit 1
fi

# Check for updates
if [[ "$1" == "update" ]] || [[ "$1" == "upgrade" ]]; then
    printf "Updating OpenVZ Bash Manager, please wait...\n"
    wget -qO /usr/bin/ovzmanager https://git.io/ovzmanager --no-check-certificate && chmod +x /usr/bin/ovzmanager
    sleep 1
    printf "OpenVZ Bash Manager has been updated to the latest version!\n"
    exit 0
fi

# Check for OpenVZ kernel
if ! [[ $(uname -r) == *"stab"* ]]; then
    ovzkernelcheck=$(ls /boot | grep "stab")
    if [[ -z $ovzkernelcheck ]]; then
        echo "You must have OpenVZ kernel and tools installed for this script to work."
        echo "Try the OpenVZ Bash Installer script: https://git.io/ovzinstaller"
    else
        echo "Reboot your server and select the OpenVZ kernel to use this script."
    fi
    exit 1
fi

# Get current working directory
currentpwd=$(pwd)

# Check and enable TUN module
checktunstatus=$(lsmod | grep tun)
if [[ -z $checktunstatus ]]; then
    modprobe tun
    if [[ -f /etc/rc.modules ]]; then
        if [[ -z $(grep "tun" /etc/rc.modules) ]]; then
            echo modprobe tun >> /etc/rc.modules 
            chmod +x /etc/rc.modules
        fi
    elif [[ -d /etc/rc.modules ]]; then
        rm -rf /etc/rc.modules
        echo modprobe tun >> /etc/rc.modules 
        chmod +x /etc/rc.modules
    else
        echo modprobe tun >> /etc/rc.modules 
        chmod +x /etc/rc.modules
    fi
fi

while true; do
    clear
    echo "================================================================================"
    echo "                              OpenVZ Bash Manager                               "
    echo "================================================================================"
    echo ""
    echo "[1] New Container"
    echo "[2] Rebuild Container"
    echo "[3] Destroy Container"
    echo ""
    echo "[4] Power ON/OFF Container"
    echo "[5] Modify Container Settings"
    echo ""
    echo "[6] List All Containers"
    echo "[7] List All Templates"
    echo "[q] Quit OpenVZ Bash Manager"
    echo ""
    if [[ ! -z $errormsg ]]; then
        printf "\e[1;31m%s\e[0m\n\n" "ERROR: $errormsg"
        unset errormsg
    fi
    if [[ $successmsg ]]; then
        printf "\e[1;32m%s\e[0m\n\n" "SUCCESS: $successmsg"
        unset successmsg
    fi
    read -p "Choose an option: " ctlopt
    case $ctlopt in
        1)
        newct
        ;;
        2)
        rebuildct
        ;;
        3)
        destroyct
        ;;
        4)
        powerct
        ;;
        5)
        modifyct
        ;;
        6)
        getctlist
        ;;
        7)
        alltemp=$(ls -1 /vz/template/cache/ | sed -e 's/\.[^.]*tar.gz//')
        printf "%s\n" "$alltemp" | less
        ;;
        q)
        printf "\nThank you for using OpenVZ Bash Manager! Bye.\n\n"
        break
        ;;
    esac
done