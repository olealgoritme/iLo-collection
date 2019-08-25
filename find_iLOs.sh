#!/bin/bash
#
# find_iLOs: Search a network for iLOs.
#

# FUNCTIONS

# Function that prints the script usage
function usage(){
    echo "Usage: $0 network_or_ip"
    echo "   Examples: $0 192.168.1.1"
    echo "             $0 192.168.1.0/24"
}

# Function that parses XML
# http://stackoverflow.com/questions/893585/how-to-parse-xml-in-bash
function parse_xml(){
    local IFS=\>
    read -d \< ENTITY CONTENT
}

# Function that validates if the argument passed is a valid IP or network
function valid_ip_or_network(){
    local  arg=$1
    local  stat=1

    # Check if it is a valid IP
    if [[ $arg =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        [[ ${BASH_REMATCH[1]} -le 255 && ${BASH_REMATCH[2]} -le 255 \
            && ${BASH_REMATCH[3]} -le 255 && ${BASH_REMATCH[4]} -le 255 ]]
        stat=$?
    # Check if it is a valid Network
    elif [[ $arg =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\/([0-9]{1,2})$ ]]; then
        [[ ${BASH_REMATCH[1]} -le 255 && ${BASH_REMATCH[2]} -le 255 \
            && ${BASH_REMATCH[3]} -le 255 && ${BASH_REMATCH[4]} -le 255 \
            && ${BASH_REMATCH[5]} -le 32 ]]
        stat=$?
    fi

    return $stat

}

# MAIN

# Check arguments
if [[ $# != 1 ]]; then
    usage
    exit 1
fi

network=$1

# Check argument is a valid IP or network
if ! valid_ip_or_network $network; then
    echo "ERROR: $network is NOT a valid IP or network"
    usage
    exit 1
fi    

# Temporary files
ILOS_IPS=`mktemp /tmp/findilos.XXXXX`
ILO_XML=`mktemp /tmp/iloxml.XXXXX`

# Get a list of IPs with the 17988 TCP port opened (iLO Virtual Media port)
# nmap options:
#    -n: Never do DNS resolution.
#    -sS: TCP SYN scans.
#    -PN: Treat all hosts as online (skip host discovery).
#    -p 17988: only scans port 17988.
#    -oG -: output scan in grepable format
nmap -n -sS -PN -p 17988 -oG - $network | grep /open/ | awk '{print $2}' > $ILOS_IPS

# Array of iLOs IPs
ips=($(<$ILOS_IPS));

# Print header
echo ""
echo "  IP Address   | iLO Type | iLO FW |   Server Model    | Server S/N "
echo "---------------|----------|--------|-------------------|------------"

for ip in "${ips[@]}"
do
    # read the xmldata from iLO
    # -m: Maximum time in seconds that you allow the whole operation to take.
    # -f: (HTTP) Fail silently (no output at all) on server errors.
    # -s: silent mode.
    curl -m 3 -f -s http://$iloip/xmldata?item=All > $ILO_XML
    
    # XML format example
    # <?xml version="1.0"?>
    # <RIMP>
    #       <SBSN>CZC7515KS6 </SBSN> 
    #       <SPN>ProLiant DL380 G5</SPN>
    #       [...]
    #       <FWRI>2.05</FWRI>
    #       <HWRI>ASIC: 7</HWRI>
    #       <SN>ILOCZC7515KS6 </SN>
    # </RIMP>
    while parse_xml; do
        if [[ $ENTITY = "SBSN" ]]; then
            sbsn=$CONTENT
        elif [[ $ENTITY = "SPN" ]]; then
            spn=$CONTENT
        elif [[ $ENTITY = "FWRI" ]]; then
            fwri=$CONTENT
        elif [[ $ENTITY = "HWRI" ]]; then
            hwri=$CONTENT
        elif [[ $ENTITY = "SN" ]]; then
            sn=$CONTENT
        fi
    done < $ILO_XML

    # iLO type:
    #   HWRI: 
    #     - TO       -> i-iLO
    #     - ASIC:  2 -> iLO-1
    #     - ASIC:  7 -> iLO-2
    #     - ASIC:  8 -> iLO-3
    #     - ASIC: 16 -> iLO-4
    case $hwri in
        "TO")
            ilotype="i-iLO"
            ;;
        "ASIC:  2")
            ilotype="iLO-1"
            ;;
        "ASIC:  7")
            ilotype="iLO-2"
            ;;
        "ASIC:  8")
            ilotype="iLO-3"
            ;;
        "ASIC: 16")
            ilotype="iLO-4"
            ;;
        *)
            ilotype="N/A"
            ;;
    esac
        
    # Print iLO data
    printf "%-15s| %-8s | %-6s | %-18s| %-10s\n" "$ip" "$ilotype" "$fwri" "$spn" "$sbsn"
    
done

# Total number of iLOs found
num_ilos=${#ips[@]}
echo "$num_ilos iLOs found on $network"

# Delete temporary files
rm -f $ILOS_IPS $ILO_XML
