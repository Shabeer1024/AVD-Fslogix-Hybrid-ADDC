<#
.SYNOPSIS
    FSLogix Profile Auto-Grow Runbook
.DESCRIPTION
    Iterates each FSLogix VHDX on the profile share. Resizes by 5GB if
    profile is >80% full, while keeping total allocated size <=100GB cap.
.NOTES
    Runs on Hybrid Worker (sh01). Uses cached SMB credentials.
#>

param(
    [string]$SharePath        = "\\stfslogixshabeer042.file.core.windows.net\profiles",
    [int]$IncrementGB         = 5,
    [int]$CapGB               = 100,
    [int]$ThresholdPercent    = 80
)

$result = @{
    StartTime               = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    SharePath               = $SharePath
    IncrementGB             = $IncrementGB
    CapGB                   = $CapGB
    ThresholdPercent        = $ThresholdPercent
    Actions                 = @()
    Errors                  = @()
}

try {
    Import-Module Hyper-V -ErrorAction Stop
    Write-Output "Hyper-V module loaded"

    if (-not (Test-Path $SharePath)) {
        throw "Cannot access share: $SharePath"
    }
    Write-Output "Share accessible: $SharePath"

    $vhdxFiles = @(Get-ChildItem -Path $SharePath -Filter "*.vhdx" -Recurse -ErrorAction SilentlyContinue)
    Write-Output "Found $($vhdxFiles.Count) VHDX file(s)"

    if ($vhdxFiles.Count -eq 0) {
        $result.Status = "NoProfilesFound"
        $result | ConvertTo-Json -Depth 4
        return
    }

    # Calculate total logical size across all VHDXes
    $totalLogicalGB = 0.0
    foreach ($vhdx in $vhdxFiles) {
        try {
            $info = Get-VHD -Path $vhdx.FullName -ErrorAction Stop
            $totalLogicalGB += ($info.Size / 1GB)
        } catch {
            Write-Warning "Cannot read VHDX info for $($vhdx.Name): $_"
        }
    }
    $result.TotalLogicalAllocatedGB = [math]::Round($totalLogicalGB, 2)
    Write-Output "Total logical allocated: $($result.TotalLogicalAllocatedGB) GB / $CapGB GB cap"

    foreach ($vhdx in $vhdxFiles) {
        $action = @{
            Profile = $vhdx.Name
            Path    = $vhdx.FullName
        }

        try {
            $vhdInfo = Get-VHD -Path $vhdx.FullName -ErrorAction Stop
            $action.CurrentSizeGB = [math]::Round($vhdInfo.Size / 1GB, 2)

            try {
                $mounted = Mount-DiskImage -ImagePath $vhdx.FullName -Access ReadOnly -PassThru -ErrorAction Stop
                Start-Sleep 2
                $disk = $mounted | Get-Disk

                # FIXED: Find NTFS volume regardless of drive letter
                # FSLogix VHDXes don't auto-assign drive letters when mounted ReadOnly
                $vol = $disk | Get-Partition -ErrorAction SilentlyContinue |
                       Get-Volume -ErrorAction SilentlyContinue |
                       Where-Object { $_.Size -gt 0 -and ($_.FileSystem -eq 'NTFS' -or $_.FileSystemType -eq 'NTFS') } |
                       Select-Object -First 1

                if ($vol) {
                    $freePercent = [math]::Round(($vol.SizeRemaining / $vol.Size) * 100, 2)
                    $usedPercent = [math]::Round(100 - $freePercent, 2)
                    $action.UsedPercent = $usedPercent
                    $action.FreePercent = $freePercent

                    # Dismount cleanly before resize
                    Dismount-DiskImage -ImagePath $vhdx.FullName -ErrorAction SilentlyContinue | Out-Null

                    if ($usedPercent -ge $ThresholdPercent) {
                        $newSizeGB = $action.CurrentSizeGB + $IncrementGB
                        $projectedTotal = $totalLogicalGB + $IncrementGB

                        if ($projectedTotal -gt $CapGB) {
                            $action.Status = "SkippedCapReached"
                            $action.Reason = "Would exceed cap (projected $([math]::Round($projectedTotal,2)) GB > $CapGB GB)"
                            Write-Output "CAP HIT: $($vhdx.Name) - skipping"
                        } else {
                            Resize-VHD -Path $vhdx.FullName -SizeBytes ($newSizeGB * 1GB) -ErrorAction Stop
                            $action.Status = "Resized"
                            $action.NewSizeGB = $newSizeGB
                            $totalLogicalGB += $IncrementGB
                            Write-Output "RESIZED: $($vhdx.Name) from $($action.CurrentSizeGB) GB to $newSizeGB GB"
                        }
                    } else {
                        $action.Status = "Healthy"
                        Write-Output "OK: $($vhdx.Name) at $usedPercent% used (below threshold)"
                    }
                } else {
                    Dismount-DiskImage -ImagePath $vhdx.FullName -ErrorAction SilentlyContinue | Out-Null
                    $action.Status = "NoVolumeFound"
                }
            } catch {
                $action.Status = "Locked"
                $action.Reason = "$_"
                Write-Output "LOCKED: $($vhdx.Name) - user likely logged in, skipping"
                Dismount-DiskImage -ImagePath $vhdx.FullName -ErrorAction SilentlyContinue | Out-Null
            }
        } catch {
            $action.Status = "Error"
            $action.Reason = "$_"
            $result.Errors += "Error processing $($vhdx.Name): $_"
        }

        $result.Actions += $action
    }

    $result.EndTime = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $result.Status = "Completed"

} catch {
    $result.Status = "Failed"
    $result.Errors += "$_"
    Write-Error $_
}

$result | ConvertTo-Json -Depth 4
