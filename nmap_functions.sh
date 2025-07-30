nmap_network() {
    # Aide
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat <<EOF
Usage: scan_network <ip_range> <ports|-> [exclude_ips] [--open]

Arguments :
  ip_range     Plage IP ou CIDR. Ex: 192.168.0.0/24 ou 192.168.0.10-192.168.0.50
  ports        Ports spécifiques (80,443,22), une plage (20-1000), ou '-' pour tous les ports
  exclude_ips  (Optionnel) Liste d'IP à exclure, séparées par des virgules
  --open       (Optionnel) Afficher uniquement les ports ouverts

Exemples :
  scan_network 192.168.191.0/24 80,443
  scan_network 192.168.191.0/24 80,443 192.168.191.1
  scan_network 192.168.191.0/24 80,443 --open
  scan_network 192.168.191.0/24 - --open
  scan_network 192.168.191.0/24 20-1000 192.168.191.1,192.168.191.254 --open
EOF
        return 0
    fi

    local range="$1"
    local ports="$2"
    local exclude=""
    local open_only=""

    # Gestion des arguments
    if [[ "$3" == "--open" ]]; then
        open_only="--open"
    elif [[ -n "$3" ]]; then
        exclude="$3"
    fi
    if [[ "$4" == "--open" ]]; then
        open_only="--open"
    fi

    if [[ -z "$range" || -z "$ports" ]]; then
        echo "❌ Erreur : arguments manquants. Utilise --help pour l'aide."
        return 1
    fi

    local base="nmap"
    local hosts_file="hosts_up.txt"

    echo "[*] Scan des hôtes sur $range..."
    if [[ -n "$exclude" ]]; then
        sudo nmap -sn "$range" --exclude "$exclude" -v -oA "$base" | grep -v "\[host down\]"
    else
        sudo nmap -sn "$range" -v -oA "$base" | grep -v "\[host down\]"
    fi

    grep "Status: Up" "$base.gnmap" | awk '{print $2}' > "$hosts_file"
    echo "[+] Hôtes UP détectés :"
    cat "$hosts_file"

    echo "[*] Scan des ports spécifiés : $ports"
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
            mkdir -p "./$ip"
            echo "[+] $ip → ports ouverts : $found_ports"
            sudo nmap -p"$found_ports" -sC -sV "$ip" -oA "./$ip/nmap_$ip" -T4
        fi
    done < "$hosts_file" | tee all.nmap
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
  ports=$(sudo nmap -p- --min-rate=1000 -t4 $ip -pn | grep '^[0-9]' | cut -d '/' -f 1 | tr '\n' ',' | sed 's/,$//')
  sudo nmap -p$ports -sc -sv $ip -oa nmap_$ip -t4 -pn
}
