# Apex / EA Javelin workaround: lokalni DNS forwarder na 127.0.0.1:53.
# Komponenty EA anticheatu (launcher i sluzba) prekladaji eaanticheat.ac.ea.com pres 127.0.0.1:53. Kdyz tam nic neposloucha,
# preklad selze a herni server klienta po 60 s odpoji s chybou (4). Tento skript kazdy dotaz beze zmeny preposle na skutecny
# DNS server aktivniho adapteru a vrati jeho odpoved. Nic nepodvrhuje, nic necachuje. Bezi, dokud okno nezavres (Ctrl+C).
# Spousteni: dvojklik na apex-dns-forwarder.cmd, nebo:  pwsh -ExecutionPolicy Bypass -File apex-dns-forwarder.ps1
param([string]$Upstream)
$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = 'Apex DNS forwarder (127.0.0.1:53) - zavrenim okna skoncis'
function Get-Upstream {
  if ($script:Upstream) { return $script:Upstream }
  $gw = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
  if ($gw) { $dns = (Get-DnsClientServerAddress -InterfaceIndex $gw.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses | Where-Object { $_ -and $_ -ne '127.0.0.1' } | Select-Object -First 1; if ($dns) { return $dns } }
  return '1.1.1.1'
}
try { $srv = New-Object Net.Sockets.UdpClient(New-Object Net.IPEndPoint([Net.IPAddress]::Loopback, 53)) } catch { Write-Host "Nelze otevrit 127.0.0.1:53 (uz tam neco posloucha?): $($_.Exception.Message)" -ForegroundColor Red; Start-Sleep 10; exit 1 }
$srv.Client.ReceiveTimeout = 1000
$up = Get-Upstream; $upEp = New-Object Net.IPEndPoint([Net.IPAddress]::Parse($up), 53); $lastCheck = Get-Date
Write-Host "Posloucham na 127.0.0.1:53, dotazy preposilam na $up. Nech okno otevrene, dokud hrajes." -ForegroundColor Green
$n = 0
while ($true) {
  if (((Get-Date) - $lastCheck).TotalSeconds -gt 60) { $lastCheck = Get-Date; $u2 = Get-Upstream; if ($u2 -ne $up) { $up = $u2; $upEp = New-Object Net.IPEndPoint([Net.IPAddress]::Parse($up), 53); Write-Host "Upstream DNS zmenen na $up" } }
  $from = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
  try { $q = $srv.Receive([ref]$from) } catch { continue }
  $n++
  $name = ''; try { $i = 12; $parts = @(); while ($q[$i] -ne 0) { $len = $q[$i]; $parts += [Text.Encoding]::ASCII.GetString($q, $i+1, $len); $i += $len + 1 }; $name = $parts -join '.' } catch {}
  $c = New-Object Net.Sockets.UdpClient; $c.Client.ReceiveTimeout = 3000
  try { $null = $c.Send($q, $q.Length, $upEp); $src = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0); $a = $c.Receive([ref]$src); $null = $srv.Send($a, $a.Length, $from); Write-Host ("{0:HH:mm:ss} #{1} {2} -> OK" -f (Get-Date), $n, $name) }
  catch { Write-Host ("{0:HH:mm:ss} #{1} {2} -> upstream {3} neodpovedel: {4}" -f (Get-Date), $n, $name, $up, $_.Exception.Message) -ForegroundColor Yellow }
  finally { $c.Close() }
}
