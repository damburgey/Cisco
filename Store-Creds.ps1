$SSHCreds = Get-Credential
$SSHCreds.UserName | Set-Content .\storeduser.txt
$SSHCreds.Password | ConvertFrom-SecureString | Set-Content .\storedpass.txt