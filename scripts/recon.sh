#!/usr/bin/env bash
# =============================================================================
#  recon.sh - Recon automatizado para CTF (FIAP NEXT)
#  Uso: ./recon.sh <IP|host> [diretorio_saida]
#  Fases: ping -> all ports (rápido) -> -sV -sC nas abertas -> UDP top 20
#         -> searchsploit --nmap -> enum por serviço (HTTP/SMB/FTP/SNMP/NFS)
# =============================================================================
set -uo pipefail

T="${1:-}"; OUT="${2:-recon_${1:-x}}"
[[ -z "$T" ]] && { echo "Uso: $0 <IP> [dir_saida]"; exit 1; }
mkdir -p "$OUT"; cd "$OUT" || exit 1

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; N='\033[0m'
info(){ echo -e "${B}[*]${N} $*"; }
ok(){   echo -e "${G}[+]${N} $*"; }
warn(){ echo -e "${Y}[!]${N} $*"; }
has(){  command -v "$1" >/dev/null 2>&1; }

WL_DIR="/usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt"
[[ -f "$WL_DIR" ]] || WL_DIR="/usr/share/wordlists/dirb/common.txt"
SUDO=""; [[ $EUID -ne 0 ]] && SUDO="sudo"

# ---------------------------------------------------------------- 1. host up
info "Alvo: $T  |  saída: $(pwd)"
if ping -c1 -W2 "$T" >/dev/null 2>&1; then ok "Host responde ICMP"
else warn "Sem ICMP - seguindo com -Pn (muito CTF bloqueia ping)"; fi

# ---------------------------------------------------------------- 2. all ports
info "Fase 1: todas as portas TCP (rápido)"
$SUDO nmap -Pn -p- --min-rate 5000 -T4 --open -oA 01_allports "$T" >/dev/null
PORTS=$(grep -oP '\d+/open' 01_allports.gnmap | cut -d/ -f1 | paste -sd, -)
[[ -z "$PORTS" ]] && { warn "Nenhuma porta aberta encontrada."; exit 0; }
ok "Portas abertas: $PORTS"

# ---------------------------------------------------------------- 3. detalhado
info "Fase 2: -sV -sC -O nas portas abertas"
$SUDO nmap -Pn -sV -sC -O -p "$PORTS" -oA 02_detail "$T" >/dev/null
grep -E '^[0-9]+/tcp' 02_detail.nmap | sed 's/^/    /'

info "Fase 3: NSE vuln (em background - pode demorar)"
( $SUDO nmap -Pn -sV --script vuln -p "$PORTS" -oN 03_vuln.nmap "$T" >/dev/null 2>&1 \
  && ok "03_vuln.nmap pronto" ) &

info "Fase 4: UDP top 20 (em background)"
( $SUDO nmap -Pn -sU --top-ports 20 --open -oN 04_udp.nmap "$T" >/dev/null 2>&1 \
  && ok "04_udp.nmap pronto" ) &

# ---------------------------------------------------------------- 4. CVE/exploits
if has searchsploit; then
  info "Buscando exploits públicos (searchsploit --nmap)"
  searchsploit --nmap 02_detail.xml 2>/dev/null | tee 05_searchsploit.txt | grep -v '^$' | head -40
else warn "searchsploit não instalado (apt install exploitdb)"; fi
if [[ -f ../cve_lookup.py || -f "$(dirname "$0")/cve_lookup.py" ]]; then
  CVE_PY="$(dirname "$0")/cve_lookup.py"; [[ -f ../cve_lookup.py ]] && CVE_PY=../cve_lookup.py
  info "Consulta NVD por versão (cve_lookup.py)"
  python3 "$CVE_PY" --nmap 02_detail.xml --max 5 | tee 06_nvd.txt
fi

# ---------------------------------------------------------------- 5. por serviço
open(){ echo ",$PORTS," | grep -q ",$1,"; }

# HTTP(S) - qualquer porta que o nmap marcou como http
HTTP_PORTS=$(grep -E '^[0-9]+/tcp +open +(ssl/)?https?' 02_detail.nmap | cut -d/ -f1)
for P in $HTTP_PORTS; do
  PROTO=http; grep -qE "^$P/tcp +open +(ssl/|https)" 02_detail.nmap && PROTO=https
  U="$PROTO://$T:$P"
  info "Web: $U"
  curl -skI "$U" | tee "10_headers_$P.txt" | grep -iE 'server|x-powered|set-cookie|location'
  curl -sk "$U/robots.txt" -o "11_robots_$P.txt" && grep -iE 'disallow|allow' "11_robots_$P.txt"
  has whatweb && whatweb -a 3 "$U" | tee "12_whatweb_$P.txt"
  if has feroxbuster; then
    feroxbuster -u "$U" -w "$WL_DIR" -x php,txt,html,bak,zip -k -q -n -o "13_dirs_$P.txt" >/dev/null 2>&1 &
  elif has gobuster; then
    gobuster dir -u "$U" -w "$WL_DIR" -x php,txt,html,bak,zip -k -q -o "13_dirs_$P.txt" >/dev/null 2>&1 &
  fi
done

# SMB
if open 445 || open 139; then
  info "SMB: null session / shares / users"
  has nxc && { nxc smb "$T" -u '' -p '' --shares 2>/dev/null; nxc smb "$T" -u 'guest' -p '' --shares 2>/dev/null; } | tee 20_smb_nxc.txt
  has smbclient && smbclient -L "//$T/" -N 2>/dev/null | tee 21_smbclient.txt
  has enum4linux-ng && enum4linux-ng -A "$T" -oY 22_enum4linux >/dev/null 2>&1 &
  $SUDO nmap -Pn -p445 --script smb-vuln-ms17-010,smb-protocols "$T" -oN 23_smb_vuln.nmap >/dev/null
  grep -iE 'VULNERABLE|SMBv1|dialects' -A2 23_smb_vuln.nmap
fi

# FTP
if open 21; then
  info "FTP: teste anonymous"
  if curl -s --max-time 8 "ftp://anonymous:anonymous@$T/" -o 30_ftp_ls.txt; then
    ok "FTP anônimo ACEITO:"; cat 30_ftp_ls.txt
    has wget && wget -q -m --no-passive "ftp://anonymous:anonymous@$T" -P 31_ftp_dump 2>/dev/null
  else warn "FTP anônimo negado"; fi
fi

# SNMP (UDP 161)
if has snmpwalk; then
  info "SNMP: community 'public'"
  timeout 15 snmpwalk -v2c -c public "$T" 1.3.6.1.2.1.1 2>/dev/null | tee 40_snmp.txt | head -5
fi

# NFS
if open 2049 || open 111; then
  info "NFS: exports"
  has showmount && showmount -e "$T" | tee 50_nfs.txt
fi

# LDAP / Kerberos -> provável DC
if open 88 || open 389; then
  warn "Kerberos/LDAP abertos -> provável Domain Controller"
  $SUDO nmap -Pn -p389 --script ldap-rootdse "$T" -oN 60_ldap.nmap >/dev/null
  grep -iE 'defaultNamingContext|dnsHostName' 60_ldap.nmap
fi

wait
ok "Recon finalizado. Arquivos em: $(pwd)"
ls -1
