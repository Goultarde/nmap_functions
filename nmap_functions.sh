nmap_network() {
    # Help
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<EOF
Usage: nmap_network <ip_range|-s|--skip-discovery> [options]

Arguments:
  ip_range                 IP range or CIDR. Ex: 192.168.0.0/24 or 192.168.0.10-192.168.0.50

Options:
  -s, --skip-discovery     Skip host discovery. Any standalone IPs will be force scanned.
  -p, --ports <ports>           Specific ports (80,443,22) or range (20-1000). Default: all ports
  -e, --exclude <ips>           List of IPs to exclude, comma-separated
  -E, --exclude-file <file>     File containing IPs to exclude (one per line)
  -f, --force-ips <ips>         IPs to scan even if they appear down, comma-separated
  -F, --force-ips-file <file>   File containing IPs to force scan (one per line)
  -i, --ip-file <file>          File containing IPs to scan (one per line)
  -a, --all                     Show all ports (open AND closed). Default: open ports only

Examples:
  nmap_network 192.168.191.0/24                                    # Scan all open ports
  nmap_network 192.168.191.0/24 -p 80,443                         # Specific open ports
  nmap_network 192.168.191.0/24 -a                                # All ports (open + closed)
  nmap_network 192.168.191.0/24 -e 192.168.191.1                  # Exclude an IP
  nmap_network 192.168.191.0/24 -E exclude_list.txt               # Exclude IPs from file
  nmap_network 192.168.191.0/24 -f 192.168.191.50,192.168.191.100 # Force IPs
  nmap_network 192.168.191.0/24 -F force_list.txt                 # Force IPs from file
  nmap_network -s 192.168.1.10                                    # Skip discovery, scan single IP
  nmap_network -p 22,3389 -s 192.168.1.10                        # IP can be anywhere
  nmap_network 192.168.1.10 192.168.1.20 -s -p 80               # Multiple IPs anywhere
  nmap_network -s -i my_ips.txt                                   # IP file (skip discovery)
  nmap_network --skip-discovery -F force_list.txt                 # Force IPs without discovery
EOF
        return 0
    fi

    local range=""
    local ports="-"  # Default: all ports
    local exclude=""
    local exclude_file=""
    local open_only="--open"  # Default: open ports only
    local force_ips=""
    local force_file=""
    local ip_file=""
    local skip_discovery=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--ports)
                ports="$2"
                shift 2
                ;;
            -e|--exclude)
                exclude="$2"
                shift 2
                ;;
            -E|--exclude-file)
                exclude_file="$2"
                shift 2
                ;;
            -f|--force-ips)
                force_ips="$2"
                shift 2
                ;;
            -F|--force-ips-file)
                force_file="$2"
                shift 2
                ;;
            -i|--ip-file)
                ip_file="$2"
                shift 2
                ;;
            -a|--all)
                open_only=""  # Show all ports
                shift
                ;;
            -s|--skip-discovery)
                skip_discovery=true
                shift
                ;;
            --open)
                # Compatibility: --open remains to force behavior (already default)
                open_only="--open"
                shift
                ;;
            *)
                # If skip-discovery mode and it's not an option, add to force_ips
                if [[ "$skip_discovery" == true && "$1" != "-"* ]]; then
                    if [[ -n "$force_ips" ]]; then
                        force_ips="$force_ips,$1"
                    else
                        force_ips="$1"
                    fi
                # If no range set yet and it's not an option, it's the range
                elif [[ "$1" != "-"* && -z "$range" ]]; then
                    range="$1"
                # Legacy syntax compatibility: if 2nd arg without --, it's ports
                elif [[ "$1" != "-"* && -z "$exclude" && "$ports" == "-" ]]; then
                    ports="$1"
                # Otherwise, it's an IP to exclude (compatibility)
                elif [[ "$1" != "-"* && -z "$exclude" ]]; then
                    exclude="$1"
                fi
                shift
                ;;
        esac
    done

    # Validate arguments
    if [[ "$skip_discovery" == true ]]; then
        if [[ -z "$force_ips" && -z "$force_file" && -z "$ip_file" ]]; then
            echo "[-] Error: --skip-discovery requires --force-ips, --force-ips-file, or --ip-file"
            return 1
        fi
    else
        if [[ -z "$range" ]]; then
            echo "[-] Error: missing ip_range argument. Use --help for help."
            return 1
        fi
    fi

    # Process exclude file and combine with exclude list
    if [[ -n "$exclude_file" ]]; then
        if [[ ! -f "$exclude_file" ]]; then
            echo "[-] Error: exclude file $exclude_file not found"
            return 1
        fi
        echo "[*] Loading exclude list from: $exclude_file"
        file_excludes=$(cat "$exclude_file" | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$exclude" ]]; then
            exclude="$exclude,$file_excludes"
        else
            exclude="$file_excludes"
        fi
        echo "[*] Total IPs to exclude: $(echo "$exclude" | tr ',' '\n' | wc -l)"
    fi

    # Process force file and combine with force IPs list
    if [[ -n "$force_file" ]]; then
        if [[ ! -f "$force_file" ]]; then
            echo "[-] Error: force file $force_file not found"
            return 1
        fi
        echo "[*] Loading force IPs list from: $force_file"
        file_force_ips=$(cat "$force_file" | tr '\n' ',' | sed 's/,$//')
        if [[ -n "$force_ips" ]]; then
            force_ips="$force_ips,$file_force_ips"
        else
            force_ips="$file_force_ips"
        fi
        echo "[*] Total IPs to force scan: $(echo "$force_ips" | tr ',' '\n' | wc -l)"
    fi

    # Generate filenames based on network/mode
    local network_name=""
    if [[ "$skip_discovery" == true ]]; then
        network_name="skip_discovery"
    else
        # Convert network range to filename-safe format
        network_name=$(echo "$range" | sed 's/[\/:]/_/g' | sed 's/\./_/g')
    fi
    
    local hosts_scan="nmap_hosts_$network_name"
    local hosts_file="hosts_up_$network_name.txt"
    local all_results="all_$network_name.nmap"

    # Create nmap directory if it doesn't exist
    mkdir -p nmap

    # Handle different discovery modes
    if [[ "$skip_discovery" == true ]]; then
        echo "[*] Skip-discovery mode enabled - no host discovery"
        
        # Use provided IP file
        if [[ -n "$ip_file" ]]; then
            if [[ ! -f "$ip_file" ]]; then
                echo "[-] Error: file $ip_file not found"
                return 1
            fi
            echo "[*] Using IP file: $ip_file"
            cp "$ip_file" "nmap/$hosts_file"
        fi
        
        # Add forced IPs
        if [[ -n "$force_ips" ]]; then
            echo "[*] Adding forced IPs: $force_ips"
            echo "$force_ips" | tr ',' '\n' >> "nmap/$hosts_file"
        fi
        
        # Create empty nmap_hosts file for consistency
        echo "# Skip discovery mode - no host discovery performed" > "nmap/$hosts_scan"
        
    else
        echo "[*] Scanning hosts on $range..."
        if [[ -n "$exclude" ]]; then
            sudo nmap -sn "$range" --exclude "$exclude" -v -oG "nmap/$hosts_scan" | grep -v "\[host down\]"
        else
            sudo nmap -sn "$range" -v -oG "nmap/$hosts_scan" | grep -v "\[host down\]"
        fi

        grep "Status: Up" "nmap/$hosts_scan" | awk '{print $2}' > "nmap/$hosts_file"
        
        # Add forced IPs even if they appear down
        if [[ -n "$force_ips" ]]; then
            echo "[*] Adding forced IPs: $force_ips"
            echo "$force_ips" | tr ',' '\n' >> "nmap/$hosts_file"
        fi
    fi

    # Remove duplicates and empty lines
    sort -u "nmap/$hosts_file" | grep -v '^$' > "nmap/${hosts_file}.tmp" && mv "nmap/${hosts_file}.tmp" "nmap/$hosts_file"
    
    echo "[+] Hosts to scan:"
    cat "nmap/$hosts_file"

    echo "[*] Scanning specified ports: $ports"
    while IFS= read -r ip; do
        ip=$(echo "$ip" | tr -d '\r')
        if [[ "$ports" == "-" ]]; then
            ports="-"
        fi

        if [[ "$open_only" == "--open" ]]; then
            found_ports=$(sudo nmap -p"$ports" --open --min-rate=1000 -T4 "$ip" \
                | grep -E '^[0-9]+/tcp\s+open' | cut -d '/' -f 1 | tr '\n' ',' | sed 's/,$//')
        else
            found_ports=$(sudo nmap -p"$ports" --min-rate=1000 -T4 "$ip" \
                | grep '^[0-9]' | cut -d '/' -f 1 | tr '\n' ',' | sed 's/,$//')
        fi

        if [[ -n "$found_ports" ]]; then
            echo "[+] $ip → open ports: $found_ports"
            sudo nmap -p"$found_ports" -sC -sV "$ip" -oA "nmap/nmap_$ip" -T4
        fi
    done < "nmap/$hosts_file" | tee "nmap/$all_results"
}


nmapfull() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Usage: nmapfull <ip>"
    echo "Performs a full TCP port scan, then a service and script scan on the discovered ports."
    echo "Output is saved as nmap_<ip>.* files."
    return 0
  fi

  if [ -z "$1" ]; then
    echo "Usage: nmapfull <ip>"
    return 1
  fi

  ip=$1
  ports=$(sudo nmap -p- --min-rate=1000 -T4 $ip -Pn | grep '^[0-9]' | cut -d '/' -f 1 | tr '\n' ',' | sed 's/,$//')
  sudo nmap -p$ports -sC -sV $ip -oA nmap_$ip -T4 -Pn
}

nmapfullvuln() {
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        echo "Usage: nmapfullvuln <ip>"
        echo "Performs a full TCP port scan, then runs vulnerability scripts on discovered ports."
        echo "Output is saved as nmap_<ip>.* files."
        return 0
    fi

    if [ -z "$1" ]; then
        echo "Usage: nmapfullvuln <ip>"
        return 1
    fi

    ip=$1
    ports=$(sudo nmap -p- --min-rate=1000 -T4 $ip -Pn | grep '^[0-9]' | cut -d '/' -f 1 | tr '\n' ',' | sed 's/,$//')
    sudo nmap -p$ports --script "vuln" -sV $ip -oA nmap_$ip -T4 -Pn
}
