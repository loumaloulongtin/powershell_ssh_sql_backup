# powershell_ssh_sql_backup
This is a MySQL backup script I wrote to fetch a mysql database remotely every hour. I wrote it in a hurry thinking it would only be temporary. Yet, it has been running for a year and a half and it never failed me. So I tought I should share it.

# About
This script was written to suit specific needs at a specific times. It wasn't written to be reused anywhere in the beginning. I've put a few minutes to make it a bit more polyvalent, IE. Moving hardcoded stuff to variables, but in the end, you will probably have to edit a few things to make it suit your needs. 

# What does it do
This script run an hourly ***(Or as often as you schedule it to run in the task scheduler)*** mysql backup to a remote linux server using SSH. It will keep all the backups for the whole day and then delete all of them (Except the last one) on the next day. Last backup of each day is kept for 5 days.

# How it works
- Firt part is the cleaning up part. It just checks if it has to remove backup files folders. 
- Then it connects over SSH to the remote host. It checks the current server load and if the server is currently above the threshold    (Currently 3.0) it will wait 10 minutes and try again.  
- Then it checks if gzip or mysqldump are already running. If they do, it will try again in 2  minutes.
- If everything is checking out, it will start the backup process. The backup is done by mysqldump and saved in a gzipped format (With a compression ratio of 4, to be softer on cpu). It also uses nice and ionice to decrease the priority for the same reason. The reason of all this is that as it was ran every hour, this had to be executed during the most busy hours of the day. So it had to be done without slowing everything down.
- It checks if the newly created backup file does indeed exists.
- Then copy it to the local folder using SCP.
- Finally, it deletes the backup file from the remote host.

# Requirements
 - Posh-SSH (Powershell module) :: `Find-Module Posh-SSH | Install-Module`

# Installation
[...]
