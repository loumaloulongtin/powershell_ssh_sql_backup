###############################################################################################################################################################
# Author : Lou-Malou Longtin																                                                                                                  # 
#	https://github.com/loumaloulongtin/														                                                                                              # 
#                                                                                                 																			                      #
# Date : 07/27/2017																	                                                                                                          #
#																			                                                                                                                        #
# Required modules : Posh-SSH																                                                                                                  #	
#   Find-Module Posh-SSH | Install-Module														                                                                                          #	
#  OR																			                                                                                                                    #
#   iex (New-Object Net.WebClient).DownloadString("https://gist.github.com/darkoperator/6152630/raw/c67de4f7cd780ba367cccbc2593f38d18ce6df89/instposhsshdev") #
# 																			                                                                                                                      #
# Description : This script is used to backup a single database. It is designed to have a 5 days retention. The backups are ran hourly. Only the last backup  #
# of the last 4 preceding days are kept. All backups of the current day are kept until the next one.                                                          #
#      								                                                                                                                                        #
# The script takes care of determining if it is already running or not. It uses SSH and the mysqldump command to execute the backup. Then fetch it using scp. #
# As it is being done hourly on the production server, it also checks the current server load and delay the backup if it is too heavy.				                #
# Backup files are deleted from the remote server after the transfer has been completed.							                                                        #
#											                                                                                                                                        #                  
# TODOs :: Translate - Add a variable for remote folder path.                                                                                                 #
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

#Paths / File names - LOCAL&&REMOTE
$localFolderPath = "D:\path\to\backup" # Local folder to save backup files
$folderName = Get-Date -format ddMMyy # How the folders are named (1 folder / day of retention)
$fileName = "$(Get-Date -format ddMMyy-HHmmss).sql.gz" # Name of the backup files
$logsPath = "D:\path\to\log\folder" #Path to log folder

#Logging
$logFile = "$(Get-Date -format dd-MM-yy).log"
#Si le fichier de log n'existe pas deja... On le cree
if (!(Test-Path "$logsPath\$logFile"))
{
	New-Item -path "$logsPath\" -name $logFile -type "file"
}
#ajoute le chemin devant le nom du fichier.
$logFile = "$logsPath\$logFile"


#Add-content $logFile -value $logstring

#Menage
Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Menage des fichiers et dossiers locaux."
$localFolder = get-childitem -Path $localFolderPath -Recurse | where-object { $_.PSIsContainer }

#Menage des dossiers
while($localFolder.Count -gt 5) { 
	$ItemName = $localFolder | Sort CreationTime | select -First 1 #Selection du dossier le plus ancien
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Menage des dossiers - Suppression du dossier : $ItemName"
	$ItemName | Remove-Item -Recurse #Supression du dossier
	$localFolder = get-childitem -Path $localFolderPath -Recurse | where-object { $_.PSIsContainer } #Mise a jour des childrens du dossier de backup
}

#Menage des fichiers
$count = $localFolder.Count-1
for($i =0; $i -lt $localFolder.Count-1; $i++){ # Count-1 (On ne veut pas nettoyer le dossier d'aujour'hui.
	$item = $localFolder | Sort CreationTime | Select-Object -Skip $i | Select-Object -First 1
	while((get-childitem -Path "$localFolderPath\$item\").Count -gt 1) {
		$ItemName = get-childitem -Path "$localFolderPath\$item\" | Sort CreationTime | select -First 1
		Write-Host $ItemName
		Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Menage des fichiers - Suppression du fichier : $ItemName"
		$ItemName | Remove-Item -Recurse
	}
}
#Creation du dossier pour la journee, si pas deja existant...
if(!(test-path "$localFolderPath\$folderName")){
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Nouvelle journee - Creation du dossier : $localFolderPath\$folderName."
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
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Retard du backup - ``date '+%m-%d-%Y %H:%M:%S'`` Load trop eleve!`" | mail -s `"Backup DB  {db} - Retard du backup`" {email}" -timeout 1200
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Verifications - Load trop eleve"
	Start-sleep -s 600
	$workload = $(Invoke-SSHCommand -SSHSession $ssh -Command "uptime | awk '{print `$10'}").Output
}


#Est-ce que mysqldump ou gzip roulent deja? (On essaie de pas ralentir le serveur)
#Mysqldump
while($(Invoke-SSHCommand -SSHSession $ssh -Command "ps aux | grep `"[m]ysqldump`"").Output -match "mysqldump"){
#Notification
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Retard du backup - ``date '+%m-%d-%Y %H:%M:%S'`` Mysqldump roule deja!`" | mail -s `"Backup DB {db} - Retard du backup`" {email}" -timeout 1200
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Verifications - Mysqldump roule deja"
	Start-Sleep -s 120
}

#Gzip
while($(Invoke-SSHCommand -SSHSession $ssh -Command "ps aux | grep `"[g]zip`"").Output -match "gzip"){
#Notification
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Retard du backup - ``date '+%m-%d-%Y %H:%M:%S'`` Gzip roule deja!`" | mail -s `"Backup DB {db} - Retard du backup`" {email}" -timeout 1200
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Verifications - Gzip roule deja"
	Start-Sleep -s 120
}

#Backup
#Notification
Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Backup - Debut du backup"
Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Debut du backup - ``date '+%m-%d-%Y %H:%M:%S'```" | mail -s `"Backup DB {db} - Debut du backup`" {email}" -timeout 1200
#mysqldump
Invoke-SSHCommand -SSHSession $ssh -Command "nice -n 10 ionice -c2 -n 7 mysqldump -u $dbUser -p $dbPass $dbName --add-drop-table --single-transaction | cstream -t 5000000 | gzip  -4 > /root/backup/$fileName" -timeout 1200

#Transfert
#Verifie que le fichier de db existe. (le mysqldump a fonctionne)
$ret = $(Invoke-SSHCommand -SSHSession $ssh -Command "ls -la /root/backup/$filename").Output

#Si le fichier existe
if($ret.Trim() -match ".sql.gz") {
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Transfert du fichier- Debut du transfter"
#Transfert via SCP
	Get-SCPFile -LocalFile "$localFolderPath\$folderName\$fileName" -RemoteFile "/root/backup/$fileName" -ComputerName $remote_host -Credential $creds -AcceptKey:$true
	Invoke-SSHCommand -SSHSession $ssh -Command "rm -rf /root/backup/$filename"
#Notification
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Succes du backup - ``date '+%m-%d-%Y %H:%M:%S'```" | mail -s `"Backup DB {db} - Succes`" {email}" -timeout 1200
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Transfert du fichier - Fin du transfert"
}

#Si il n'existe pas
elseif ($ret.Trim() -match "cannot access"){
#Log
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Transfert du fichier - ERREUR : Le fichier n'existe pas"
#Notification	
	Invoke-SSHCommand -SSHSession $ssh -Command "echo `"Erreur dans le backup - ``date '+%m-%d-%Y %H:%M:%S'`` Fichier non trouve... `" | mail -s `"Backup DB {db} - Erreur`" {email}" -timeout 1200
}

#Erreur inconnue
else {
	Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - ERREUR - ERREUR INCONNUE"
}


# Remove the session after we're done
Remove-SSHSession -Name $ssh | Out-Null
Add-content $logFile -value "$(Get-Date -format HH:mm:ss) - Backup - Fin du backup"
