function Get-RemoteRegistryKey {
     <#   
    .SYNOPSIS   
        Retrieves the value of a registry key for a local or remote computer, enabling Remote Registry service if required. Requires WMI access.
         
    .DESCRIPTION   
        Retrieves the value of a registry key for a local or remote computer, enabling Remote Registry service if required. Requires WMI access.
        
		The value to check is comma-delimited in the format of 'reghive,path,valuename'.
		Ex: 'HKLM,SOFTWARE\Microsoft\Windows NT\CurrentVersion,ProductName'
    .PARAMETER Computername
        Strings. Required. Name of the local or remote system/s.
	
	.PARAMETER RegKey
        Strings. Required. Name of the key as a string or list of strings. The value to check is comma-delimited in the format of 'reghive,path,valuename'.
		Ex: 'HKLM,SOFTWARE\Microsoft\Windows NT\CurrentVersion,ProductName'
	
	.PARAMETER ShowOnlyValid
        Switch. Output only fully valid entries (pingable, has WMI access).
	
	.PARAMETER DontEnableRemoteRegistry
		Switch. Do NOT attempt to enable the RemoteRegistry service if it's disabled.

	.PARAMETER PromptForCredentials
		Switch. Prompt for secure credentials to use.
		
	.PARAMETER Credential
		Secure credential object to use to access instead of the current user's credentials.
		
    .NOTES   
        Author: Matthew Carras
		Version: 1.11
			- Fixed Powershell compatibility lower than v3.0.
		Version: 1.1
			- Added code to get values from registry entries that are types other than REG_SZ (String) by looking up the type.
		Version: 1.0
			- Initial release.
     
    .EXAMPLE 
		Get-RemoteRegistryKey -Computername Desktop1 -RegKey 'HKLM,SOFTWARE\Microsoft\Windows NT\CurrentVersion,ProductName'
		
		Value         : Windows 7 Enterprise
		OSVersion     : 6.1.7601
		Hostname      : Desktop1
		IP            : 192.168.1.3
		Key           : HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProductName
		OSDescription : Microsoft Windows 7 Enterprise
    #>         
    [cmdletbinding()]
    Param (
		# Remote computer name to query
		[Parameter(Mandatory = $true,ValueFromPipeLine=$True,ValueFromPipeLineByPropertyName=$True)]
		[Alias("CN","__Server","IPAddress","Server")]
        [string[]] $ComputerName,
		
		[Parameter(Mandatory = $true)]
		[string[]]$RegKey, # Keys to check, comma-delimited of 'reghive,path,valuename'. Ex: 'HKLM,SOFTWARE\Microsoft\Windows NT\CurrentVersion,ProductName'
		
		# Output only fully valid entries (reachable, has WMI access). Will still show entries where the keys weren't found.
		[Parameter(Mandatory = $false)]
		[Switch] $ShowOnlyValid,
		
		# Don't attempt to remotely enable the RemoteRegistry service if it's stopped. Required for all except SLP partial keys
		[Parameter(Mandatory = $false)]
		[Switch] $DontEnableRemoteRegistry,
		
		# Prompt for credentials using Get-Credential
		[Parameter(Mandatory = $false)]
		[Switch] $PromptForCredentials,
		
		# Credential to use for all local and remote queries, if given
		[Parameter(Mandatory = $false)]
		[System.Management.Automation.PSCredential] $Credential
    )
    Begin {
        # Registry Hive definitions for GetStringValue GetStringValue($reghive, $subkey, $value)
		$REGHIVES=@{ 
			"HKCR"	= 2147483648;
			"HKCU" 	= 2147483649;
			"HKLM" 	= 2147483650;
			"HKU"	= 2147483651;
			"HKCC" 	= 2147483653;
			"HKDD"	= 2147483654
		}
		$REGHIVES.Add("HKEY_CLASSES_ROOT", 	$REGHIVES.'HKCR')
		$REGHIVES.Add("HKEY_CURRENT_USER", 	$REGHIVES.'HKCU')
		$REGHIVES.Add("HKEY_LOCAL_MACHINE", $REGHIVES.'HKLM')
		$REGHIVES.Add("HKEY_USERS", 		$REGHIVES.'HKU')
		$REGHIVES.Add("HKEY_CURRENT_CONFIG",$REGHIVES.'HKCC')
		$REGHIVES.Add("HKEY_DYN_DATA",		$REGHIVES.'HKDD')

		$ofs = '; ' # Delimiter for converting to string (in case it's needed)
		
		# IP address of local machine, used to determine whether a given hostname is the local machine
		Try {
			$sLOCALIP = [string]([System.Net.Dns]::GetHostAddresses($Env:ComputerName) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -Expand IPAddressToString)
		} Catch {
			$sLOCALIP = '127.0.0.1'
		}
    } #end begin
    Process {
		$WmiSplat = @{ ErrorAction = 'Stop' } # Given to all WMI-related commands
		
		If ( $PromptForCredentials ) {
			$Credential = Get-Credential -Message "Credentials for Get-RemoteRegistryKey"
		}
		If ( $Credential ) {
			Write-Verbose ("Using given credentials for user [{0}]" -f $Credential.Username)
			$WmiSplat.Add('Credential', $Credential)
		}
		
		$aKeys = @() # collect all the objects into one array to output at the end
        ForEach ($Computer in $ComputerName) {
			$Hostname = $Computer
			$IP = $Computer
			$bIsLocalMachine = $false
			
            Write-Verbose ("{0}: Checking network availability" -f $Computer)
            If (Test-Connection -ComputerName $Computer -Count 1 -Quiet) {
				# Get hostname
				$bHostnameOK = $true
				Try {
					$Hostname = [string]([System.Net.Dns]::GetHostByAddress($Computer).Hostname)
				} Catch {
					$bHostnameOK = $false # Try using WMI later
				}
				# Get IP address
				Try {
					$IP = [string]([System.Net.Dns]::GetHostAddresses($Computer) | Where-Object { $_.AddressFamily -eq 'InterNetwork' } | Select-Object -Expand IPAddressToString)
				} Catch {
					# do nothing
				} # end try/catch
				
				# Check to see if this is the local machine
				If ( $IP -eq $sLOCALIP -Or $Hostname.ToLower() -eq ($Env:ComputerName).ToLower() ) {
					$bIsLocalMachine = $true
					Write-Verbose ("{0}: Determined this is the local machine" -f $Computer)
				}
				
				# Start WMI block by getting OS info
                Try {
                    Write-Verbose ("{0}: Retrieving WMI OS information" -f $Computer)
                    $OS = Get-WmiObject -ComputerName $Computer Win32_OperatingSystem @WmiSplat
					
					# If we don't have a hostname, try using WMI to get the hostname
					if ( -Not $bHostnameOK ) {
						Try {
							$Hostname = (Get-WmiObject -ComputerName $Computer -Class Win32_ComputerSystem -Property Name @WmiSplat).Name
						} Catch {
							Write-Verbose ("{0}: WARNING - Could not get hostname" -f $Computer)
						}
					} #end if
					
					# Query RemoteRegistry service and start it if needed
					$RevertServiceStatus = $false
					$PreviousServiceStatus = 'Stopped'
					If ( -Not $bIsLocalMachine ) {
						Write-Verbose ("{0}: Querying services for RemoteRegistry" -f $Computer)
						Try { 
							$service = Get-WmiObject -Namespace root\CIMV2 -Class Win32_Service -ComputerName $Computer -Filter "Name='RemoteRegistry' OR DisplayName='RemoteRegistry'" @WmiSplat
							$PreviousServiceStatus = [string]$service.State
							Write-Verbose ("{0}: RemoteRegistry is {1}" -f $Computer,$PreviousServiceStatus) 
							If ( -Not $DontEnableRemoteRegistry -And $PreviousServiceStatus -ne 'Running' ) {
								$result = $service.StartService()
								$RevertServiceStatus = $true
								Write-Verbose ("{0}: Enabled RemoteRegistry service" -f $Computer)
								Sleep 1
							} # end if
						} Catch {
							Write-Verbose ("{0}: WARNING - Could not get status of RemoteRegistry service" -f $Computer)
						}
					} # end if remote
					
					# Begin registry access
					if ( -Not $bIsLocalMachine ) {
						Write-Verbose ("{0}: Attempting remote registry access" -f $Computer)
					} Else {
						Write-Verbose ("{0}: Attempting local registry access" -f $Computer)
					}
					# Access registry via WMI to provide credentials, if given
					$remoteReg = Get-WmiObject -List -Namespace 'root\default' -ComputerName $Computer @WmiSplat | Where-Object {$_.Name -eq "StdRegProv"}
					# Loop all the registry keys given to check.
					foreach ($keystr in $RegKey) {
						Try {
							$keyarr = $keystr -split ",",3
							$reghivestr = $keyarr[0].ToUpper()
							$reghive = $REGHIVES.($reghivestr)
							$regpath = $keyarr[1]
							$valuename = $keyarr[2]
							$fullpath = "{0}\{1}\{2}" -f $reghivestr,$regpath,$valuename
							Write-Verbose ("{0}: Checking {1}" -f $Computer,$fullpath)
							
							# Enumerate all the names in path to find out which type of value it is (and if value name exists)
							$enumvalues = $remoteReg.EnumValues($reghive, $regpath) | Select sNames,Types
							$i = [Array]::FindIndex($enumvalues.sNames,[Predicate[String]]{param($s)$s -eq $valuename})
							if ( $i -gt 0 ) {
								Switch ( $enumvalues.Types[$i] ) {
									2 { $value = ($remoteReg.GetExpandedStringValue($reghive, $regpath, $valuename)).sValue }
									3 { $value = ($remoteReg.GetBinaryValue($reghive, $regpath, $valuename)).uValue }
									4 { $value = ($remoteReg.GetDWORDValue($reghive, $regpath, $valuename)).uValue }
									7 { $value = ($remoteReg.GetMultiStringValue($reghive, $regpath, $valuename)).sValue }
									11 { $value = ($remoteReg.GetQWORDValue($reghive, $regpath, $valuename)).uValue }
									default { $value = ($remoteReg.GetStringValue($reghive, $regpath, $valuename)).sValue }
								} #end switch
							} else {
								value = "ERROR: Value name [$($valuename)] not found"
							}
							# Collect value
							$aKeys += New-Object PSObject -Property @{
								Hostname = $Hostname
								IP = $IP
								Key = $fullpath
								Value = [string]$value
								OSVersion = $os.version
								OSDescription = $os.caption
							}
						} Catch {
							Write-Verbose ("{0}: WARNING - Registry entry for [{1}] does not seem to exist. Exception (if any): " -f $Computer,$keystr,$_.Exception.Message)
							
							$aKeys += New-Object PSObject -Property @{
								Hostname = $Hostname
								IP = $IP
								Key = $keystr
								Value = 'ERROR: Key or value not found'
								OSVersion = $os.version
								OSDescription = $os.caption
							}
						} # end try/catch
					} #end foreach
					
					# Set service status back to its original state
					If ( $RevertServiceStatus ) {
						Try {
							$service = Get-WmiObject -Namespace root\CIMV2 -Class Win32_Service -ComputerName $Computer -Filter "Name='RemoteRegistry' OR DisplayName='RemoteRegistry'" @WmiSplat
							If ( $PreviousServiceStatus -eq 'Stopped' ) {
								$result = $service.StopService()
								Write-Verbose ("{0}: RemoteRegistry set back to {1}" -f $Computer,$PreviousServiceStatus)
							}
						} Catch {
							Write-Verbose ("{0}: WARNING - Could NOT restore RemoteRegistry back to {1} - {2}" -f $Computer,$PreviousServiceStatus,$_.Exception.Message)
						} # end try/catch
					} #end if we need to revert service status
                } Catch { # no WMI access
					Write-Verbose ("{0}: WARNING - Could not query WMI" -f $Computer)
					if ( -Not $ShowOnlyValid ) {
						$aKeys += New-Object PSObject -Property @{
							Hostname = $Hostname
							IP = $IP
							Key = 'ERROR: No WMI access'
							Value = $_.Exception.Message
							OSVersion = $_.Exception.Message
							OSDescription = $_.Exception.Message
						}
					} # end if
                } #end try/catch
            } ElseIf ( -Not $ShowOnlyValid ) {
                $aKeys += New-Object PSObject -Property ]@{
                    Hostname = $Computer
					IP = $Computer
                    Key = 'Unreachable'
					Value = 'Unreachable'
					OSVersion = 'Unreachable'
					OSDescription = 'Unreachable'
                } #end if
            } Else {
				Write-Verbose("{0}: WARNING - Unreachable, skipping" -f $Computer)
			} # end if computer is reachable or not
        } # end foreach
		
		# Finally, loop over all the keys we've collected, displaying them
		foreach ( $obj in $aKeys ) {
			$obj
		} # end foreach
    } # end process
} # end function 