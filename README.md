# Get-RemoteRegistryKey
Powershell cmdlet which retrieves the value of a registry key for a local or remote computer, enabling Remote Registry service if required. Requires WMI access.

The value to check is comma-delimited in the format of 'reghive,path,valuename'. Ex: 'HKLM,SOFTWARE\Microsoft\Windows NT\CurrentVersion,ProductName'  

**.PARAMETER Computername**  
   Strings. Required. Name of the local or remote system/s. You may give multiple computernames.

**.PARAMETER RegKey**
   Strings. Required. Name of the key as a string or list of strings. The value to check is comma-delimited in the format of 'reghive,path,valuename'. Ex: 'HKLM,SOFTWARE\Microsoft\Windows NT\CurrentVersion,ProductName'  
   
**.PARAMETER ShowOnlyValid**  
   Switch. Output only fully valid entries (pingable, has WMI access). Will still show when the key is missing.  

**.PARAMETER DontEnableRemoteRegistry**  
  Switch. Do NOT attempt to enable the RemoteRegistry service if it's disabled.  

**.PARAMETER PromptForCredentials**  
  Switch. Prompt for secure credentials to use.  

**.PARAMETER Credential**  
  Secure credential object to use instead of the current user's credentials.  

**.EXAMPLE**  
		PS> Get-RemoteRegistryKey -Computername Desktop1 -RegKey 'HKLM,SOFTWARE\Microsoft\Windows NT\CurrentVersion,ProductName'
		
		Value         : Windows 7 Enterprise  
		OSVersion     : 6.1.7601  
		Hostname      : Desktop1  
		IP            : 192.168.1.3  
		Key           : HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProductName  
		OSDescription : Microsoft Windows 7 Enterprise  
