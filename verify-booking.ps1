$ErrorActionPreference='Stop'
$projectPath=$PSScriptRoot
$edgePath='C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
# Use a free loopback port and a project-contained, dedicated browser profile.
$portProbe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$portProbe.Start();$debugPort=$portProbe.LocalEndpoint.Port;$portProbe.Stop()
$arguments=@('--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-smooth-scrolling',('--user-data-dir="'+$projectPath+'\browser-check"'),("--remote-debugging-port=$debugPort"),'--remote-debugging-address=127.0.0.1','--window-size=1440,1100','about:blank')
$browser=Start-Process -FilePath $edgePath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $projectPath 'evidence\browser-automation-output.log') -RedirectStandardError (Join-Path $projectPath 'evidence\browser-automation-error.log')
$socket=New-Object Net.WebSockets.ClientWebSocket
$script:commandId=0
function Invoke-BrowserCommand([string]$method,$parameters=@{}){
 $script:commandId++;$currentId=$script:commandId
 $json=ConvertTo-Json -InputObject @{id=$currentId;method=$method;params=$parameters} -Depth 12 -Compress
 $payload=[Text.Encoding]::UTF8.GetBytes($json)
 $socket.SendAsync([ArraySegment[byte]]::new($payload),[Net.WebSockets.WebSocketMessageType]::Text,$true,[Threading.CancellationToken]::None).GetAwaiter().GetResult()
 do{
  $buffer=New-Object byte[] 65536
  $stream=New-Object IO.MemoryStream
  do{
   $received=$socket.ReceiveAsync([ArraySegment[byte]]::new($buffer),[Threading.CancellationToken]::None).GetAwaiter().GetResult()
   $stream.Write($buffer,0,$received.Count)
  }while(-not $received.EndOfMessage)
  $message=[Text.Encoding]::UTF8.GetString($stream.ToArray()) | ConvertFrom-Json
  $stream.Dispose()
 }while($message.id -ne $currentId)
 if($message.error){throw ($message.error | ConvertTo-Json -Compress)}
 if($message.result.exceptionDetails){throw ('Browser evaluation failed: '+$message.result.exceptionDetails.exception.description)}
 return $message.result
}
function Save-BrowserScreenshot([string]$name){
 $shot=Invoke-BrowserCommand 'Page.captureScreenshot' @{format='png';captureBeyondViewport=$false}
 [IO.File]::WriteAllBytes((Join-Path $projectPath $name),[Convert]::FromBase64String($shot.data))
}
function Wait-Ready(){
 $deadline=[DateTime]::UtcNow.AddSeconds(20)
 do{
  Start-Sleep -Milliseconds 100
  $ready=Invoke-BrowserCommand 'Runtime.evaluate' @{expression="document.readyState==='complete' && Array.from(document.images).every(i=>{i.loading='eager';return i.complete&&i.naturalWidth>0})";returnByValue=$true}
 }while(-not $ready.result.value -and [DateTime]::UtcNow -lt $deadline)
 if(-not $ready.result.value){throw 'Local page or images did not finish loading'}
}
try {
 for($attempt=0;$attempt -lt 50;$attempt++){try{$targets=Invoke-RestMethod "http://localhost:$debugPort/json/list";if($targets){break}}catch{};Start-Sleep -Milliseconds 100}
 $target=$targets|Where-Object type -eq 'page'|Select-Object -First 1
 $socket.ConnectAsync([Uri]$target.webSocketDebuggerUrl,[Threading.CancellationToken]::None).GetAwaiter().GetResult()|Out-Null
 Invoke-BrowserCommand 'Page.enable'|Out-Null
 foreach($width in @(1440,390)){
  Invoke-BrowserCommand 'Emulation.setDeviceMetricsOverride' @{width=$width;height=1000;deviceScaleFactor=1;mobile=$false}|Out-Null
  Invoke-BrowserCommand 'Page.navigate' @{url='http://localhost:8083/'}|Out-Null
  Wait-Ready
  foreach($route in @('home','projects','about','contact')){
   Invoke-BrowserCommand 'Runtime.evaluate' @{expression="location.hash='$route'"}|Out-Null
   Start-Sleep -Milliseconds 100
   $result=Invoke-BrowserCommand 'Runtime.evaluate' @{expression="JSON.stringify({errors:window.__portfolioErrors,overflow:document.documentElement.scrollWidth>innerWidth,images:Array.from(document.images).filter(i=>i.offsetParent!==null).every(i=>i.complete&&i.naturalWidth>0),contact:!!document.querySelector('#open-booking')})";returnByValue=$true}
   $value=$result.result.value|ConvertFrom-Json
   if($value.errors.Count -gt 0 -or $value.overflow -or -not $value.images -or -not $value.contact){throw ('Check failed: '+$result.result.value)}
   Save-BrowserScreenshot ("evidence/publish-$width-$route.png"); if($route -eq 'contact'){Invoke-BrowserCommand 'Runtime.evaluate' @{expression="document.querySelector('#open-booking').click()"}|Out-Null; Start-Sleep -Seconds 5; $embed=Invoke-BrowserCommand 'Runtime.evaluate' @{expression="JSON.stringify({iframe:document.querySelector('#calendly-container iframe')?.src||null,status:document.querySelector('#booking-status')?.textContent||null,fallback:document.querySelector('#calendly-fallback').href})";returnByValue=$true}; $embed.result.value | Set-Content -LiteralPath (Join-Path $projectPath "evidence/calendly-$width.json"); $opened=Invoke-BrowserCommand 'Runtime.evaluate' @{expression="document.querySelector('#booking-dialog').open";returnByValue=$true}; if(-not $opened.result.value){throw 'Booking dialog did not open'}; Save-BrowserScreenshot ("evidence/booking-$width.png"); Invoke-BrowserCommand 'Runtime.evaluate' @{expression="document.querySelector('#close-booking').click()"}|Out-Null}
  }
 }
 'Desktop/mobile online-copy layouts, images, routes and contact text passed.' | Set-Content -LiteralPath (Join-Path $projectPath 'evidence/publish-results.txt')
 Write-Output 'Online-copy browser checks passed.'
}finally{$socket.Dispose();if($browser -and -not $browser.HasExited){Stop-Process -Id $browser.Id -ErrorAction SilentlyContinue}}