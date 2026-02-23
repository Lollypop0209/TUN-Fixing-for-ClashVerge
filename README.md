网卡共享重置法（针对 Windows 系统的常见 Bug）
原因：Windows 系统的网络路由转发状态可能会在开启 TUN 模式时卡死，导致流量无法正常穿透虚拟网卡，此时日志中常出现 DNS 解析错误。
操作步骤：

在 Clash Verge 中开启服务模式（Service Mode）和 TUN 模式。

进入 Windows 的“控制面板” -> “网络和 Internet” -> “网络和共享中心” -> “更改适配器设置”。

找到主物理网卡（例如 WLAN 或 以太网）或 Clash 的虚拟网卡（名称通常为 Mihomo 或 Clash TUN）。

右键点击该网卡 -> 选择“属性” -> 切换到“共享”选项卡。

勾选“允许其他网络用户通过此计算机的 Internet 连接来连接”，点击“确定”。

再次打开该网卡的“属性” -> “共享”，取消勾选刚才的选项，再次点击“确定”。
经历一次开启再关闭共享的操作后，底层路由通常会重置，TUN 模式即可恢复正常的网络连接。

参考链接：

GitHub Issue #244: Tun模式启动后无法连接外网，在适配器里勾选再取消网络共享后恢复正常

GitHub Issue #1490: 开启服务模式和TUN模式后，电脑断网


# TUN-Fixing-for-ClashVerge

---

# Clash Verge TUN 模式路由自动修复方案 (事件触发版)

### 1. 方案背景

由于 Windows 系统 ICS (Internet Connection Sharing) 服务在处理虚拟网卡时存在路由表卡死 Bug，导致开启 TUN 模式后无法联网。本方案通过**监听系统事件**，在 Mihomo 网卡上线时自动执行“开启-关闭共享”动作，强制重置路由。

### 2. 目录结构

建议将所有文件存放在：`D:\Tools\TUNfixing for ClashVerge\`

---

### 3. 文件准备

#### 文件一：`AutoResetTUN.ps1` (核心逻辑)

```powershell
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
        # 3. 执行“开启-关闭”重置动作
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

```

#### 文件二：`Silent_Fix.bat` (执行中转)

```bat
@echo off
pushd "%~dp0"
powershell.exe -Mta -ExecutionPolicy Bypass -NoProfile -File "D:\Tools\TUNfixing for ClashVerge\AutoResetTUN.ps1"
exit

```

---

### 4. 安装与部署 (管理员 PowerShell)

运行以下代码将任务绑定到“Mihomo网卡上线”事件：

```powershell
$TaskName = "AutoFixClashTUN"
$ScriptPath = "D:\Tools\TUNfixing for ClashVerge\Silent_Fix.bat"

$XmlQuery = @"
<QueryList>
  <Query Id="0" Path="Microsoft-Windows-NetworkProfile/Operational">
    <Select Path="Microsoft-Windows-NetworkProfile/Operational">
      *[System[(EventID=10000)]] and *[EventData[Data[@Name="Name"] and (Data="Mihomo")]]
    </Select>
  </Query>
</QueryList>
"@

$service = New-Object -ComObject Schedule.Service
$service.Connect()
$rootFolder = $service.GetFolder("\")
$taskDefinition = $service.NewTask(0)
$taskDefinition.Principal.RunLevel = 1 
$taskDefinition.Principal.UserId = "SYSTEM"
$taskDefinition.Principal.LogonType = 5 
$taskDefinition.Settings.AllowDemandStart = $true
$taskDefinition.Settings.DisallowStartIfOnBatteries = $false
$taskDefinition.Settings.StopIfGoingOnBatteries = $false
$taskDefinition.Triggers.Create(0).Subscription = $XmlQuery
$action = $taskDefinition.Actions.Create(0)
$action.Path = "cmd.exe"
$action.Arguments = "/c `"`"$ScriptPath`"`""
$rootFolder.RegisterTaskDefinition($TaskName, $taskDefinition, 6, $null, $null, 5)

```

---

### 5. 维护与清理

* **查看任务状态**：打开 `taskschd.msc` (任务计划程序)，查找 `AutoFixClashTUN`。
* **手动强制运行**：`schtasks /run /tn "AutoFixClashTUN"`
* **禁用自动修复**：`Disable-ScheduledTask -TaskName "AutoFixClashTUN"`
* **彻底卸载方案**：`schtasks /delete /tn "AutoFixClashTUN" /f`

---

### 6. 注意事项

1. **文件夹路径**：若移动文件夹，需先执行“卸载”命令，修改脚本中路径后再重新“部署”。
2. **系统服务**：方案依赖 `Windows Firewall` 服务，请确保该服务未被第三方卫士禁用。
3. **网卡名称**：若 Clash 核心更新导致虚拟网卡更名，需同步修改 XML 查询中的 `Data="Mihomo"` 部分。

---

