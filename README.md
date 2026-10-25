**[SOLVED / WORKAROUND] Error (4) "The client is not running the anti-cheat, or has failed the anti-cheat authentication" – root cause found: Javelin resolves its backend host via 127.0.0.1:53**

**TL;DR:** On my PC the EA Javelin launcher and service only ever send their DNS lookups for `eaanticheat.ac.ea.com` to **127.0.0.1 port 53** (localhost). Nothing listens there on a normal Windows install, so the lookup fails forever, the anticheat never reaches its backend, and the game server kicks you with error (4) exactly 60 seconds after you join. Running a tiny DNS forwarder on 127.0.0.1:53 that passes queries to your real DNS server fixes it instantly. Nothing in the game or the anticheat is modified.

**Symptoms**
- Game launches, login and lobby work, Javelin service shows as running.
- Any Firing Range / match join: you sit in the match for about a minute, then get bounced to the lobby with error (4).
- Started suddenly (for me on 22 Oct right after Javelin self-updated to 1.0.16162060). Nothing else had changed on the PC.
- Second account on the same PC fails too. Reinstalling Apex, reinstalling Javelin, Steam verify, clean boot, disabling every third-party service and driver, disabling all virtual network adapters (VPN, Hamachi, Check Point) – none of it helped.

**What the packet capture showed** (pktmon + per-second socket log, Windows 11 26H2, Steam)
- `EAAntiCheat.GameServiceLauncher.exe` and `EAAntiCheat.GameService.exe` send standard A + AAAA DNS queries for `eaanticheat.ac.ea.com` **only to 127.0.0.1:53**, retrying with back-off (20 pairs in 2 minutes). Every query gets ICMP "port unreachable" because no DNS server runs on localhost. There is no fallback to the system DNS server.
- Every other EA/Respawn hostname (cdn.eaanticheat.ac.ea.com, accounts.ea.com, gateway.ea.com, *.stryder.respawn.com …) is resolved normally through the router DNS and works.
- Neither process ever connects to the backend IPs (54.155.x / 52.19.x / 52.51.x … – AWS eu-west-1).
- The game itself connects to the match server fine and is disconnected exactly 61.5 s after the first packet – the server-side authentication deadline.
- System DNS config is clean: no 127.0.0.1 anywhere, no NRPT rules, hosts file default, firewall clean. Windows itself resolves the name instantly.

**Proof / workaround**
With a 20-line PowerShell DNS forwarder listening on 127.0.0.1:53 and passing every query unchanged to my router, both EA processes got their answers within 2 seconds of starting, immediately opened TLS to `eaanticheat.ac.ea.com` (54.155.173.144:443), and the game worked normally. Without it the failure reproduces every time; with it, never. This also explains why only *some* players are affected: anyone already running a local DNS proxy (some VPN / security suites, AdGuard Home, Pi-hole-style tools) is fine.

**How to do it yourself (no admin rights needed, nothing is installed or modified)**
1. Save the script below as `apex-dns-forwarder.ps1`.
2. Right-click → "Run with PowerShell", or run `powershell -ExecutionPolicy Bypass -File apex-dns-forwarder.ps1`. A console window opens and says `Forwarding 127.0.0.1:53 -> <your DNS>`.
3. Keep the window open, launch Apex, play. Close the window when you are done.
4. Optional check that this is your problem: in PowerShell run `Get-NetUDPEndpoint -LocalPort 53` – if it prints nothing, nothing listens on port 53 (same situation as mine).

```powershell
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
```

What it does: it is a plain DNS relay. Whatever the anticheat asks on localhost is sent to the DNS server your Windows already uses and the real answer is handed back. No caching, no rewriting, no changes to Windows, the game or Javelin. If you already run a local DNS proxy (AdGuard Home, Pi-hole, Acrylic, a VPN client with DNS filtering), you do not need this – that is probably why you are not affected.

**@EA / Respawn:** the resolver inside the Javelin launcher and service uses 127.0.0.1:53 as its only DNS server instead of the system-configured one (at least on Windows 11 26H2 build 26300.9711, Javelin 1.0.16162060, Steam). Players without a local DNS proxy cannot authenticate and get error (4) after the 60-second deadline. I have full pcapng captures of both the failing and the working session and can provide them.
