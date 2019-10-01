[CmdletBinding()]
Param(
  [Parameter(Position=0,Mandatory=$false,
    HelpMessage='Location of Logs Folder')]
    [alias("LP","Logs")][String]$LogPath = '.\Logs\',
  
  [Parameter(Position=1,Mandatory=$false,
    HelpMessage='IP Address or Resolvable Hostname of Seed Switch A')]
    [alias("A","FabA")][String]$SwitchA = "10.16.30.82",
  
  [Parameter(Position=2,Mandatory=$false,
    HelpMessage='IP Address or Resolvable Hostname of Seed Switch B')]
    [alias("B","FabB")][String]$SwitchB = "10.16.30.83",

  [Parameter(Position=3,Mandatory=$false,
    HelpMessage='Location of the Cisco Crendential Username')]
    [alias("User","Username")][String]$UserFile = '.\user.cred',

  [Parameter(Position=4,Mandatory=$false,
    HelpMessage='Location of the Cisco Crendential Password')]
    [alias("Pass","Password")][String]$PassFile = '.\pass.cred'
)

# Internal Functions

Function Parse-Zones ([array]$zones) {
  # Build a PSObject that extracts the zoneset, the underlying zones, and stores the relationships
  $fabobjects = @()
  $zoneset = $null
  $vsan = $null

  foreach ($str in $zones) {

    # Look for a zoneset line
    if ($str -Match ".*zoneset\s.*") {
      $split = $str.Trim().Split(" ")
      $zoneset = $split[2]
      $vsan = $split[4]

      # Look for a zone line
    } elseif ($str -Match ".*zone\s.*") {
      $split = $str.Trim().Split(" ")[2].Split("_")
      $fabobjects += [PSCustomObject]@{
        Hostname = $split[0];
        Hba      = $split[1];
        Array    = $split[2];
        Port     = $split[3];
        Zoneset  = $zoneset;
        Vsan     = $vsan;
      }
    }
  }
  Return $fabobjects
}

# Get Script Started Time
$StartedTime = $([datetime]::Now)

# Script Version
$ScriptVer = "v0.1b"

# Get the DOMAIN\Username of the script user
$ScriptUser = $(whoami)

# Check to see if the Log Directory exists, if not, create it, or exit upon failure.
    If (!(Test-Path $LogPath)){
        Write-Host "$LogPath doesnt exist, creating it. $([datetime]::Now)"
        New-Item -Path $LogPath -ItemType Directory | Out-Null
        If (!(Test-Path $LogPath)){
            Write-Host "$LogPath creation failed, exiting... $([datetime]::Now)"
            exit
        }
        else {Write-Host "$LogPath was created successfully, proceeding... $([datetime]::Now)"}
    }
    else {Write-Host "$LogPath exists, proceeding... $([datetime]::Now)"}

# Get the time stamp for the output log
$LogTime = $(Get-Date -Format MMddyyy_HHmmss)

# Set the global logfile variable
$global:LogFile = $LogPath+$LogTime+"_Get-CiscoZones.log"

# Set the global tmpfile variable
$global:tmpFile = $LogPath+$LogTime+"_Get-CiscoZones-Metadata.txt"

#Supress Error Notifications
$ErrorActionPreference = "SilentlyContinue"

# Check to see if the Cisco stored credentials exist, if not, prompt for new credentials
    If (!(Test-Path $UserFile)){
        Write-Host "$UserFile doesnt exist, prompting for credentials. $([datetime]::Now)"
        $SSHCreds = Get-Credential
        $SSHCreds.UserName | Set-Content $UserFile
        $SSHCreds.Password | ConvertFrom-SecureString | Set-Content $PassFile 
        
        If (!(Test-Path $UserFile)){
            Write-Host "Credential creation failed, exiting... $([datetime]::Now)"
            exit
        }
        else {Write-Host "Credentials were stored successfully, proceeding... $([datetime]::Now)"}
    }
    else {Write-Host "$UserFile found, proceeding with stored credentials... $([datetime]::Now)"}

# After Credentials are Stored
$Username = Get-Content $UserFile
$Password = Get-Content $PassFile | ConvertTo-SecureString
$SSHCreds = New-Object System.Management.Automation.PSCredential ($Username, $Password)

# Touch the LogFile and add the Forsythe Engineering Header
"" | Out-File $global:LogFile -Append
Add-Content $global:LogFile ""
Add-Content $global:LogFile "  ______                   _   _                          "
Add-Content $global:LogFile " |  ____|                 | | | |                         "
Add-Content $global:LogFile " | |__ ___  _ __ ___ _   _| |_| |__   ___                 "
Add-Content $global:LogFile " |  __/ _ \| '__/ __| | | | __| '_ \ / _ \                "
Add-Content $global:LogFile " | | | (_) | |  \__ \ |_| | |_| | | |  __/                "
Add-Content $global:LogFile " |_|  \___/|_|  |___/\__, |\__|_| |_|\___|                "
Add-Content $global:LogFile "                      __/ |                               "
Add-Content $global:LogFile "  ______             |___/                  _             "
Add-Content $global:LogFile " |  ____|           (_)                    (_)            "
Add-Content $global:LogFile " | |__   _ __   __ _ _ _ __   ___  ___ _ __ _ _ __   __ _ "
Add-Content $global:LogFile " |  __| | '_ \ / _`  | | '_ \ / _ \/ _ \ '__| | '_ \ / _`  |"
Add-Content $global:LogFile " | |____| | | | (_| | | | | |  __/  __/ |  | | | | | (_| |"
Add-Content $global:LogFile " |______|_| |_|\__, |_|_| |_|\___|\___|_|  |_|_| |_|\__, |"
Add-Content $global:LogFile "                __/ |                                __/ |"
Add-Content $global:LogFile "               |___/                                |___/ "
Add-Content $global:LogFile ""
Add-Content $global:LogFile "----------------------------------------------------------"
Add-Content $global:LogFile " Cisco Zoning Analysis Report $ScriptVer "
Add-Content $global:LogFile " Ran on $DisplayDate by $ScriptUser "
Add-Content $global:LogFile "----------------------------------------------------------"
Add-Content $global:LogFile ""


##################
### Do Fabric A
##################

# Create Fabric A SSH Session
Write-Host -ForegroundColor Green "Establishing SSH Connection to $SwitchA as $Username"
$ssh = New-SSHSession -ComputerName $SwitchA -Credential $SSHCreds 

# Grab the switchname for Fabric A
Write-Host -ForegroundColor Green "Retreiving the switchame from $SwitchA"
$FabASwitchName = (Invoke-SSHCommand -Index 0 -Command "show running-config | grep switchname").Output

# Grab the active zones in the zoneset
Write-Host -ForegroundColor Green "Retreiving the active zoneset information from $FabASwitchName at $SwitchA"
$fabazones = (Invoke-SSHCommand -Index 0 -Command "show zoneset active | grep zone").output

# Parse all of the zonesets and zones on Fabric A
Write-Host -ForegroundColor Green "Parsing the active zoneset information from $FabASwitchName at $SwitchA"
$fabaobjects = Parse-Zones $fabazones

# Identify the number of unique Hostnames on Fabric A
Write-Host -ForegroundColor Green "Identifying the Unique Hostnames on $FabASwitchName at $SwitchA"
$uniquefaba = $fabaobjects.Hostname | Sort -Unique

##################
### Do Fabric B
##################

# Create Fabric B SSH Session
Write-Host -ForegroundColor Green "Establishing SSH Connection to $SwitchB as $Username"
$ssh = New-SSHSession -ComputerName $SwitchB -Credential $SSHCreds 

# Grab the switchname for Fabric B
Write-Host -ForegroundColor Green "Retreiving the switchame from $SwitchB"
$FabBSwitchName = (Invoke-SSHCommand -Index 1 -Command "show running-config | grep switchname").Output

# Grab the active zones in the zoneset
Write-Host -ForegroundColor Green "Pulling the active zoneset information from $FabBSwitchName at $SwitchB"
$fabbzones = (Invoke-SSHCommand -Index 1 -Command "show zoneset active | grep zone").output

# Parse all of the zonesets and zones on Fabric B
Write-Host -ForegroundColor Green "Parsing the active zoneset information from $FabBSwitchName at $SwitchB"
$fabbobjects = Parse-Zones $fabbzones

# Identify the number of unique Hostnames on Fabric B
Write-Host -ForegroundColor Green "Identifying the Unique Hostnames on $FabBSwitchName at $SwitchB"
$uniquefabb = $fabbobjects.Hostname | Sort -Unique

##################
### Merge & Sort
##################

# Merge Fabric A and Fabric B Objects in to one Master Object
$AllHosts = $fabaobjects + $fabbobjects

# Find all the unique Storage Arrays that were discovered
$Arrays = $AllHosts | Sort -Property Array -Unique

##################
### Count Stuff
##################

# Display Temp Outputs
Write-Host -ForegroundColor Green $fabaobjects.Count "Active Zones on $FabASwitchName at $SwitchA"
Write-Host -ForegroundColor Green $uniquefaba.Count "Unique Hosts discovered on $FabASwitchName at $SwitchA"
Write-Host -ForegroundColor Green $fabbobjects.Count "Active Zones on $FabBSwitchName at $SwitchB"
Write-Host -ForegroundColor Green $uniquefabb.Count "Unique Hosts discovered on $FabBSwitchName at $SwitchB"
Write-Host -ForegroundColor Green $AllHosts.Count "Total Zones to be analzyed"
Write-Host -ForegroundColor Green $Arrays.Count "Total Arrays to be analzyed"

##################
### Report Stuff
##################

# Find Hosts with an ODD number of zones across both fabrics
$SingleZonedHosts = ($AllHosts | Group -Property Hostname | ?{$_.Count -eq 1}) | Sort
$TripleZonedHosts = ($AllHosts | Group -Property Hostname | ?{$_.Count -eq 3}) | Sort
$PentaZonedHosts = ($AllHosts | Group  -Property Hostname | ?{$_.Count -eq 5}) | Sort
    Write-Host -ForegroundColor Green "The Following Hostnames appear to only have a single zone"
    $SingleZonedHosts.Group | Format-Table 
    Write-Host -ForegroundColor Green "The Following Hostnames appear to have 3 zones"
    $TripleZonedHosts.Group | Format-Table 
    Write-Host -ForegroundColor Green "The Following Hostnames appear to have 5 zones"
    $PentaZonedHosts.Group | Format-Table 

# Messing Around with listing all connections on a per array basis to the tmpFile output
foreach ($Array in $Arrays){
Write-Host -ForegroundColor Green "Parsing Host Connections to $($Array.Array)" >> $global:tmpFile
$AllHosts | ?{$_.Array -eq $Array.Array} | Sort -Property Hostname,HBA,Zoneset | Format-Table >> $global:tmpFile
}

# Identify Hosts with less than two known zones to a specific array
$UniqueHostArrayPair = $AllHosts | Sort-Object -Property Hostname,Array,Zoneset -Unique | Group -Property Hostname,Array | ?{$_.Count -lt 2}
Write-Host -ForegroundColor Green "The followings hosts have less than two connections to a specific array"
$UniqueHostArrayPair

##################
### All Done
##################

# Disconnect all SSH Sessions
Write-Host -ForegroundColor Green "Disconnecting SSH sessions on $FabASwitchName and $FabBSwitchName"
Get-SSHSession | Remove-SSHSession | Out-Null

#Caculate and print script execution time
$EndedTime = $([datetime]::Now)
#$TimeElapsed = [math]::Round([decimal] ($EndedTime - $StartedTime).TotalSeconds, $Precision)
$TimeElapsed = $EndedTime - $StartedTime
Write-Host -ForegroundColor Green "Script Execution Time $TimeElapsed"