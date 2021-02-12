compile function DECRYPTPWORD(password)

	decimal = invert(password)

	perm = ''
	answer = ''

	gosub getPerm
	gosub verifyPerm
	gosub removeInvalid
	gosub convertPerm
	gosub formatAnswer

return answer


getPerm:
	* get each possible decimal permutation
	* by adding 60 to 1, 2 & 3 digit(s) in pos 1, 5 & 10

	permCnt = 0

	for x = 3 to 0 step -1
		for y = 3 to 0 step -1
			for z = 3 to 0 step -1

				tempDecimal = decimal

				if (x=1 or y=1 or z=1) and (decimal[1,x]="-" or decimal[5,y]="-" or decimal[10,z]="-") else
					changeOne = decimal[10,z] + 60
					changeTwo = decimal[5,y] + 60
					changeThr = decimal[1,x] + 60

					* zeros disappear
					if len(changeOne) = 1 then changeOne = '0':changeOne
					if len(changeTwo) = 1 then changeTwo = '0':changeTwo
					if len(changeThr) = 1 then changeThr = '0':changeThr

					tempDecimal[10,z] = changeOne
					tempDecimal[5,y] = changeTwo
					tempDecimal[1,x] = changeThr

					permCnt += 1
					perm<permCnt> = tempDecimal
				end

			next
		next
	next
return perm


verifyPerm:
	* check each permutation to see if all digits can be converted to ascii
	* if not prefix the permutation with x

	permCnt = dcount(perm, @fm)

	for w = 1 to permCnt
		tempPerm = perm<w>
		tempPermLen = len(tempPerm)

		for v = 1 to tempPermLen
			digits = tempPerm[v,2]
			gosub validate

			if result = 'fail' then
				digits = tempPerm[v,3]
				gosub validate

				if result = 'fail' then
					perm<w> = 'x':perm<w>
					v = tempPermLen
				end else
					v += 2
				end

			end else
				v += 1
			end
		next

	next
return perm


removeInvalid:
	* remove invalid permutations

	permCnt = dcount(perm, @fm)

	for u = 1 to permCnt
		tempPerm = perm<u>

		if tempPerm[1,1] = 'x' then
			perm = delete(perm, u, 0, 0)
			permCnt = dcount(perm, @fm)
			u -= 1
		end
	next
return perm


convertPerm:
	* convert each valid permutation to ascii

	permCnt = dcount(perm, @fm)

	for s = 1 to permCnt
		tempAnswer = ''
		tempPerm = perm<s>
		tempPermLen = len(tempPerm)

		for t = 1 to tempPermLen
			digits = tempPerm[t,2]
			gosub validate

			if result = 'fail' then
				digits = tempPerm[t,3]
				t += 2
			end else
				t += 1
			end

			tempAnswer := char(digits)
		next

		answer<s> = tempAnswer
	next
return answer


formatAnswer:
	* make the output pretty

	swap @fm with \0D0A\ in answer
	tempAnswer = answer

	answer = "Possible decryption(s):":\0D0A\
	answer := \0D0A\
	answer := tempAnswer
return answer


validate:
	* determine whether the given digits are common ascii chars
	* returns pass or fail using ascii chart below

	/* 
	ASCII codes
	32        = Space
	33  - 47  = Special Chars
	48  - 57  = Numbers (0-9)
	58  - 64  = Special Chars
	65  - 90  = Letters (A-Z)
	91  - 96  = Special Chars
	97  - 122 = Letters (a-z)
	123 - 126 = Special Chars
	*/

	result = ''

	if (digits > 32) and (digits < 126) then
		result = 'pass'
	end else
		result = 'fail'
	end
return result
