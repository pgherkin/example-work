compile subroutine UTIL_GFE_MANAGER(param)

/*
    Version    Date      Details
    1.0        26/08/14  The birth!
    1.1        27/08/14  Added revfile backup status for user feedback
    1.2        19/03/15  Shortened variable names
    1.3        19/03/15  Added dateStamped backup dir
    1.4        20/03/15  Create log with gfe info
    1.5        13/04/15  UI improvements + show group #s on double click
    1.6        23/06/15  Fix for LSv2

    To do
	- Check to see if the fix dumps the data
	- Separate logging
*/

	declare function util_getDataFolder
	declare function msg, status, utility
	declare function get_property, set_property
	declare function util_lhverify, util_lhfix
	declare function getEnvironmentVariable

	$insert msg_equates
	$Insert standard_common
	$insert standard_equates
	$insert extra_common

	avblTblLst = @window:'.LSTAVAILABLETABLES'
	slctTblLst = @window:'.LSTSELECTEDTABLES'
	resultTbl = @window:'.TBLRESULTS'

	dataDir = util_getDataFolder()
	dateStamp = oconv(Date(),"DE.")

	begin case
		case param = 'CREATE'
			gosub create
		case param = 'ADDTABLE'
			gosub addTable
		case param = 'REMOVETABLE'
			gosub removeTable
		case param = 'ADDTABLEALL'
			gosub addTableAll
		case param = 'REMOVETABLEALL' 
			gosub removeTableAll
		case param = 'SHOWGFES'
			gosub showGfes
		case param = 'VERIFY'
			gosub verify
		case param = 'BKUPTABLES'
			gosub bkuptables
		case param = 'FIXGFES'
			gosub fixgfes
		case param = 'CLEAR'
			gosub clearResults
	end case
return

create:
	avblTblAry = @tables
	avblTblCnt = dcount(avblTblAry, @fm)

	for w = avblTblCnt to 1 step -1
		table = avblTblAry<w>
		if table[1,4] = 'DICT' or table[1,1] = '!' then
			avblTblAry = delete(avblTblAry, w, 0, 0)
		end
	next

	call set_property(avblTblLst,'LIST',avblTblAry)
return

addTable:
	slctTbl = get_property(avblTblLst,'TEXT')
	slctTblAry = get_property(slctTblLst,'LIST')

	slctTblAry<-1> = slctTbl	

	call set_property(slctTblLst,'LIST',slctTblAry)
return

removeTable:
	slctTbl = get_property(slctTblLst,'TEXT')
	slctTblAry = get_property(slctTblLst,'LIST')

	locate slctTbl in slctTblAry using @fm setting pos then
		slctTblAry = delete(slctTblAry, pos, 0, 0)
	end	

	call set_property(slctTblLst,'LIST',slctTblAry)
return

addTableAll:
	slctTblAry = @tables
	slctTblAryCnt = dcount(slctTblAry, @fm)

	for w = slctTblAryCnt to 1 step -1
		table = slctTblAry<w>
		if table[1,4] = 'DICT' or table[1,1] = '!' then
			slctTblAry = delete(slctTblAry, w, 0, 0)
		end
	next

	call set_property(slctTblLst,'LIST',slctTblAry)
return

removeTableAll:
	slctTblAry = ''
	call set_property(slctTblLst,'LIST',slctTblAry)
return

showGfes:
	*get windows %temp% environment variable
	winTempVar = "TEMP"
	winTempLen = getEnvironmentVariable(winTempVar, "", 0) + 1
	winTempVal = space(winTempLen+1)
	winTempLen = getEnvironmentVariable(winTempVar, winTempVal, winTempLen)
	winTempVal = winTempVal[1, winTempLen]

	slctRstRow = get_property(resultTbl,'ROWDATA')
	slctRstTbl = slctRstRow<1>
	slctRstGfes = slctRstRow<3>

	if slctRstGfes # '' then
		swap ',' with \0D0A\ in slctRstGfes

		gfesFile = winTempVal:"\":"Group_Numbers_":rnd(999999):'.txt'
		oswrite slctRstGfes to gfesFile

		program = 'notepad.exe':' ':gfesFile
		call utility('RUNWIN', program, 5)
	end else
		msg(@window, slctRstTbl:" does not have any GFEs")
	end

return

verify:
	resultAry = ''
	tblToVer = get_property(slctTblLst,'LIST')
	tblToVerCnt = dcount(tblToVer, @fm)

	if tblToVerCnt = 0 then
		noTblToVer = "No tables have been selected to verify!"
		msg(@window, noTblToVer)
	end else
		for x = 1 to tblToVerCnt
			resultAry = insert(resultAry, 1, x, 0, tblToVer<x>)
			resultAry = insert(resultAry, 2, x, 0, "Checking...")

			call set_property(resultTbl,'ARRAY',resultAry)
			call util_lhverify(dataDir,tblToVer<x>)

			open 'SYSLHGROUP' to f.syslhgrp else
				syslhgrperror = "Cannot open SYSLHGROUP to verify the results!"
				msg(@window, syslhgrperror)
			end

			select f.syslhgrp

			gfes = ''
			gfeCnt = 0
			eof = ''
			loop
				readnext id else eof = 1
			until eof do
				gfeCnt += 1
				gfes<gfeCnt> = id[(indexc(id, "*", 3) + 1), len(id)]
			repeat

			if gfeCnt = 0 then
				resultAry = replace(resultAry, 2, x, 0, "Ok")
			end else
				if gfes = 0 then
					resultAry = replace(resultAry, 2, x, 0, "Group 0 GFE found!")
				end else
					swap @fm with ',' in gfes
					resultAry = insert(resultAry, 3, x, 0, gfes)
					resultAry = replace(resultAry, 2, x, 0, gfeCnt:" GFE(s) found")
				end
			end

			call set_property(resultTbl,'ARRAY',resultAry)
		next
	end
return

bkuptables:
	gfeAry = get_property(resultTbl, 'ARRAY')
	gfeAryCnt = dcount(gfeAry<1>, @vm)

	if gfeAry<1,1> # '' then
		*creating a array of db tables and their revfiles
		gosub revfiles

		*creating a array of tables with gfes and the gfe #s and revfiles
		for y = gfeAryCnt to 1 step -1
			if gfeAry<3,y> = '' then
				*remove table as there are no gfes
				gfeAry = delete(gfeAry, 1, y, 0)
				gfeAry = delete(gfeAry, 2, y, 0)
				gfeAry = delete(gfeAry, 3, y, 0)
				gfeAry = delete(gfeAry, 4, y, 0)
			end else
				*add revfile to array as the table as gfes
				rfileAryCnt = dcount(revfileArray, @fm)
				for v = 1 to rfileAryCnt
					if revfileArray<v,2> = gfeAry<1,y> then
						gfeAry<4,y> = revfileArray<v,3>
					end
				next
			end
		next

		gosub createBkupDir

        *backup affected tables
		gfeAryCnt = dcount(gfeAry<1>, @vm)

		for u = 1 to gfeAryCnt
			gfeAry = replace(gfeAry, 2, u, 0, "Backing up Revfile...")
			call set_property(resultTbl,'ARRAY',gfeAry)

			LKfileCopy = dataDir:gfeAry<4,u>:".LK"
			LKfilePaste = backupDir:gfeAry<4,u>:".LK"

			OVfileCopy = dataDir:gfeAry<4,u>:".OV"
			OVfilePaste = backupDir:gfeAry<4,u>:".OV"		

			call utility('COPYFILE',LKfileCopy, LKfilePaste)
			call utility('COPYFILE',OVfileCopy, OVfilePaste)

			gfeAry = replace(gfeAry, 2, u, 0, "Revfiles backed up!")
			call set_property(resultTbl,'ARRAY',gfeAry)
		next

		backupMsg = "All GFE effected table files have been backed up to:"
		backupMsg := "|":backupDir
		msg(@window, backupMsg)
	end else
		noBackupMsg = "There is nothing to backup!"
		msg(@window, noBackupMsg)
	end
return

fixgfes:
	*if LSv2 is enabled the data directory needs to be attached
	LSyncTwo = xlate('PRACTICE_DETAILS','PRACTICE','94','X')
	if LSyncTwo then
		call attach_table(dataDir,"","","")
	end

	log = 'The following GFEs have been fixed:':\0D0A\:\0D0A\
	gfeAry = get_property(resultTbl, 'ARRAY')
	gfeAryCnt = dcount(gfeAry<1>, @vm)

	if gfeAry<1,1> # '' then
		for s = 1 to gfeAryCnt
			table = gfeAry<1,s>
			tableGfe = gfeAry<3,s>

			log := table:': ':tableGfe:\0D0A\

			if tableGfe # '' then
				gfeAry = replace(gfeAry, 2, s, 0, "Fixing GFE(s)...")
				call set_property(resultTbl,'ARRAY',gfeAry)

				swap ',' with @vm in tableGfe
				tableGfeCnt = dcount(tableGfe<1>, @vm)	

				for r = 1 to tableGfeCnt
					call util_lhfix(table,tableGfe<1,r>)
				next

				gfeAry = replace(gfeAry, 2, s, 0, "GFE(s) Fixed!")
				call set_property(resultTbl,'ARRAY',gfeAry)
			end
		next

		gosub createBkupDir
		
		logFile = backupDir:"log.txt"
		oswrite log to logFile
		
		fixMsg = "A log file has been written to:"
		fixMsg := "|":logFile
		msg(@window, fixMsg)

	end else
		msg(@window, "There's nothing to fix!")
	end
return

clearResults:
	resultAry = ''
	call set_property(resultTbl,'ARRAY',resultAry)
return

createBkupDir:
	backupRoot = dataDir:"Backup\"
	backupDir = backupRoot:dateStamp:"\"

	call utility('MAKEDIR',backupRoot)
	call utility('MAKEDIR',backupDir)
return

revfiles:
	*the following code has been borrowed from DR_REVFILES
	*and modified to use the current data folder

	default_dir = '..\HEALTHY'

	status() = 0

	if len(dataDir) = 0 then
		datavolError = "Cannot determine the current DB path!"
		msg(@window, datavolError)
		return
	end

	bOk = 0
	call set_status(0)
	call name_volume(dataDir,date():time())
	call set_status(0)
	call alias_table(dataDir,'SYSPROG','REVMEDIA','MEDIA_TEMP')
	if not(get_status()) then
		open 'MEDIA_TEMP' to f.revmedia then bOk = 1
	end
	if not(bOk) then
		call set_status(0);
		call msg(@window,quote(dataDir):' is not a valid OI volume location')
		return
	end

	OSFileList = ''
	InitDir dataDir:'\*.LK'
	loop
		temp = dirlist()
	while len(temp)
		OSFileList<-1> = temp
	repeat
	InitDir dataDir:'\*.OV'
	loop
		temp = dirlist()
	while len(temp)
		OSFileList<-1> = temp
	repeat
	convert @lower.case:@fm to @upper.case:@vm in OSFileList

	SkipFiles = 'REVMEDIA':@vm:'REPOSIX':@vm:'REVREPOS':@vm:'REVDICT'
	spos = 0; fname = ''
	loop
		remove fname from SkipFiles at spos setting delim
		if len(fname) then
			locate fname:'.LK' in OSFileList setting pos then
				OSFileList = delete(OSFileList,1,pos,0)
			end
			locate fname:'.OV' in OSFileList setting pos then
				OSFileList = delete(OSFileList,1,pos,0)
			end
		end
	while delim do repeat

	clearselect
	call rlist('SELECT MEDIA_TEMP',5,'','','')
	done = 0; revfileArray = ''; missing = ''
	loop
		readnext id else done = 1
	until done
		readv revnum from f.revmedia,id,1 then
			convert @lower.case to @upper.case in revnum

			bMissing = 0
			locate revnum:'.LK' in OSFileList setting pos then
				OSFileList = delete(OSFileList,1,pos,0)
			end else
				bMissing = 1
			end
			locate revnum:'.OV' in OSFileList setting pos then
				OSFileList = delete(OSFileList,1,pos,0)
			end else
				bMissing = 1
			end

			size = dir(dataDir:'\':revnum:'.LK')<1> + dir(dataDir:'\':revnum:'.OV')<1>
			tablename = id[1,'*']
			appname = id[col2()+1,len(id)]
			line = appname:@vm:tablename:@vm:revnum:@vm:oconv(size,'MD0,')
			locate line in revfileArray by 'AL' using @fm setting pos else null
			revfileArray = insert(revfileArray,pos,0,0,line)
			missing = insert(missing,pos,0,0,bMissing)
		end 
	repeat

	call set_status(0)
	call detach_table('MEDIA_TEMP')
return
