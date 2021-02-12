<#
.SYNOPSIS
	The purpose of this script is to automate the deployment of individual bing keys to hosted customer.

.DESCRIPTION
	A new Roster deployment folder will be created containing the updated key if required.

.NOTES
	Author: Alex Cook
	Revision date: 06/02/2020
	Version: 1.0
#>


Import-Module DBATools

#$CsvFile=$args[0]
#if(-not($CsvFile)) {Throw "You must specify a csv file as input"}

$CsvFile = "C:\AppDel\Powershell\Automation\Bing\Test.csv"
$List = Import-Csv -Path $CsvFile -Header DBID,NewKey

$Prog = 0
$RosterRoot = "\\sp-FSVS01.advhc.local\Roster\"
$OldKey = "ztTbK0QjtTbuF7bmUPj9deFYI4ZYWLHPdACxZPtQJunuMDHb469tp6VP8AN98r2p0EWNPE4KVXq7c6bwaFmlGg2TfU0x4QsM"


function FindAG ($DBID) {

	$Query = "
		SELECT [AGname]
		FROM [tblDatabases_ALL]
		WHERE [DatabaseName] = '$DBID'
	"
	Invoke-DbaQuery -SqlInstance "CARE-VSQL-AHC1" -Database "UTILITY" -Query $Query
}

function FindRosterPath ($DBID) {

	$Query = "
		SELECT [RosterPath]
		FROM [tblDatabases_ALL]
		WHERE [DatabaseName] = '$DBID'
	"
	Invoke-DbaQuery -SqlInstance "CARE-VSQL-AHC1" -Database "UTILITY" -Query $Query
}

function UpdateHostedDBs ($AG,$DBID,$PathNew) {

	$Query = "
		UPDATE [tblDatabases]
		SET [RosterPath] = '$PathNew'
		WHERE [DatabaseName] = '$DBID'
	"
	$DB = "HostedDBs_" + $AG
	
	Invoke-DbaQuery -SqlInstance $AG -Database $DB -Query $Query
}


cls
Write-Host "progress_space"
Write-Host "progress_space"
Write-Host "progress_space"
Write-Host "progress_space"
Write-Host "progress_space"
Write-Host "progress_space"

Write-Host "BING - API KEY UPDATER" -ForegroundColor Magenta


ForEach ($Entry in $List) {

	$XMLSkip = 0

	$Prog++
	$Pcent = [math]::floor($(100 * ($Prog / $List.Count)))
	Write-Progress -Activity "Working through list..." -Status "$Prog / $($List.Count)" -PercentComplete $Pcent

	Write-Host "Obtaining information... " -ForegroundColor Green
	$DBID    = $Entry.DBID
	$NewKey  = $Entry.NewKey
	$AG      = FindAG $DBID
	$PathEx  = FindRosterPath $DBID
	$OrgID   = $DBID.Substring(0,9)
	$VerTest = $PathEx.RosterPath -Match '\d{4}'
	$Version = $Matches[0]
	$PathNew = $RosterRoot + $OrgID + "-" + $Version

	Switch ($Version.Substring(0,1)) {
		"4" { $RConfig = "\SPRoster40.exe.config"}
		"5" { $RConfig = "\SPRoster50.exe.config"}
		"6" { $RConfig = "\SPRoster60.exe.config"}
	}

	Write-Host "Checking if an updated RosterPath already exists... " -ForegroundColor Green
	if (-not(Test-Path -Path $PathNew)) {

		#Create Roster directory
		Write-Host "Folder not found, creating one..." -ForegroundColor Green
		Write-Host $PathNew
		Copy-Item -Path $PathEx.RosterPath -Recurse -Destination $PathNew -Container

		#Set Bing key
		Write-Host "Setting customer bing key..." -ForegroundColor Green
		$RosterConfigFile = $PathNew + $RConfig
		$RosterConfig = Get-Content $RosterConfigFile -Raw
		$RosterConfig = $RosterConfig.replace($OldKey, $NewKey)
		$RosterConfig = $RosterConfig.replace("ENTER YOUR LICENSE KEY HERE", $NewKey)
		Set-Content -Path $RosterConfigFile -Value $RosterConfig
	} else {
		Write-Host "Folder found" -ForegroundColor Green
		$XMLSkip = 1
	}

	#Update HostedDBs
	Write-Host "Updating HostedDBs with new path..." -ForegroundColor Green
	UpdateHostedDBs $AG.AGname $DBID $PathNew

	#Rebuild XML
	if ($XMLSkip -eq 0) {
		Write-Host "Opening Roster Version XML Tool... " -ForegroundColor Green
		Start-Process -FilePath 'C:\Tools\Roster Version Manager\RosterVersionChecksumXML.exe'
		Read-Host "Enter to Continue"
	}
}
