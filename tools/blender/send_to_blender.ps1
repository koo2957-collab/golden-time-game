# Send python code to the Blender MCP add-on socket on this PC (127.0.0.1:9876). ASCII only in this file.
param([string]$Code)
$c = [System.Net.Sockets.TcpClient]::new()
$c.ReceiveTimeout = 60000
$c.Connect("127.0.0.1", 9876)
$s = $c.GetStream()
$payload = @{ type = "execute_code"; params = @{ code = $Code } } | ConvertTo-Json -Depth 6 -Compress
$b = [Text.Encoding]::UTF8.GetBytes($payload)
$s.Write($b, 0, $b.Length)
$buf = New-Object byte[] 65536
$sb = [Text.StringBuilder]::new()
do {
  $n = $s.Read($buf, 0, $buf.Length)
  if ($n -gt 0) { [void]$sb.Append([Text.Encoding]::UTF8.GetString($buf, 0, $n)) }
  $txt = $sb.ToString()
  $ok = $false
  try { $null = $txt | ConvertFrom-Json; $ok = $true } catch {}
} while (-not $ok -and $n -gt 0)
$c.Close()
$txt
