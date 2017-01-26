# Author:       Sam Ransford
# Creation Date:
# Last Modified:June 15th 2016
#
#################################


# Variables
##############

theFile=HostList
tmpFile=tmpHosts.txt
i=0
online=0
offline=0
ipmiIssue=0
hostList=""
problemHosts=""
args=("$@")

## Functions
##############

function clearAttributes {
        # Used to help clear problem attributes in bulk (e.g. SITEOPS-12089)
        while read host; do
                myOutput=`problem -H $host clean`
                #echo "(test) $myOutput"
        done <$theFile
}

function getHostList {
        hosts=''
        newLine=4
        i=0
        while read host; do
                let "i++"
                if [[ $i == $newLine ]]
                then
                        hosts=$host"\n"
                fi
                hosts=$hosts", "$host
        done<$theFile
}

function getPowerStatus {
        # Utilize lom to get the power status of each host in the HostList
        while read host; do
                status=`lom.sh --status -y -H $host`
                if [[ $status == *"on"* ]]
                then
                        printf "$host is powered on\n"
                elif [[ $status == *"off"* ]]
                then
                        printf "$host is powered off\n"
                elif [[ $status == *"Unable"* ]]
                then
                        printf "$host has IPMI issues\n"
                else
                        printf "$host has IPMI issues\n"
                fi
        done <$theFile
}

function newHostList {
        usr=`whoami`
        rm $theFile
        touch $theFile
        chmod 755 $theFile
        chown $usr $theFile
        printf "New host list created.\n"
}
function getHostList {
        # Get list of hosts and their statuses (online/offline)
        # then append to an array for easier processing later on
        ipmiIssues=0
        while read host; do
                #printf "$host\n"
                let "i++"
                status=`lom.sh --status -y -H $host`
                if [[ $status == *"on"* ]]
                then
                        #printf "$host is online\n"
                        hostList="$hostList $host"
                        echo $hostList >> $tmpFile
                elif [[ $status == *"off"* ]]
                then
                        #printf "$host is offline\n"
                        hostList="$hostList $host"
                        echo $hostList >> $tmpFile
                elif [[ $status == *"Unable"* ]]
                then
                        printf "($host) Unable to establish IPMI connection - Added to issues list\n"
                        let "ipmiIssues++"
                else
                        printf "($host) has IPMI issues - did not add to hosts list\n"
                        let "ipmiIssues++"
                fi
        done <$theFile
        if [[ $ipmiIssues > 0 ]]
        then
                printf "\n$ipmiIssues have IPMI issues\n"
        fi
}

function cronusInstall {
        printf "\n**This process requires a manual reboot of each system.\nIt gives the tech 1 minute after setting the host for rekick to allow\nfor placing host back into the rack, and plugging it in."
        hostCount=`cat $theFile | wc -l`
        i=0
        while read host; do
                let "i++"
                #myMainten=`wlm-move -N maintenance $host`
                #myUnmonit=`loony -H $host set attribute unmonitored:999999999999999`
                myInstall=`provctl -N --no-reboot reinstall $host`      # Place provctl cmd in a variable to help w/
                if [[ $myInstall == *"success"* || $myInstall == *"Success"* ]]
                then
                        echo "$host set for rekick!"
                        if [[ $i == $hostCount ]]
                        then
                                echo "** FINAL HOST **\n\n"
                                exit;
                        fi
                        sleep 1m
                else
                        printf "*****$host - FAILURE***** \n\t\t$myInstall";
                fi
        done < $theFile;
}

function rcom {
        # Get Burnin, Sku verification, and PV status of a specified rack
        if [[ -z $1 ]]
        then
                echo "No rack specified"
        else
                rack=$1
                printf "Information for rack '$1'\n"
                printf "Burnin and verification statuses for the specified rack.\n\n"
                printf "Hostname\t\t\t Ver Sku   RAM\t     Disk      CPU\t PV   Platform"
                printf "\n-------------------------------------------------------------------------------------|\n"
                loony -D smf1 -l "%(facts:hostname)s,%(attributes:wilson_verify_sku)s,%(attributes:burnin_ram)s,%(attributes:burnin_disk)s,%(attributes:burnin_cpu)s,%(attributes:physical_verification)s,%(groups:platform)s" -g rack:$1 | sort
        fi
}

function runProcess {
        # Function to accept processing tasks - core feature
        doProc=$1       # This is what goes into provctl for processing
        procName=$2     # This is what's presented to the user
        hosts=``
        if [[ ${args[0]} == "-Ci" || ${args[1]} == "-Ci" ]]
        then
                echo "Reinstalling cronus systems"
        elif [[ ${args[0]} == "-Nhl" || ${args[0]} == "-Nhl" ]]
        then
                echo "" # Do nothing
        else
                echo "" #getHostList    # Generate list of hosts that can be used by provctl
        fi
        printf "\nProcess Selected:.$procName\n"

        if [[ ${args[0]} -ne "-Ps" || ${args[1]} -ne "-Nhl" ]]
        then
                printf "Host Count:.......$i\n\n"
        fi
        if [[ ${args[0]} == "-Ps" || ${args[1]} == "-Ps" ]]
        then
                getPowerStatus
                exit
        fi
        if [[ ${args[1]} == "-w" || ${args[0]} == "-w" || ${args[1]} == "-Ca" || ${args[0]} == "-Ca" ]]
        then
                printf "Are you sure? (y/n) "; read usrConfirm
                printf "\n"
        else
                if [[ ${args[2]} == "-n" || ${args[1]} == "-n" || ${args[0]} == "-n" ]]
                then
                        usrConfirm="y"
                else
                        printf "Are you sure? (y/n) "; read usrConfirm
                        printf "\n"
                fi
        fi
        if [[ $usrConfirm == "y" || $usrConfirm == "Y" ]]
        then
                if [[ ${args[0]} == "-Ci" || ${args[1]} == "-Ci" ]]
                then
                        #Perform cronus install process
                        cronusInstall
                elif [[ ${args[0]} == "-Rs" ]]
                then
                        #Get a specified rack's status (burnin, sku verification, and pyhisical verification)
                        rcom ${args[1]}
                elif [[ ${args[0]} == "-Po" || ${args[1]} == "-Po" ]]
                then
                        #Poweron hosts
                        while read host; do ipmitool -U root -P root -H $host.ipmi.twitter.com -I lanplus power on; done<$theFile
                elif [[ ${args[0]} == "-Pf" || ${args[1]} == "-Pf" ]]
                then
                        #Poweroff hosts
                        while read host; do ipmitool -U root -P root -H $host.ipmi.twitter.com -I lanplus power off; done<HostList
                elif [[ ${args[0]} == "-Pr" || ${args[1]} == "-Pr" ]]
                then
                        #Poweroff hosts
                        while read host; do ipmitool -U root -P root -H $host.ipmi.twitter.com -I lanplus power reset; done<HostList
                elif [[ ${args[0]} == "-vbond" || ${args[1]} == "-vbond" ]]
                then
                        #Verify bond on hosts
                        lom.sh --verifybond -y -F $theFile
                elif [[ ${args[0]} == "-unbond" || ${args[1]} == "-unbond" ]]
                then
                        #Unbond hosts
                        lom.sh --swunbond -y -F $theFile
                elif [[ ${args[0]} == "-unmon" || ${args[1]} == "-unmon" ]]
                then
                        #Unmonitor hosts
                        cmd=`loony -F $theFile set attribute unmonitored:99999999999999`
                        printf "Hosts unmonitored\n"
                elif [[ ${args[0]} == "-iden" || ${args[1]} == "-iden" ]]
                then
                        #Turn on identifier lights indefinitely
                        for i in `cat $theFile`;do printf "$i\n"; ipmitool -U root -P root -H $i.ipmi.twitter.com -I lanplus chassis identify forced;done
                elif [[ ${args[0]} == "-idenf" || ${args[1]} == "-idenf" ]]
                then
                        #Turn off identifier lights
                        for i in `cat $theFile`;do ipmitool -U root -P root -H $i.ipmi.twitter.com -I lanplus chassis identify off forced;done
                elif [[ ${args[0]} == "-serv" || ${args[1]} == "-serv" ]]
                then
                        #Get host's services, platform, augmentation, and monitor status
                        loony -F $theFile | awk '{ printf $1"\t"$2"\t"$4"\t\t"$5"\n" }' | sort
                elif [[ ${args[0]} == "-Fd" || ${args[1]} == "-Fd" ]]
                then
                        #Get failed drives
                        if [[ ${args[0]} == "hyve" || ${args[1]} == "hyve" || ${args[2]} == "hyve" ]]
                        then
                                loony -F $theFile -S run 'echo "[$(/usr/local/sbin/healthcheck3.sh | cut -c75- | sed 's/,.*//')]";'
                        elif [[ ${args[0]} == "hp" || ${args[1]} == "hp" || ${args[2]} == "hp" ]]
                        then
                                loony -F $theFile -S run 'echo "[$(/usr/sbin/hpacucli ctrl all show config | grep -Ei 'fail')]" '
                        elif [[ ${args[0]} == "dell" || ${args[1]} == "dell" || ${args[2]} == "dell" ]]
                        then
                                loony -F $theFile -S run 'echo "[$(/usr/sbin/hpacucli ctrl all show config | grep -Ei 'fail')]" '
                        fi
                elif [[ ${args[*]} == *"-Bp"* ]]
                then
                        # Force hosts to PXE boot
                        while read host; do
                                printf $host" "
                                ipmitool -I lanplus -H $host.ipmi.twitter.com -U root -P root chassis bootdev pxe options=persistent
                        done<$theFile
                elif [[ ${args[0]} == "-Ca" || ${args[1]} == "-Ca" ]]
                then
                        # Clears problem attibutes
                        clearAttributes
                elif [[ ${args[0]} == "-Nhl" || ${args[1]} == "-Nhl" ]]
                then
                        # Create new hosts list
                        newHostList
                elif [[ ${args[0]} == "-sm" || ${args[1]} == "-sm" ]]
                then
                        # NetEng Switch Mapping
                        usrName=`whoami`
                        netFile='git/neteng/switch_mapping_smf.py'
                        if [[ ! -d "~/git" ]]
                        then
                                printf "Git folder already created... Continuing...\n"
                        else
                                printf "Creating git folder...\n"
                                mkGit=`mkdir /Users/$usrName/git`
                                printf "Git folder created... Continuing...\n"
                        fi
                        if [[ ! -d "~/git/neteng" ]]
                        then
                                printf "Git repository exists, proceeding with switch mapping"
                        else
                                printf "You don't have the NetEng Repository downloaded. We're downloading it now.\n"
                                getGit=`git clone https://git.twitter.biz/neteng ~/git/neteng`
                                printf "\nNetEng repository has been downloaded."
                        fi
                        printf "Did you want the AS switch or the MS switch? (as/ms): "; read usrChoice
                        if [[ $usrChoice == "as" || $usrChoice == "AS" ]]
                        then
                                printf "Specify a rack, leave blank if you want the whole file: "; read usrRack
                                if [[ -z $usrRack ]]
                                then
                                        ~/$netFile AS | sort
                                else
                                        ~/$netFile AS | grep $usrRack
                                fi
                        else
                                printf "Specify a rack, leave blank if you want the whole file: "; read usrRack
                                if [[ -z $usrRack ]]
                                then
                                        ~/$netFile MS | sort
                                else
                                        ~/$netFile MS | grep $usrRack
                                fi
                        fi
                elif [[ ${args[0]} == "-mi" || ${args[1]} == "-mi" ]]
                then
                        printf "Which zone? "; read zone
                        ~/git/neteng/tools_dev $ ./aud_rackify.py -u $zone
                elif [[ ${args[0]} == "-mt" || ${args[1]} == "-mt" ]]
                then
                        printf "Specify a rack triplet: "; read rack
                        printf "Specify Data Center: "; read dc
                        printf "Working on $dc-$rack-as1-1.net.twitter.com, standby...";
                        loony -D $dc -e network -H $dc-$rack-as1-1.net.twitter.com unset attribute unmonitored:true
                        loony -D $dc -e network -H $dc-$rack-as1-1.net.twitter.com set attribute loopback:true
                        loony -D $dc -e network -H $dc-$rack-as1-1.net.twitter.com unset attribute skip_nagios:true
                        printf "\n$dc-$rack-as1-1.net.twitter.com has been completed...\n Now working on $dc-$rack-ms1-1.net.twitter.com, standby...\n"
                        loony -D $dc -e network -H $dc-$rack-ms1-1.net.twitter.com unset attribute unmonitored:true
                        loony -D $dc -e network -H $dc-$rack-ms1-1.net.twitter.com set attribute loopback:true
                        loony -D $dc -e network -H $dc-$rack-ms1-1.net.twitter.com unset attribute skip_nagios:true
                        printf "\n$dc-$rack-ms1-1.net.twitter.com has been completed! No further actions required!\n"
                else
                        #Provctl command
                        if [[ ${args[0]} == "-r" || ${args[1]} == "-r" ]]
                        then
                                # This argument is for the rekick option. It checks if the platform is a gemini or yellowjacket and asks the user
                                # if they want to update the sku to accomedate a boot drive swap that gets upgraded to a 1TB drive.
                                hostPlatform=`loony -F $theFile -l "%(groups:base_platform)s"`
                                if [[ $hostPlatform == *"gemini"* || $hostPlatform == *"Gemini"* || $hostPlatform == *"yellowjacket"* || $hostPlatform == *"Yellowjacket"* ]]
                                then
                                        printf "\n1 or more Gemini hosts found. When replacing the boot drive, the sku may need to be updated to accomedate the upgraded 1 TB drive. Would you like to update the sku? (y/n)"; read skuConfirm
                                        if [[ $skuConfirm == "y" || $skuConfirm == "Y" || $skuConfirm == "yes" || $skuConfirm == "Yes" ]]
                                        then
                                                while read host; do
                                                        platformConfirm=`loony -H $host -l "%(groups:base_platform)s"`
                                                        if [[ $platformConfirm == "gemini" || $platformConfirm == "Gemini" ]]
                                                        then
                                                                cmd=`loony -H $host set attribute sku_signature:2xIntel.R.Xeon.R.CPUE5645_M72_N2_S0_D25000`
                                                        elif [[ $platformConfirm == "yellowjacket" || $platformConfirm = "Yellowjacket" ]]
                                                        then
                                                                cmd=`loony -H $host set attribute sku_signature:2xIntel.R.Xeon.R.CPUE5620_M48_N2_S0_D25000`
                                                        fi
                                                done <$theFile
                                                printf "SKU successfully changed for all hosts\n"
                                        fi
                                fi
                        fi
                        if [[ $doProc == *"reinstall"* ]]
                        then
                                printf "Image argument applied, expect kickstart completion in 20-30 minutes.\n"
                                provctl -N $doProc --image - < $theFile
                        else
                                provctl -N $doProc - < $theFile
                        fi
                fi
                if [[ $problemHosts != "" ]]
                then
                        #Print the hosts that have IPMI issues
                        printf $problemHosts
                fi
        else
                printf "User unsure - exiting\n"
                exit
        fi
        exit
}

## Argument
## Processing
##############

if [[ ${args[0]} == "-h" || -z ${args[0]} ]]
then
        printf "
        #######################################
        #                                     #
        #       SiteOps Automation Tool       #
        #                                     #
        #######################################

        -c        Cancel Plan(s)
        -h        Get this help prompt
        -n        Non-Interactive Mode
        -r        Rekick hosts
        -s        Get plan status(es)
        -v        Verify SKU
        -w        Wipe drives in hosts list - forced confirmation
        -Ba       Set hosts to run through all burnin
        -Bc       Set hosts to run through CPU burnin
        -Bd       Set hosts to run through disk burnin
        -Br       Set hosts to run through RAM burnin
        -Bu       Run firmware/bios update on hosts
        -Bp       Set hosts to boot off of PXE
        -Ca       Clear problem attributes - forced confirmation
        -Ci       Reinstall cronus platform
        -Fd [mfg] Get failed drives for host - [mfg] for manufacturer [hp & hyve]
        -iden     Turn on identifier lights
        -idenf    Turn off identifier lights
        -mi       Audubon Injection of Network Devices
        -mt       TOR monitoring (nagios)
        -Nhl      Remove old Hosts List and create a new one
        -Pf       Poweroff Machines
        -Po       Poweron Machines
        -Pr       Reboot Machines
        -Ps       Get host's power status (IPMI testing)
        -Rs [abc] Get a rack's burnin, sku verification, and physical verification statuses - must be the only arguments
        -serv     Get host's services and it's monitor status
        -sm       Switch Mapping - (rack, core port, core switch)
        -unmon    Unmonitor Hosts
        -unbond   Unbond hosts
        -vbond    Verify bond status

"
        exit
elif [[ ${args[*]} == *"-r"* ]]
then
        #Rekick hosts
        runProcess reinstall Rekick
        exit
elif [[ ${args[*]} == *"-v"* ]]
then
        #Verify SKU
        runProcess verify "Verify SKU"
        exit
elif [[ ${args[*]} == *"-c"* ]]
then
        #Cancel plan(s)
        runProcess cancel "Cancel Plan(s)"
        exit
elif [[ ${args[*]} == *"-s"* ]]
then
        #Get statuses of hosts
        runProcess show "View Status(es)"
        exit
elif [[ ${args[*]} == *"-w"* ]]
then
        #Wipe drives
        runProcess wipe "Drive wipe"
        exit
elif [[ ${args[*]} == *"-Ba"* ]]
then
        #Burn in all
        runProcess "burnin all" "Burnin - All"
        exit
elif [[ ${args[*]} == *"-Bc"* ]]
then
        #Burn in CPU
        runProcess "burnin cpu" "Burnin - CPU"
        exit
elif [[ ${args[*]} == *"-Bd"* ]]
then
        #Burn in disk
        runProcess "burnin disk" "Burnin - Disk"
        exit
elif [[ ${args[*]} == *"-Br"* ]]
then
        #Burn in ram
        runProcess "burnin ram" "Burnin - RAM"
        exit
elif [[ ${args[*]} == *"-Bu"* ]]
then
        #Bios Update
        runProcess firmware_update "Bios Update"
        exit
elif [[ ${args[*]} == *"-Bp"* ]]
then
        #Set hosts to PXE boot
        runProcess pxe_boot "Force PXE boot"
        exit
elif [[ ${args[*]} == *"-Ca"* ]]
then
        #Clears problem attrbiutes
        runProcess clear_attributes "Clear Problem Attributes"
elif [[ ${args[*]} == *"-Ci"* ]]
then
        #Reinstall cronus systems
        runProcess "reinstall" "Reinstall Cronus Hosts"
elif [[ ${args[*]} == *"-Fd"* ]]
then
        #Get power status
        runProcess failedDrive  "Get Failed drives"
elif [[ ${args[*]} == *"-mi"* ]]
then
        #Audubon Injection of Network Devices
        runProcess audInj  "Audubon Injection of Network Devices"
elif [[ ${args[*]} == *"-mt"* ]]
then
        #TOR Monitoring (nagios)
        runProcess monTor  "Set tor switches into monitoring mode"
elif [[ ${args[*]} == *"-Nhl"* ]]
then
        #Create new hosts list
        runProcess shitName "Create New Host List"
elif [[ ${args[*]} == *"-Rs"* ]]
then
        #Get specified rack's burnin, sku verification, and physical verification statuses
        runProcess rackStat "Rack Status"
elif [[ ${args[*]} == *"-Ps"* ]]
then
        #Get power status
        runProcess powerStatus  "Get Power Status"
elif [[ ${args[*]} == *"-Pf"* ]]
then
        #Poweroff machines
        runProcess poweroff "Power Off"
elif [[ ${args[*]} == *"-Po"* ]]
then
        #Poweron machines
        runProcess poweron "Power On"
elif [[ ${args[*]} == *"-Pr"* ]]
then
        #Reboot machines
        runProcess reboot "Reboot Host(s)"
elif [[ ${args[*]} == *"-serv"* ]]
then
        #Get host's service and it's monitor status
        runProcess loonyService "Get host's service and it's monitor status"
elif [[ ${args[*]} == *"-sm"* ]]
then
        #Neteng Switch Mapping - neteng git repo required
        runProcess switchMapping "NetEng Switch Mapping - Rack, Core Port, Core Switch"
elif [[ ${args[*]} == *"-vbond"* ]]
then
        #Verify bond status
        runProcess verifybond "Verify Bond Status"
elif [[ ${args[*]} == *"-unmon"* ]]
then
        #Unmonitor hosts
        runProcess monitor "Unmonitor Hosts"
elif [[ ${args[*]} == *"-unbond"* ]]
then
        #Unbond hosts
        runProcess swunbond "Switch-Level Unbond"
elif [[ ${args[*]} == *"-iden"* ]]
then
        #Turn on identifier lights indefinitely
        runProcess idenOff "Turn on identifier lights"
elif [[ ${args[*]} == *"-idenf"* ]]
then
        #Turn off identifier lights
        runProcess idenOn "Turn off indentifier lights indefinitely"
else
        #If nothing returned
        if [[ ${args[0]} == "--file="* ]]
        then
                theFile=${args[0]} | cut -c 7-
        fi
        echo "No arguments stated! $theFile"
fi
