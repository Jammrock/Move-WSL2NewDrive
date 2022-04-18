# Move-WSL2NewDrive.ps1

<# 

This assumes that there is only a single VHDX file in the distro's BasePath.

Based on work by sonook @Giuthub

https://github.com/MicrosoftDocs/WSL/issues/412#issuecomment-828924500

#>

[CmdletBinding()]
param ()

function Add-YesNoPrompt
{
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]
        $Title,

        [Parameter()]
        [string]
        $Question,

        [Parameter()]
        [ValidateRange(0,1)]
        [int]
        $Default = 0
    )
    
    $choices  = '&Yes', '&No'

    $decision = $Host.UI.PromptForChoice($title, $question, $choices, $Default)
    if ($decision -eq 0) 
    {
        return $true
    } 
    else 
    {
        return $false
    }
}



$wsl2RegRoot = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss\"

# get the distros from the registry to save time on string parsing of wsl
$distros = Get-ChildItem $wsl2RegRoot -EA SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath } | Where-Object Version -eq 2

$locSpace = ($distros.DistributionName | ForEach-Object { $_.Length } | Measure-Object -Maximum | ForEach-Object Maximum) + 3


Write-Host -ForegroundColor Yellow "Which distro do you want to move?"

if ($distros.Count -gt 0)
{
    1..($distros.Count) | ForEach-Object {
        $tmpDistro = $distros[($_ - 1)]
        Write-Host "$_`t$(($tmpDistro.DistributionName).PadRight($locSpace))(Location: $($tmpDistro.BasePath))"
    }
}
else
{
    Write-Host "No WSL2 distros were found."
}

do
{
    try
    {
        [int]$selection = Read-Host "Chose wisely" -EA Stop
    }
    catch
    {
        Write-Warning "You have chosen poorly. The selection must be an integer, 1 thru $($distros.Count). [1]`n"
        $selection = $null
    }

    if ($selection -and ($selection -lt 1 -or $selection -gt $distros.Count))
    {
        Write-Warning "You have chosen poorly. The selection must be an integer, 1 thru $($distros.Count). [2]`n"
        $selection = $null
    }
} until ($selection)

# save the selected distro
$selDistro = $distros[$selection - 1]

do
{
    $path = Read-Host "Enter the full parent path to the new distro (the path used will be: <path you enter>\<distro-name>)"

    if (-NOT (Test-Path "$path" -IsValid))
    {
        Write-Warning "'$path' is an invalid path. Please try again."
        $path = $null
    }
} until ($path)


$destPath = "$path\$($selDistro.DistributionName)"

$title =  @"
Moving distro $($selDistro.DistributionName). Please save and close all work in WSL2 before proceeding, as a WSL shutdown is required to move a distro.

Current Path: $($selDistro.BasePath)
New Path:     $destPath


"@

$question = "Would you like to proceed (Y/n)?"

$go = Add-YesNoPrompt $title $question

if ($go)
{
    Write-Verbose "Stopping wsl."
    wsl --shutdown
    $stopTime = Get-Date

    Write-Verbose "Create the destination dir, $destPath."        
    try 
    {
        $null = mkdir "$destPath" -Force -EA Stop    
    }
    catch 
    {
        return (Write-Error "Failed to create the destination directory, $destPath`: $_" -EA Stop)
    }

    # copy the file first, not a move
    $vhdx = Get-ChildItem "$($selDistro.BasePath)" -Filter "*.vhdx"
    if ($vhdx)
    {
        Write-Verbose "Copying $($vhdx.FullName) to $destPath."    
        $null = Copy-Item "$($vhdx.FullName)" "$destPath" -Force
    }
    else
    {
        return (Write-Error "Failed to find the distro's VHDX file in $($selDistro.BasePath)" -EA Stop)
    }

    # save and update the registery
    reg.exe export "$(($selDistro.PSPath).Split(':')[-1])" "$destPath\pre-move-export.reg" /y > $null
    
    
    try 
    {
        Set-ItemProperty $selDistro.PSPath -Name BasePath -Value $destPath -EA Stop
    }
    catch
    {
        return (Write-Error "Failed to update the distro path in the registry: $_" -EA Stop)
    }

    # start the distro to make sure it works
    $cmdArgs = "/k wsl.exe -d $($selDistro.DistributionName)"
    Start-Process cmd -ArgumentList $cmdArgs

    $sw =  [system.diagnostics.stopwatch]::StartNew()

    $distroRunning = $false
    do
    {
        # wait 1 second for the state to change
        Start-Sleep 1

        # is the distro running?
        # wsl.exe output does some sort of strange encoding that pwsh doesn't like...there has to be a better way to do this
        # strip out all the zeroes
        $raw = [System.Text.Encoding]::Unicode.GetBytes((wsl -l -v)) | Where-Object { $_ -ne 0 } 
        
        # convert the result into UTF8
        $text = [System.Text.Encoding]::UTF8.GetString($raw)

        # get the index of the distro in the output + (length of the distro name)
        $tIdx = $text.IndexOf("$($selDistro.DistributionName)") + ($selDistro.DistributionName.Length)
        Write-Verbose "tIdx: $tIdx"

        # now look for the index of the next number, which will be the WSL version number
        $c = $tIdx
        $verIdx = -1
        Write-Verbose "text substring: $($text.Substring($tIdx))"
        foreach ($char in $text.Substring($tIdx).ToCharArray())
        { 
            Write-Debug "pipe: $_"
            if ($char -match "\d") 
            {
                Write-Verbose "match at: $c"
                $verIdx = $c
                break
            } 
            else
            {
                $c++
            }
        }

        Write-Verbose "verIdx: $verIdx"
        # get all the non-whitespace characters between tIdx and verIdx, join them into a word
        $status = ($text.Substring($tIdx, ($verIdx - $tIdx)).ToCharArray() | Where-Object {$_ -match "\w"}) -join ""
        Write-Verbose "status: $status"

        if ($status -eq "Running")
        {
            $distroRunning = $true
        }
    } until ($sw.Elapsed.TotalSeconds -gt 60 -or $distroRunning)

    $sw.Stop()

    if ($distroRunning -eq $false)
    {
        # write warning and do not delete anything
        Write-Warning @"
Either the distro did not start in the new location or the script couldn't determine if it did. The VHDX file in the original location has NOT been deleted, just in case.

Use "wsl -l -v" to manually check the status of the $($selDistro.DistributionName). If the status is Running, then you should be okay to manually delete the old VHDX file.

The original VHDX file is in:

$($selDistro.BasePath)

How do you know for absolute certain that it worked? 

Go to the original and new locations ($destPath) and compare the Date Modified time on the VHDX files. The time on the new file should have a recent Date Modified time. 

The old VHDX file should not have a Date Modified time much newer than around $($stopTime.ToShortDateString()) $($stopTime.ToShortTimeString())`. I recorded when the script stopped wsl, just in case.

If something really weird happened you can revert to the original location by merging $destPath\pre-move-export.reg (double-click) back into the registry. This will reset the location back to the original path.
"@
    }
    else
    {
        # compare Dat Modified (LastWriteTime) on old and new files to make sure the new file was used post-migration
        $oldTime = Get-Item "$($vhdx.FullName)" | ForEach-Object LastWriteTime
        $newTime = Get-ChildItem "$destPath" -Filter "*.vhdx" | ForEach-Object LastWriteTime

        # assuming there is just one VHDX file in the dir
        if ($newTime -gt $oldTime)
        {
            $title = @"
It's cleanup time!

The original file now appears out of date, based on the last write times of the old and new VHDX files. Which means it should be safe to delete the old VHDX file and free up some space.

Do you want to be 100% certain first!

Go to the original and new locations and compare the Date Modified time on the VHDX files. The time on the new file should have a newer Date Modified time. 

The old VHDX file should not have a Date Modified time much newer than around $($stopTime.ToShortDateString()) $($stopTime.ToLongTimeString())`. That is roughly the time when the script stopped wsl.

The original VHDX file is in:

$($selDistro.BasePath)

The new VHDX file is in:

$destPath

You can use "wsl --shutdown" followed by relaunching the WSL2 distro to force a change of the Date Modified time. The new file time should change, the old file should remain the same. 

If that's what happened then it should be safe to delete the old file.


"@
            $byebye = Add-YesNoPrompt -Title $title -Question "Remove the original file?"

            if ($byebye)
            {
                # delete the original file
                $null = $vhdx | Remove-Item -Force
            }
        }
    }
    
}
else 
{
    Write-Host "User terminated."
}