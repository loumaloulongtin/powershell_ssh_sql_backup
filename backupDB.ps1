###############################################################################################################################################################
# Author : Lou-Malou Longtin																      # 
#	https://github.com/loumaloulongtin/														      # 
#                                                                                                 							      #
# Date : 07/27/2017																	      #
#																			      #
# Required modules : Posh-SSH															              #	
#   Find-Module Posh-SSH | Install-Module														      #	
#  OR																                              #
#   iex (New-Object Net.WebClient).DownloadString("https://gist.github.com/darkoperator/6152630/raw/c67de4f7cd780ba367cccbc2593f38d18ce6df89/instposhsshdev") #
# 																			      #
# Description : This script is used to backup a single database. It is designed to have a 5 days retention. The backups are ran hourly. Only the last backup  #
# of the last 4 preceding days are kept. All backups of the current day are kept until the next one.                                                          #
#      								                                                                                              #
# The script takes care of determining if it is already running or not. It uses SSH and the mysqldump command to execute the backup. Then fetch it using scp. #
# As it is being done hourly on the production server, it also checks the current server load and delay the backup if it is too heavy.			      #
# Backup files are deleted from the remote server after the transfer has been completed.							              #
#											                                                                      #                  
#                                                                                           #
###############################################################################################################################################################

\Import-Module "C:\ajdb\alreadyRunning.psm1"

$ScriptName = $MyInvocation.MyCommand.Name
Test-IfAlreadyRunning -ScriptName $ScriptName

# SSH/SFTP credentials
# Replace {password} with your SSH password,
# Replace {user} with your SSH username,
# Replace {exmaple.com} with the hostname or IP address of the remote server
$secpasswd = ConvertTo-SecureString "{password}" -AsPlainText -Force
$creds = New-Object System.Management.Automation.PSCredential ("{user}", $secpasswd)
$remote_host = "{example.com}"

# Database credentials
# Replace {password} with your DB password
# Replace {user} with your DB username
# Replace {dbname} with your DB name
$dbUser = '{user}'
$dbPass = '{password}'
$dbName = '{dbname}'

#Notifications
#Replace {email} with your email address
$email = '{email}'

#Paths / File names - LOCAL&&REMOTE
$localFolderPath = "D:\path\to\backup" # Local folder to save backup files
$folderName = Get-Date -format ddMMyy # How the folders are named (1 folder / day of retention)
$fileName = "$(Get-Date -format ddMMyy-HHmmss).sql.gz" # Name of the backup files
$logsPath = "D:\path\to\log\folder" #Path to log folder
$remoteSavePath = '/path/to/save/temp/sql/file' #Remote path to dump sql database temporarily

#Logging
$logFile = "$(Get-Date -format dd-MM-yy).log"
if (!(Test-Path "$logsPath\$logFile"))
{
	New-Item -path "$logsPath\" -name $logFile -type "file"
}
$logFile = "$logsPath\$logFile"


#Cleaning up
Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Cleaning local folders."
$localFolder = get-childitem -Path $localFolderPath -Recurse | where-object { $_.PSIsContainer }

#Folders cleanup
while($localFolder.Count -gt 5) { 
	$ItemName = $localFolder | Sort CreationTime | select -First 1 #Select oldest folder
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Folders cleanup - Deleting folder : $ItemName"
	$ItemName | Remove-Item -Recurse #Delete folder
	$localFolder = get-childitem -Path $localFolderPath -Recurse | where-object { $_.PSIsContainer } #Updating backup folders childs
}

#Files cleanup
$count = $localFolder.Count-1
for($i =0; $i -lt $localFolder.Count-1; $i++){ # Count-1 -> We do not cleanup current day's folder.
	$item = $localFolder | Sort CreationTime | Select-Object -Skip $i | Select-Object -First 1
	while((get-childitem -Path "$localFolderPath\$item\").Count -gt 1) {
		$ItemName = get-childitem -Path "$localFolderPath\$item\" | Sort CreationTime | select -First 1
		Write-Host $ItemName
		Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Files cleanup - Deleting file : $ItemName"
		$ItemName | Remove-Item -Recurse
	}
}
#Creating a folder for current day (If it doesn't already exists)
if(!(test-path "$localFolderPath\$folderName")){
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - New day - Creating folder : $localFolderPath\$folderName."
	New-Item -ItemType Directory -Force -Path "$localFolderPath\$folderName"
}


 
#Create SSH Session
$ssh = New-SSHSession -ComputerName $remote_host -Credential $creds -AcceptKey:$true


#Workload
$workload = $(Invoke-SSHCommand -SSHSession $ssh -Command "uptime | awk '{print `$10'}").Output
if($workload.split('.')[0] -eq "average:"){
	$workload = $(Invoke-SSHCommand -SSHSession $ssh -Command "uptime | awk '{print `$11'}").Output
}
while([int]$workload.split('.')[0] -gt 3){
#Notification
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Backup is late - ``date '+%m-%d-%Y %H:%M:%S'`` server load too high!`" | mail -s `"Backup DB  $dbName - Backup is late`" $email" -timeout 1200
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Rules - Server load too high"
	Start-sleep -s 600
	$workload = $(Invoke-SSHCommand -SSHSession $ssh -Command "uptime | awk '{print `$10'}").Output
}


#Are mysqldump OR gzip already running?
#Mysqldump
while($(Invoke-SSHCommand -SSHSession $ssh -Command "ps aux | grep `"[m]ysqldump`"").Output -match "mysqldump"){
#Notification
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Backup is late - ``date '+%m-%d-%Y %H:%M:%S'`` Mysqldump is already running!`" | mail -s `"Backup DB $dbName - Backup is late`" $email" -timeout 1200
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Rules - Mysqldump is already running"
	Start-Sleep -s 120
}

#Gzip
while($(Invoke-SSHCommand -SSHSession $ssh -Command "ps aux | grep `"[g]zip`"").Output -match "gzip"){
#Notification
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Backup is late - ``date '+%m-%d-%Y %H:%M:%S'`` Gzip is already running!`" | mail -s `"Backup DB $dbName - Retard du backup`" $email" -timeout 1200
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Verifications - Gzip is already running"
	Start-Sleep -s 120
}

#Backup
#Notification
Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Backup - Started"
Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Started backup process - ``date '+%m-%d-%Y %H:%M:%S'```" | mail -s `"Backup DB $dbName - The backup process has started`" $email" -timeout 1200
#mysqldump
Invoke-SSHCommand -SSHSession $ssh -Command "nice -n 10 ionice -c2 -n 7 mysqldump -u $dbUser -p $dbPass $dbName --add-drop-table --single-transaction | gzip  -4 > $remoteSavePath/$fileName" -timeout 1200

#Transfert
#Making sure that the backup file exists
$ret = $(Invoke-SSHCommand -SSHSession $ssh -Command "ls -la $remoteSavePath/$filename").Output

#The file does exists
if($ret.Trim() -match ".sql.gz") {
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Transfering file - Started"
#Transfert via SCP
	Get-SCPFile -LocalFile "$localFolderPath\$folderName\$fileName" -RemoteFile "$remoteSavePath/$fileName" -ComputerName $remote_host -Credential $creds -AcceptKey:$true
	Invoke-SSHCommand -SSHSession $ssh -Command "rm -rf $remoteSavePath/$filename"
#Notification
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Backup successful - ``date '+%m-%d-%Y %H:%M:%S'```" | mail -s `"Backup DB $dbName - Success`" $email" -timeout 1200
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Transfering file - Done"
}

#Doesn't exists
elseif ($ret.Trim() -match "cannot access"){
#Log
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Transfert error - The file doesn't exists"
#Notification	
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Backup error - ``date '+%m-%d-%Y %H:%M:%S'`` Mysqldump backup file not found... `" | mail -s `"Backup DB $dbName - Error`" $email" -timeout 1200}

#Unknown error (Never been here, should never come here.) If it does, make sure it goes somewhere else in the future.
else {
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Error - Unknown error"
}


# Remove the session after we're done
Remove-SSHSession -Name $ssh | Out-Null
Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Backup - Done"
