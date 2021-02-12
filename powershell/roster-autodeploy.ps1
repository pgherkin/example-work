<#
.SYNOPSIS
	The purpose of this script is to fully automate the deployment of a Staffplan system for a new hosted customer.
	
.DESCRIPTION
	Currently this will not work for new franchisee customers that need to align to existing records.

.NOTES
	Author: Alex Cook
	Revision date: 23/01/2020
	Version: 3.5

.TODO
	Cassia Licenses

	Check to see if the following already exist:
		- OU Structure
		- Users, Groups
		- File directories
		- Live and training databases
#>

Import-Module DBATools

function RandomPW {
<#
.Description
Generates a random password
#>
	$password = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 10 | % {[char]$_})
    if ($password -cmatch "[A-Z]" -And $password -cmatch "[0-9]")
    {return $password}
    else
    {RandomPw}
}


#region: Variables (Static)

	$SPVersionLatest = "5610"

	$DOMAIN = 'ADVHC\'
	$ExportUserList = @()

	$LocationHash = @{
		"United Kingdom" = @("GBR","GB");
		"Ireland"        = @("IRL","IE");
		"Spain"          = @("SPA","ES");
		"Canada"         = @("CAN","CA");
		"Australia"      = @("AUS","AU")
	}
	$Locations = @($LocationHash.Keys)

	$RosterRoot = "\\sp-FSVS01.advhc.local\Roster\"
	$AppRoot = "C:\AppDel\Powershell\Automation\Roster Setup\"
	$ScriptRoot = $AppRoot + "Scripts\"
	$OutputRoot = $AppRoot + "Output\"
	$FullBackupRoot = "\\adv-backup-sl1\Backups\Staffplan\TempBackups\"

	$ADRoot = "OU=Roster,OU=Staffplan,OU=Hosted Applications,DC=ADVHC,DC=local"
	$ADGrpMembers = @(
		"Office View Only", 
		"AG-XA7.x-Roster", 
		"AG-XA7.x-Roster_Training", 
		"AG-XA7.x-Roster_Alarms", 
		"AG-XA7.x-Exchange",
		"AG-XA7.x-NomadTagWriter"
	)
	
	$BingDefaultKey = "ztTbK0QjtTbuF7bmUPj9deFYI4ZYWLHPdACxZPtQJunuMDHb469tp6VP8AN98r2p0EWNPE4KVXq7c6bwaFmlGg2TfU0x4QsM"
	
	$ProgressPreference = "SilentlyContinue"
	$nl = "`r`n"

#endregion

#region: Variables (Customer)

    cls
	Write-Host "HOSTED ROSTER INSTALL" -ForegroundColor Magenta

    Write-Host "
        This script attempts to fully automate a hosted Staffplan Roster setup
		
		Basic checking has been implemented to avoid duplication
		however there is no error handing at this point
		
		Colour key:
		Magenta is used for sections headers
		
		Lines shown in yellow text require an action or entry
		Default entries will be shown in square brackets [], pressing enter will use the default
		
		Green lines represent an action the script is performing
		
		This script relies on the DBATools module
		https://dbatools.io/
        "

	#Company name search (cassia)
	while ($CassiaAgain -ne "n") {
		$CompanyName = $(Write-Host "Enter a Company name to search Cassia e.g. Alexios: " -ForegroundColor Yellow -NoNewline; Read-Host)

		Write-Host "Searching Cassia..." -ForegroundColor Green
		$Script = $ScriptRoot + "CassiaSearch.sql"
		$ScriptContent = Get-Content $Script -Raw
		$ScriptContent = $ScriptContent.replace('COMPANY_NAME', $CompanyName)
		Invoke-Dbaquery -SQLInstance "SP-SQL02\SQL02" -Database "CassiaLive" -Query $ScriptContent | Format-Table -Wrap -AutoSize

		Write-Host "If no results have been displayed you have entered a unique search term"$nl
		$CassiaAgain = $(Write-Host "Would you like to search Cassia again? [y/n]: " -ForegroundColor Yellow -NoNewline; Read-Host)
	} 

	$CompanyName = $(Write-Host $nl"Enter a unique Company name: " -ForegroundColor Yellow -NoNewline; Read-Host)
	
	#Location
	Write-Host $nl"Available locations:"
	for ($Entry = 0; $Entry -lt $Locations.count; $Entry++) {
		write-host "["$Entry"]" $Locations[$Entry]
	}
	$LocationSelection = $(Write-Host "Enter the number which corresponds to the customer's location: " -ForegroundColor Yellow -NoNewline; Read-Host)
	$Location = $Locations[$LocationSelection]
	$DBLocationCode = $LocationHash.$Location[0]
	$CassiaLocationCode = $LocationHash.$Location[1]
	Write-Host "$Location selected, $DBLocationCode will be used in the database name"$nl

	#Cassia Variables
	$CassiaCreate = $(Write-Host "Create a new Cassia page? [y/n]: " -ForegroundColor Yellow -NoNewline; Read-Host)
	if ($CassiaCreate -match "[yY]") {
		Write-Host $nl"Please enter additional information about the customer" -ForegroundColor Yellow
		Write-Host "Mandatory fields marked with an *"$nl -ForegroundColor Red
		$CassiaName		  = $CompanyName
		if (($CassiaAlias = Read-Host "Company Alias*          [$CompanyName]") -eq ''){$CassiaAlias = $CassiaName}
		$CassiaStreet1	  = Read-Host "Address Street*   e.g. 123 Church Road"
		$CassiaStreet2	  = ""
		$CassiaStreet3	  = ""
		$CassiaTown		  = Read-Host "Address Town*     e.g. Ashford        "
		$CassiaCounty	  = Read-Host "Address County*   e.g. Kent           "
		$CassiaCountry	  = $CassiaLocationCode
		$CassiaPostcode	  = Read-Host "Address Postcode* e.g. TN24 8SB       "
		$CassiaPhone	  = Read-Host "Telephone number* e.g. 01233 722700   "
		$CassiaPhone	  = $CassiaPhone -replace '\s',''
		$CassiaEmail	  = Read-Host "Email address*    e.g. bob@gmail.com  "
		$CassiaNotes	  = Read-Host "Notes             e.g. Use main number"

		while ($CassiaConfirm -ne "n"  ) {
			Write-Host $nl"Check the details you have entered are correct" -ForegroundColor Yellow
			Write-Host "Company Name    :" $CassiaName
			Write-Host "Company Alias   :" $CassiaAlias
			Write-Host "Address Street  :" $CassiaStreet1
			Write-Host "Address Town    :" $CassiaTown
			Write-Host "Address County  :" $CassiaCounty
			Write-Host "Address Country :" $CassiaCountry
			Write-Host "Address Postcode:" $CassiaPostcode
			Write-Host "Telephone Number:" $CassiaPhone
			Write-Host "Email Address   :" $CassiaEmail
			Write-Host "Notes           :" $CassiaNotes

			$CassiaConfirm = $(Write-Host $nl"Would you like to change any of these details? [y/n]: " -ForegroundColor Yellow -NoNewline; Read-Host)
			if ($CassiaConfirm -match "[yY]") {				
				if (($CassiaNameUpdate     = Read-Host "*Company Name [$CompanyName]")        -ne ''){$CassiaName     = $CassiaNameUpdate}
				if (($CassiaAliasUpdate    = Read-Host "*Company Alias [$CassiaAlias]")       -ne ''){$CassiaAlias    = $CassiaAliasUpdate}
				if (($CassiaStreet1Update  = Read-Host "*Address line 1 [$CassiaStreet1]")    -ne ''){$CassiaStreet1  = $CassiaStreet1Update}
				if (($CassiaTownUpdate     = Read-Host "*Address town [$CassiaTown]")         -ne ''){$CassiaTown     = $CassiaTownUpdate}
				if (($CassiaCountyUpdate   = Read-Host "*Address county [$CassiaCounty]")     -ne ''){$CassiaCounty   = $CassiaCountyUpdate}
				if (($CassiaPostcodeUpdate = Read-Host "*Address postcode [$CassiaPostcode]") -ne ''){$CassiaPostcode = $CassiaPostcodeUpdate}
				if (($CassiaPhoneUpdate    = Read-Host "*Telephone number [$CassiaPhone]")    -ne ''){$CassiaPhone    = $CassiaPhoneUpdate}
				if (($CassiaEmailUpdate    = Read-Host "*Email address [$CassiaEmail]")       -ne ''){$CassiaEmail    = $CassiaEmailUpdate}
				if (($CassiaNotesUpdate    = Read-Host "Notes [$CassiaNotes]")                -ne ''){$CassiaNotes    = $CassiaNotesUpdate}
			}
		}
	}

	#DB Prefix
	while (!$DBPrefix) {
		Write-Host $nl"All databases require a 3 letter prefix, these are unique to the customer"
		Write-Host "Enter a prefix to be used e.g. HCL for HomeCare Limited, this will be checked to ensure it's unique: " -ForegroundColor Yellow -NoNewline
		$DBPrefixSearch = read-host
		$DBPrefixSearch = $DBPrefixSearch.ToUpper()

		Write-Host "Checking existing systems..." -ForegroundColor Green
		$Script = $ScriptRoot + "SQLHostedDBsCheck.sql"
		$ScriptContent = Get-Content $Script -Raw
		$ScriptContent = $ScriptContent.replace('DB_SEARCH', $DBPrefixSearch + "%")
		$DBPrefixResults = Invoke-DbaQuery -SqlInstance "CARE-VSQL-AHC1" -Database "UTILITY" -Query $ScriptContent

		if (!$DBPrefixResults) {
			Write-Host "Unique prefix found! $DBPrefixSearch will be used"$nl
			$DBPrefix = $DBPrefixSearch
		} else {
			Write-Host "Matches found:"$nl
			if ($DBPrefixResults.Length -gt 10) {
				Write-Host "Too many results, only showing the first 10"$nl
				$DBPrefixResults[0..10] | Format-Table -Wrap -AutoSize
			} else {
				$DBPrefixResults | Format-Table -Wrap -AutoSize
			}
            $DBPrefixBypass = $(Write-Host "Continue and use anyway? [y/n]: " -ForegroundColor Yellow -NoNewline; Read-Host)
			if ($DBPrefixBypass -match "[yY]") {
				$DBPrefix = $DBPrefixSearch
			}
		}
	}

	#DB Suffix
	if ($CassiaTown) {
		$DBSuffixSuggestion = $CassiaTown.ToUpper().SubString(0,3)
	} else {
		$DBSuffixSuggestion = "LON" 
	}

	if (($DBSuffix = $(Write-Host "Enter a 3 letter abbreviation for the customers town [$DBSuffixSuggestion]: " -ForegroundColor Yellow -NoNewline; Read-Host)) -eq ''){
		$DBSuffix = $DBSuffixSuggestion
	}

	$DBID = $DBPrefix + $DBLocationCode + $DBSuffix
	$DBIDLIV = $DBID + "LIV"
	$DBIDTRG = $DBID + "TRG"
	$Environments = @($DBIDLIV, $DBIDTRG)
	Write-Host "The following databases will be created:"
	Write-Host $DBIDLIV
	Write-Host $DBIDTRG
	Write-Host $nl

	#Roster Version
	while (!$RosterVersion) {
		if (($RosterVersion = $(Write-Host "Enter Roster version to be used [$SPVersionLatest]: " -ForegroundColor Yellow -NoNewline; Read-Host)) -eq '') {
			$RosterVersion = $SPVersionLatest
		}
		
		$RosterSource = $RosterRoot + "BLANK-" + $RosterVersion + "-BCN"
		$RosterDest   = $RosterRoot + $DBID.Substring(0,3) + "-" + $RosterVersion
		
		if (!(Test-Path $RosterSource)) {
			Write-Host "A BLANK template does not exist for that version!" -ForegroundColor Red
			Write-Host "You can now either create a BLANK template for $RosterVersion and then re-enter the same version"
			Write-Host "Or try another version"$nl
			Clear-Variable RosterVersion
		}
	}

	#AD Users
	do {
		try {[ValidatePattern('^\d+$')]$NoOfADUsers = $(Write-Host "Enter the number of AD users to create: " -ForegroundColor Yellow -NoNewline; Read-Host)}
		catch {Write-Error -Message "Error: Not a number!" -Category InvalidArgument}
	} until ($?)
	
	#Bing Key
	$BingKey = $(Write-Host "Enter Bing API key or press enter to use default [$($BingDefaultKey.SubString(0,10))...] : " -ForegroundColor Yellow -NoNewline; Read-Host)
	if ($BingKey -eq "") {$BingKey = $BingDefaultKey}
	
	Write-Host $nl

#endregion


#region: Cassia

	Write-Host "CASSIA" -ForegroundColor Magenta
	
	#Create Customer page
	if ( $CassiaCreate -match "[yY]" ) { 
		Write-Host $nl"Creating Cassia Page... " -ForegroundColor Green
		$Script = $ScriptRoot + "CassiaCreatePage.sql"
		$ScriptContent = Get-Content $Script -Raw
		$ScriptContent = $ScriptContent.replace('CASSIA_NAME',		$CassiaName)
		$ScriptContent = $ScriptContent.replace('CASSIA_ALIAS',		$CassiaAlias)
		$ScriptContent = $ScriptContent.replace('CASSIA_STREET1',	$CassiaStreet1)
		$ScriptContent = $ScriptContent.replace('CASSIA_STREET2',	$CassiaStreet2)
		$ScriptContent = $ScriptContent.replace('CASSIA_STREET3',	$CassiaStreet3)
		$ScriptContent = $ScriptContent.replace('CASSIA_TOWN',		$CassiaTown)
		$ScriptContent = $ScriptContent.replace('CASSIA_COUNTRY',	$CassiaCountry)
		$ScriptContent = $ScriptContent.replace('CASSIA_COUNTY',	$CassiaCounty)
		$ScriptContent = $ScriptContent.replace('CASSIA_POSTCODE',	$CassiaPostcode)
		$ScriptContent = $ScriptContent.replace('CASSIA_PHONE',		$CassiaPhone)
		$ScriptContent = $ScriptContent.replace('CASSIA_EMAIL',		$CassiaEmail)
		$ScriptContent = $ScriptContent.replace('CASSIA_NOTES',		$CassiaNotes)
		$ScriptContent = $ScriptContent.replace('CASSIA_DBIDLIV',	$DBIDLIV)
		Invoke-DbaQuery -SqlInstance "SP-SQL02\SQL02" -Database "CassiaLive" -Query $ScriptContent
	
	    #Get Organisation Id
	    $QueryContent = "SELECT [OrganisationID] FROM [tblOrganisation] WHERE [HostedDatabaseName] = '$DBIDLIV'"
	    $OrgId = Invoke-DbaQuery -SqlInstance "SP-SQL02\SQL02" -Database "CassiaLive" -Query $QueryContent
	    $OrgId = $OrgId[0]
    }
	
	#Generate User licenses
	#Need to automate this
	Write-Host $nl
	
#endregion

#region: Active Directory

	Write-Host "ACTIVE DIRECTORY"$nl -ForegroundColor Magenta
	
	#Import AD module
	import-module activedirectory

	#Create OU Structure
	Write-Host "Creating OU Structure..." -ForegroundColor Green
	New-ADOrganizationalUnit -name $CompanyName -path $ADRoot

	$ADPath = "OU=" + $CompanyName + "," + $ADRoot
	New-ADOrganizationalUnit -name $Location -path $ADPath

	$ADPath = "OU=" + $Location + "," + $ADPath
	New-ADOrganizationalUnit -name "Live" -path $ADPath

	$ADPath = "OU=Live," + $ADPath
	New-ADOrganizationalUnit -name $DBID -path $ADPath

	$ADPath = "OU=" + $DBID + "," + $ADPath

	#Create User Group
	Write-Host "Creating user group..." -ForegroundColor Green
	New-ADGroup -Name $DBID -SamAccountName $DBID -GroupCategory Security -GroupScope Global -Path $ADPath

	#Add Group members
	foreach ($Grp in $ADGrpMembers) {
		Add-ADPrincipalGroupMembership -Identity $DBID -MemberOf $Grp
	}

	#Create User Accounts
	Write-Host "Creating user accounts.." -ForegroundColor Green
	$USRID = $DBIDLIV + "USR"
	for ($UserNo=1; $UserNo -le $NoOfADUsers; $UserNo++){

		if ($UserNo -lt 10) {$UserNoFormat = $UserNo.ToString("00")}
		else {$UserNoFormat = $UserNo}
		$UserAcc = $USRID + $UserNoFormat
        $UserPass = RandomPW
		$SecureUserPass = ConvertTo-SecureString $UserPass -AsPlainText -force

		New-ADUser -Name $UserAcc `
			-SamAccountName $UserAcc `
			-UserPrincipalName $UserAcc$Domain `
			-GivenName $UserAcc `
			-DisplayName $UserAcc `
			-AccountPassword $SecureUserPass `
			-ChangePasswordAtLogon 0 `
			-CannotChangePassword 0 `
			-PasswordNeverExpires 1 `
			-Enabled 1 `
			-Path $ADPath

		Add-ADGroupMember -Identity $DBID -Members $UserAcc

		$ExportUserList += @([pscustomobject]@{Username = $UserAcc;Password = $UserPass})
	}
	
	#Create Output directory
	$OutputDir = $OutputRoot + $DBID + "\"
	
	if (Test-Path $OutputDir) {
		Write-Host "The following output directory already exists: $OutputDir"
		Write-Host "If you are not aware of a previous attempt, stop this script and check."
		Write-Host $nl
		
		$OutputDirConfirm = $(Write-Host "Would you like to clear the folder and continue? [y/n]: " -ForegroundColor Yellow -NoNewline; Read-Host)
		if ($OutputDirConfirm -eq 'y') {
			Write-Host "Deleting contents... " -ForegroundColor Green
			Get-ChildItem -Path $OutputDir -Include *.* -File -Recurse | foreach { $_.Delete()}
		} else {
			Write-Error "Cannot continue until the directory is deleted" -ErrorAction Stop
		}
	}
    New-Item -ItemType directory -Path $OutputDir
	
	#Write out usernames, passwords to file
	$OutputFileUsers = $OutputDir + "Users.csv"
	$ExportUserList = $ExportUserList.replace("`"", "")
	$ExportUserList | Export-Csv -Path ($OutputFileUsers) -NoTypeInformation
	Write-Host "Usernames and passwords have been written to: $OutputFileUsers"
	Write-Host $nl

#endregion

#region: File Directories

	Write-Host "FILE DIRECTORIES"$nl -ForegroundColor Magenta

	$CUS_PATH_ENV = "\\sp-FSVS01.advhc.local\Environments\" + $DBID
	$CUS_PATH_SHR = "\\sp-FSVS01.advhc.local\Shared\" + $DBID

	if (Test-Path $CUS_PATH_ENV) {
		Write-Error "Directories on the \\sp-FSVS01 share already exist for this database ID." -ErrorAction Stop
	} else {
		#Create directories
		Write-Host "Creating Environment and Shared Directories... " -ForegroundColor Green
		New-Item -ItemType directory -Path $CUS_PATH_ENV | Out-Null
		Write-Host $CUS_PATH_ENV
		New-Item -ItemType directory -Path $CUS_PATH_SHR | Out-Null
		Write-Host $CUS_PATH_SHR

		#Set Environment permissions
		Write-Host "Setting Permissions... " -ForegroundColor Green
		$Acl = Get-Acl $CUS_PATH_ENV
		$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule(
			$DBID, 
			"Modify", 
			"ContainerInherit, ObjectInherit", 
			"None", 
			"Allow"
			)
		$Acl.SetAccessRule($Ar)
		Set-Acl $CUS_PATH_ENV $Acl

		#Set Share permissions
		$Acl = Get-Acl $CUS_PATH_SHR
		$Ar = New-Object  system.security.accesscontrol.filesystemaccessrule(
			$DBID, 
			"Modify", 
			"ContainerInherit, ObjectInherit", 
			"None", 
			"Allow"
			)
		$Acl.SetAccessRule($Ar)
		Set-Acl $CUS_PATH_SHR $Acl

		#Create Roster directory
		Write-Host "Creating Roster Folder... " -ForegroundColor Green
		Write-Host $RosterDest
		Copy-Item -Path $RosterSource -Recurse -Destination $RosterDest -Container
		
		#Set Bing key
		if ($BingKey -ne $BingDefaultKey) {
			$RosterConfigFile = $RosterDest + "\SPRoster50.exe.config"
			$RosterConfig = Get-Content $RosterConfigFile -Raw
			$RosterConfig = $RosterConfig.replace($BingDefaultKey, $BingKey)
			Set-Content -Path $RosterConfigFile -Value $RosterConfig
		}

		#Copy Sample Invoice Layouts
		Write-Host "Copying Sample Invoice Layouts into Shared folder... " -ForegroundColor Green
		$SILSource = $RosterDest + "\Sample Invoice Layouts"
		$SILDest   = $CUS_PATH_SHR + "\Sample Invoice Layouts"
		Copy-Item -Path $SILSource -Recurse -Destination $SILDest -Container
	}

	Write-Host $nl

#endregion

#region: Live Database

	Write-Host "LIVE DATABASE"$nl -ForegroundColor Magenta

	#DB AG
	Write-Host "Getting least used AG... (This usually takes a couple of minutes)" -ForegroundColor Green
	$AGLeastUsed = Invoke-DbaQuery -SqlInstance "SP-SQL01-GR2" -Database "UTILITY" -QueryTimeout 300 -Query "exec GetLeastUsedAG ''"
	$AGLeastUsed = $AGLeastUsed[0]
	Write-Host "The least used AG is $AGLeastUsed"
	if (($AG = $(Write-Host "Enter an alternative AG name or press enter to use [$AGLeastUsed]: " -ForegroundColor Yellow -NoNewline; Read-Host)) -eq ''){
		$AG = $AGLeastUsed
	}

	#Create LIV Database
	Write-Host $nl"Creating Live Database... " -ForegroundColor Green
	New-DbaDatabase -SqlInstance $AG -Name $DBIDLIV

	#New DB Script
	Write-Host "Running New DB Script... " -ForegroundColor Green
	$Script = $ScriptRoot + "SQLNewDBConfig.sql"
	$ScriptContent = Get-Content $Script -Raw
	Invoke-DbaQuery -SqlInstance $AG -Database $DBIDLIV -Query $ScriptContent

	#Create SQL Logins
	Write-Host "Creating SQL logins... " -ForegroundColor Green
	$Script = $ScriptRoot + "SQLCreateLogin.sql"
	$ScriptContent = Get-Content $Script -Raw
	$ScriptContent = $ScriptContent.replace("SUPPORT_USER", $DBID.SubString(0,3) + "_Staffplan")
	$ScriptContent = $ScriptContent.replace("DOMAIN_GROUP", $DOMAIN + $DBID)
	Invoke-DbaQuery -SqlInstance $AG -Database "MASTER" -Query $ScriptContent

	#Create SQL Users
	$Script = $ScriptRoot + "SQLCreateUser.sql"
	$ScriptContent = Get-Content $Script -Raw
	$ScriptContent = $ScriptContent.replace("SUPPORT_USER", $DBID.SubString(0,3) + "_Staffplan")
	$ScriptContent = $ScriptContent.replace("DOMAIN_USER", $DOMAIN + $DBID)
	Invoke-DbaQuery -SqlInstance $AG -Database $DBIDLIV -Query $ScriptContent

	#Roster Procedures
	Write-Host "Running Staffplan procedures... (This usually takes a couple of minutes)" -ForegroundColor Green
	$Script = $RosterDest + "\Procedures.sql"
	$ScriptContent = Get-Content $Script -Raw
	Invoke-DbaQuery -SqlInstance $AG -Database $DBIDLIV -QueryTimeout 300 -Query $ScriptContent
	Write-Host "The following known errors can be ignored:"
	Write-Host "JIRA SP-3099 - Invalid object name 'dbo.viewMonitoringFailureReason'"

	#Roster Procedures Check
	Write-Host "Checking Staffplan procedures..." -ForegroundColor Green
	$ScriptContent = "
		SELECT Value
		FROM tblSysParams
		WHERE ParamKey = 'V4ProcsVer'
		"
	$ProcRosterVersion = Invoke-DbaQuery -SqlInstance $AG -Database $DBIDLIV -QueryTimeout 300 -Query $ScriptContent
	if ($ProcRosterVersion) {
		Write-Host "Staffplan procedures completed successfully" -ForegroundColor Green
	} else {
		Write-Host "Staffplan procedures has not completed!" -ForegroundColor Red
		Start-Process notepad.exe $Script
		Read-Host "Run procedures manually now, press enter when done"
	}

	#Bespokes
	Read-Host "Install any bespokes now, press enter when done"

	#Cassia Licenses
	Read-Host "Generate Cassia licences and then run the scripts manually against $DBIDLIV, press enter when done"

	#Add Roster Support User
	Write-Host "Adding the Support User... " -ForegroundColor Green
	$Script = $ScriptRoot + "RosterAddUser.sql"
	$ScriptContent = Get-Content $Script -Raw
	$ScriptContent = $ScriptContent.replace("ROSTER_USERNAME", $DBID.SubString(0,3) + "_Staffplan")
	Invoke-DbaQuery -SqlInstance $AG -Database $DBIDLIV -Query $ScriptContent

	#Add Roster Customer User(s)
	Write-Host "Adding customer users... " -ForegroundColor Green
	for ($UserNo=1; $UserNo -le $NoOfADUsers; $UserNo++){

		if ($UserNo -lt 10) {$UserNoFormat = $UserNo.ToString("00")}
		else {$UserNoFormat = $UserNo}
		$UserAcc = $USRID + $UserNoFormat

		$ScriptContent = Get-Content $Script -Raw
		$ScriptContent = $ScriptContent.replace("ROSTER_USERNAME", $UserAcc)
		Invoke-DbaQuery -SqlInstance $AG -Database $DBIDLIV -Query $ScriptContent
	}

	#Set Live Company Name
	Write-Host "Setting company name... " -ForegroundColor Green
	$Script = $ScriptRoot + "SQLHouseKeeping.sql"
	$ScriptContent = Get-Content $Script -Raw
	$ScriptContent = $ScriptContent.replace("COMPANY_NAME", $CompanyName)
	$ScriptContent = $ScriptContent.replace("ENV", "Live")
	Invoke-DbaQuery -SqlInstance $AG -Database $DBIDLIV -Query $ScriptContent

	Write-Host $nl

#endregion

#region: Training Database

	Write-Host "TRAINING DATABASE"$nl -ForegroundColor Magenta

	#Backup Liv
	Write-Host "Backing up live database... " -ForegroundColor Green
	$Timestamp = Get-Date -Format "yyyyMMdd-HHmm"
	$FullBackupPath = $FullBackupRoot + $DBIDLIV + "_" + $Timestamp + ".bak"
    Backup-DbaDatabase -SqlInstance $AG -Database $DBIDLIV -FilePath $FullBackupPath -CopyOnly

	#Restore as Trg
	Write-Host "Restoring backup as $DBIDTRG... " -ForegroundColor Green
	Restore-DbaDatabase -SqlInstance $AG -Path $FullBackupPath -DatabaseName $DBIDTRG -ReplaceDbNameInFile

	#New DB Script
	Write-Host "Running New DB Script... " -ForegroundColor Green
	$Script = $ScriptRoot + "SQLNewDBConfig.sql"
	$ScriptContent = Get-Content $Script -Raw
	Invoke-DbaQuery -SqlInstance $AG -Database $DBIDTRG -Query $ScriptContent

	#Set Training Company Name
	Write-Host "Setting company name... " -ForegroundColor Green
	$Script = $ScriptRoot + "SQLHouseKeeping.sql"
	$ScriptContent = Get-Content $Script -Raw
	$ScriptContent = $ScriptContent.replace("COMPANY_NAME", $CompanyName)
    $ScriptContent = $ScriptContent.replace("ENV", "Training")
	Invoke-DbaQuery -SqlInstance $AG -Database $DBIDTRG -Query $ScriptContent

	Write-Host $nl

#endregion 

#region: Add Databases to AG

	Write-Host "ADDING TO AG"$nl -ForegroundColor Magenta

	#Full backups
	Write-Host "Taking full backups... " -ForegroundColor Green
	$Timestamp = Get-Date -Format "yyyyMMdd-HHmm"
	$LIVBackupPath = $FullBackupRoot + $DBIDLIV + "_" + $Timestamp + ".bak"
	$TRGBackupPath = $FullBackupRoot + $DBIDTRG + "_" + $Timestamp + ".bak"
	Backup-DbaDatabase -SqlInstance $AG -Database $DBIDLIV -FilePath $LIVBackupPath -Type Full
	Backup-DbaDatabase -SqlInstance $AG -Database $DBIDTRG -FilePath $TRGBackupPath -Type Full

	#Obtain AG servers
	Write-Host "Finding server names... " -ForegroundColor Green
	$Script = $ScriptRoot + "SQLAGFindServers.sql"
	$ScriptContent = Get-Content $Script -Raw
	$ScriptContent = $ScriptContent.replace("AG_NAME", $AG)
	$AGDetails = Invoke-DbaQuery -SqlInstance $AG -Database "Master" -Query $ScriptContent

	#Determine Primary/Secondary
	switch ($AGDetails[0].Server_Type) {
		"PRIMARY" {
			$AGPrimaryServer = $AGDetails[0].Server_Name;
			$AGPrimaryEndpoint = $AGDetails[0].Endpoint_URL;
			$AGSecondaryServer = $AGDetails[1].Server_Name;
			$AGSecondaryEndpoint = $AGDetails[1].Endpoint_URL
			}
		"SECONDARY" {
			$AGPrimaryServer = $AGDetails[1].Server_Name;
			$AGPrimaryEndpoint = $AGDetails[1].Endpoint_URL;
			$AGSecondaryServer = $AGDetails[0].Server_Name;
			$AGSecondaryEndpoint = $AGDetails[0].Endpoint_URL
			}
	}

<# Not required. The add to AG restores to the secondaries

	#Restore to Secondaries
	Write-Host "Restoring backups to the secondary servers..." -ForegroundColor Green
	Restore-DbaDatabase -SqlInstance $AGSecondaryServer -Path $LIVBackupPath -DatabaseName $DBIDLIV -WithReplace
	Restore-DbaDatabase -SqlInstance $AGSecondaryServer -Path $TRGBackupPath -DatabaseName $DBIDTRG -WithReplace
#>

    #Add databases into the AG
	Write-Host "Adding databases to the AG..." -ForegroundColor Green
	Add-DbaAgDatabase -SqlInstance $AGPrimaryServer -AvailabilityGroup $AG -Secondary $AGSecondaryServer -Database $DBIDLIV, $DBIDTRG -SharedPath $FullBackupRoot

	Write-Host $nl

#endregion

#region: Final Checks

	Write-Host "FINAL TASKS"$nl -ForegroundColor Magenta

	Write-Host "Registering databases in Exchange..." -ForegroundColor Green

	#Auto exchange registration
	ForEach ($Environment in $Environments) {

		Switch ($Environment.Substring(9,3)) {
			"LIV" {
				$ExDBType = 1
				$ExDBDesc = "Live"
				}
			"TRG" {
				$ExDBType = 2
				$ExDBDesc = "Training"
				}
		}

		$Script = $ScriptRoot + "ExchangeRegisterDB.sql"
		$ScriptContent = Get-Content $Script -Raw

		$ScriptContent = $ScriptContent.replace("COMPANY_NAME", $CompanyName)
		$ScriptContent = $ScriptContent.replace("DATABASE_NAME", $Environment)
		$ScriptContent = $ScriptContent.replace("DATABASE_TYPE", $ExDBType)
		$ScriptContent = $ScriptContent.replace("DESCRIPTION", $Company + " - " + $ExDBDesc)
		$ScriptContent = $ScriptContent.replace("LOGIN_TYPE", "Windows")
		$ScriptContent = $ScriptContent.replace("PARENT_COMPANY", $CompanyName)
		$ScriptContent = $ScriptContent.replace("ROSTER_PATH", $RosterDest)
		$ScriptContent = $ScriptContent.replace("ORGANISATION_ID", $OrgId)

		$ExHostedDB = "HostedDBs_" + $AG
		Invoke-DbaQuery -SqlInstance $AG -Database $ExHostedDB -Query $ScriptContent
	}

	Write-Host "Opening Roster Version XML Tool... " -ForegroundColor Green
	Start-Process -FilePath 'C:\Tools\Roster Version Manager\RosterVersionChecksumXML.exe'
	Read-Host "Enter to Continue"

	Write-Host "Don't forget to test... :)" -ForegroundColor Green
	$ExportUserList[0]

	$OutputFileLog = $OutputDir + "Log.txt"
	$LogDetails = "
		Installation DateTime: $Timestamp     $nl
		OrgID:                 $OrgID         $nl
		Customer:              $CassiaName    $nl
		AvailabilityGroup:     $AG            $nl
		Live Database:         $DBIDLIV       $nl
		Training Database:     $DBIDTRG       $nl
		Version:               $RosterVersion $nl
		Roster Folder:         $RosterDest    $nl
		Shared Folder:         $CUS_PATH_SHR  $nl
		Environment Folder:    $CUS_PATH_ENV  $nl
		Culprit:               $env:UserName  $nl
		"
	$LogDetails | Out-File -Append $OutputFileLog

	Write-Host "
		A summary of the details has been written to:
		$OutputFileLog
		these can be added to the salesforce case
		"

	Write-Host "The End!" -ForegroundColor Magenta -NoNewline; Read-Host

#endregion
