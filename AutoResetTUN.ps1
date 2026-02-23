# 1. 唤醒网络连接文件夹 (COM 对象刷新)
$shell = New-Object -ComObject Shell.Application
$folder = $shell.Namespace(0x31)
$folder.Items() | Out-Null
Start-Sleep -Seconds 2

# 2. 初始化接口并识别网卡
$m = New-Object -ComObject HNetCfg.HNetShare
$phys = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notmatch "Mihomo|Meta|Clash|Loopback|VMware|vEthernet|Bluetooth" } | Select-Object -First 1
$tun = Get-NetAdapter | Where-Object { $_.Name -match "Mihomo|Meta|Clash" } | Select-Object -First 1

if ($phys -and $tun) {
    $physConn = $null; $tunConn = $null
    foreach ($c in $m.EnumEveryConnection) {
        $p = $m.NetConnectionProps($c)
        if ($p.Name -eq $phys.Name) { $physConn = $c }
        if ($p.Name -eq $tun.Name) { $tunConn = $c }
    }
    if ($physConn -and $tunConn) {
        # 3. 执行一次“开启-关闭”重置动作
        $physConfig = $m.INetSharingConfigurationForINetConnection($physConn)
        $tunConfig = $m.INetSharingConfigurationForINetConnection($tunConn)
        $physConfig.EnableSharing(1)
        $tunConfig.EnableSharing(0)
        Start-Sleep -Seconds 2
        $tunConfig.DisableSharing()
        $physConfig.DisableSharing()
    }
}
exit