# efi-layout.ps1
# Enumerate disks, partitions and identify EFI System Partition(s). Provide helper to mount and copy EFI.

Write-Output "[efi-layout] Listing GPT disks and partitions"
Get-Disk | Where-Object PartitionStyle -EQ 'GPT' | ForEach-Object {
    $disk = $_
    Write-Output "`nDisk $($disk.Number): $($disk.FriendlyName)`n"
    Get-Partition -DiskNumber $disk.Number | Format-Table -AutoSize
    Get-Volume -DiskNumber $disk.Number | Where-Object FileSystem -EQ 'FAT32' | Format-Table DriveLetter,FileSystemLabel,Size,SizeRemaining
}

Write-Output "[efi-layout] Current firmware BCD entries"
bcdedit /enum firmware

Write-Output "efi-layout.ps1 completed"
