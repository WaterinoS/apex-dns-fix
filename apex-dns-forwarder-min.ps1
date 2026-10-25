# Minimal loopback DNS forwarder for the Apex Legends / EA Javelin error (4) workaround.
# Listens on 127.0.0.1:53 and forwards every query unchanged to your real DNS server. No admin needed. Ctrl+C / close window to stop.
$gw  = Get-NetRoute -DestinationPrefix '0.0.0.0/0' | Sort-Object RouteMetric, InterfaceMetric | Select-Object -First 1
$dns = (Get-DnsClientServerAddress -InterfaceIndex $gw.ifIndex -AddressFamily IPv4).ServerAddresses | Where-Object { $_ -ne '127.0.0.1' } | Select-Object -First 1
if (-not $dns) { $dns = '1.1.1.1' }
$srv = New-Object Net.Sockets.UdpClient(New-Object Net.IPEndPoint([Net.IPAddress]::Loopback, 53))
$up  = New-Object Net.IPEndPoint([Net.IPAddress]::Parse($dns), 53)
Write-Host "Forwarding 127.0.0.1:53 -> $dns  (keep this window open while playing)"
while ($true) {
  $from = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0)
  $q = $srv.Receive([ref]$from)
  $c = New-Object Net.Sockets.UdpClient; $c.Client.ReceiveTimeout = 3000
  try { $null = $c.Send($q, $q.Length, $up); $src = New-Object Net.IPEndPoint([Net.IPAddress]::Any, 0); $a = $c.Receive([ref]$src); $null = $srv.Send($a, $a.Length, $from); Write-Host ("{0:HH:mm:ss} answered query from port {1}" -f (Get-Date), $from.Port) }
  catch { Write-Host "upstream $dns did not answer: $($_.Exception.Message)" -ForegroundColor Yellow }
  finally { $c.Close() }
}
