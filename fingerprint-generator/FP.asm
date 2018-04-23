.286
;====DATA SEGMENT===========================================
data segment

Buffer			db	255 dup(?)						;output of parser function, converted to string. Structure: <arg1><arg2>...<argn>$$$$$...
ArgSizes		db	128	dup(?)						;sizes of parrsed arguments
ArgQuantity		db	0								;quantity of parrsed arguments

Hex				db	16 dup(?)						;array of moves converted from buffer into binary system
CurrentPos		dw	76								;says where bishop is now 
BookOfVisits	db  153 dup(0)						;stores each cell's visit counter
VisitMarks		db	' ','.','o','+','=','*','B','O'	;graphical marks used to inform how many times bishop visited paricullar cell
				db	'X','@','%','&','#','/','^'
				
FParray			db	"+---[RSA  1024]---+",10,13		;size of array is 21x11, from which 17x9 is blank for later use
repeat 9
				db	"|                 |",10,13
endm
				db  "+-----------------+",10,13,'$'
				
ErrorTxt		db	"Unrecognised call",10,13,10,13
				db	"To run this program use following syntax: FP.EXE [MODE] [HEX]",10,13,10,13
				db  "From which:",10,13
				db	"MODE - number 0 or 1 - determines which mode you want to use",10,13
				db	"HEX - string of 32 numbers from range of 0-f(h) - determines the path of bishop",10,13,'$'

data ends

;====STACK SEGMENT===========================================
stackseg segment stack
				dw	256 dup(?)
stacktop 		dw	?
stackseg ends

;====CODE SEGMENT============================================
code segment
start:	
		MOV		ax, seg stackseg			;initialize stack
		MOV		ss, ax
		MOV		sp, offset stacktop
		
		CALL parser							;sends CMD line input to Buffer, removes white spaces
		CALL verifier						;checks if parsed arguments have correct syntax
		CALL stringtohex					;converts string of ASCII symbols into hexadecimal representations
		CALL fingerprint					;moves bishop around array using input string as a key
		CALL asciiart						;converts numbers into their Ascii-Art representations
		CALL filltab						;fills final array with Ascii-Art
		
		MOV		dx, offset FParray			;frint final tab
		MOV		ah, 9
		INT		21h
EndOfProgram:		
		MOV		ah, 4ch 					;return to DOS
		INT		21h
		
;====INTERNAL PROCEDURES=====================================
;############################################################
errormsg proc;-----------------------------------------------
		MOV		ax, seg data				;print erro msg
		MOV		ds, ax
		MOV 	dx, offset ErrorTxt
		MOV		ah,	9
		INT		21h
		
		MOV		ah, 4ch 					;return to DOS
		INT		21h
errormsg endp;-----------------------------------------------
;############################################################
parser proc;-------------------------------------------------		
		PUSHA
		MOV 	ax, seg data				;insert adress of data segment in es
		MOV 	es, ax
		
		MOV		ah, 62h						;insert adress of PSP segment in ds
		INT		21h
		
		MOV		bp, offset ArgSizes
		MOV 	di, offset Buffer
		MOV		si, 81h						;offset 81h is where PSP buffer begins
		
		MOV 	cl, ds:[80h]				;save lenght of buffer (which is stored in offset 80h oF PSP) in counter
		XOR		ch, ch						
		
		CMP		cl, 0						;in case lenght is equal to 0, return error msg
		JE		errormsg

Parse:	
				CALL	eatwhite					;skip neighboring blank signs, stop whenever any other sign occures
				CALL	eatblack					;store other neighboring signs, stop whenever blank sign occures
		
				CMP		cl, 0
				JNE		Parse						;repeat until there are no signs left (cl is reduced inside of functions eatwhite and eatblack)
		
		MOV		ax, seg data				;from now on PSP won't be useful, so ds will contain adress of data segment
		MOV		ds, ax
		POPA
		RET
parser endp;-------------------------------------------------
eatwhite proc;-----------------------------------------------
				CMP 	byte ptr ds:[si], ' '		;check if considered sign is white (in ASCII table all belowe "space" are white)
				JG		EndEatWhite					;if no, return

				INC		si							;if yes, skip it and repeat

				LOOP	eatwhite
EndEatWhite:								
		RET
eatwhite endp;-----------------------------------------------
eatblack proc;-----------------------------------------------
				CMP 	byte ptr ds:[si], ' '		;check if considered sign is "black" (in ASCII table all above "space" are black)
				JLE		EndEatBlack
		
				MOVSB								;PSP -> Buffer si++ di++
				INC		byte ptr es:[bp]			;increment size od current argument
		
				LOOP	eatblack
EndEatBlack:
		INC		bp							;consider next argument
		INC		es:[ArgQuantity]			;increment quantity of arguments
		RET
eatblack endp;-----------------------------------------------
;############################################################
verifier proc;-----------------------------------------------	
		PUSHA
		CMP		ds:[ArgQuantity], 2			;check if quantity of arguments is correct (2)
		JNE		errormsg
		;-----
		XOR		bx, bx						;following part of verifier checks if sizes of particular arguments are correct 
		
		CMP		ds:ArgSizes[bx], 1			;first argument (1)
		JNE		errormsg
		
		INC		bx							;secound argument (32)
		CMP		ds:ArgSizes[bx], 32
		JNE		errormsg
		;-----
		XOR		bx, bx						;following part of verfier checks if parsed characters are correct (numbers represents their postions in ASCII table)
		
		CMP		ds:Buffer[bx], '0'			;first argument ([48(0), 49(1)])
		JL		errormsg
		CMP		ds:Buffer[bx], '1'
		JG		errormsg
											;secound argument ([48(0), 57(9)]u[97(a), 102(b)])
		MOV		cx, 32						;counter refers to lenght of secound argument
CheckIntervals:
				INC		bx
		
				CMP		ds:Buffer[bx], '0'			;following signs belongs to secound argument and have to be placed somewhere in range of one of 2 intervals
				JL		errormsg
				CMP		ds:Buffer[bx], '9'
				JG		NextInterval
				JMP		End_CheckIntervals
NextInterval:
				CMP		ds:Buffer[bx], 'a'
				JL		errormsg
				CMP		ds:Buffer[bx], 'f'
				JG		errormsg
End_CheckIntervals:
				LOOP	CheckIntervals				;consider next sign	
		POPA
		RET
verifier endp;-----------------------------------------------
;############################################################
stringtohex proc;--------------------------------------------
		PUSHA
		MOV		si, offset Buffer			;Buffer will be source
		INC		si							;secound argument starts from secound character of Buffer
		MOV		di, offset Hex				;and its conversion will be stored in Hex
		MOV		dl, 16						;later in this function dl will be used as operator of division
		MOV		cx, 16						;there are 16 bytes in hex, each byte will be defined by 2 numbers extracted from buffer
NextNumber:
				MOV		al, ds:[si]					;extract more significent number
				CBW
				CMP		byte ptr ds:[si], '9'		;check if it's regular decimal number or letter (commonly used to represent numbers from range of 10 to 15 in hexadecimal system)
				JLE		HighIsNum					
HighIsLetter:
				SUB		al, 87						;if its letter substract 87 from it, to convert ASCII sign into number represented by it
				MUL		dl							;multiplication is important, it places number in correct place around Hex
				MOV		ds:[di], al
				JMP		NextSign
HighIsNum:
				SUB		al, 48						;if its number substract 48 from it, to convert ASCII sign into number represented by it
				MUL		dl							;multiplication is important, it places number in correct place around HEx
				MOV		ds:[di], al				
NextSign:
				INC		si							;consider next number
				
				MOV		al, ds:[si]					;everything similar to first number, just without multiplications
				CMP		byte ptr ds:[si], '9'		
				JLE		LowIsNum
LowIsLetter:
				SUB		al, 87
				ADD		ds:[di], al
				JMP		EndOfByte
LowIsNum:
				SUB		al, 48
				ADD		ds:[di], al
EndOfByte:
				INC		si							;consider next number and also next byte
				INC		di
				LOOP	NextNumber
		POPA
		RET
stringtohex endp;--------------------------------------------
;############################################################
fingerprint proc;--------------------------------------------
		PUSHA
		XOR		bx, bx				;bx is index register to move around HEX array, moves are stored in hexadecimal numbers, which can be easily converted into binary code
		MOV		cx, 16				;there are 16 numbers in hex, reading begins from the most significent byte
ExtractMoves:
				PUSH	cx
				MOV		al, ds:Hex[bx]				;insert number in al, for following division opertions
				MOV		cx, 4						;there are 4 moves in each byte, reading begins from the least significent bit
NextMove:
						XOR		ah, ah						;ax:=al, couldn't use CBW beocuse it's signed operation
						MOV		dl, 4						
						DIV		dl							;double bit shift, 2 bits goes to ah, rest remain in al
						CALL	movebishop					;using ah value move bishop, save his new position and increment visit counter
						LOOP	NextMove
		
				INC		bx
				POP		cx
				LOOP	ExtractMoves
		POPA
		RET
fingerprint endp;--------------------------------------------	
movebishop proc;---------------------------------------------
		PUSH	ax
		PUSH	bx
		MOV		al, ah						;insert number in al, for following division opertions
		CBW									;ax:=al
			
		SHR		al, 1						;extract bit from LSB to determine next horizontal move
		JC		SkipLeft					;Jump if CF is 1	
		CALL	moveleft					;$$$ H SHIFT FUNCTIONS $$$ - Its purpose is to change and save bishop's position in horizontal axis
		JMP		SkipRight
SkipLeft:
		CALL 	moveright					;$$$ H SHIFT FUNCTIONS $$$
SkipRight:

		SHR		al, 1						;extract remaining bit to determine next vertrical move
		JC		SkipUp						;Jump if CF is 1	
		CALL	moveup						;$$$ V SHIFT FUNCTIONS $$$ - Its purpose is to change and save bishop's position in vertrical axis
		JMP		SkipDown
SkipUp:
		CALL	movedown					;$$$ V SHIFT FUNCTIONS $$$
SkipDown:

		MOV		bx, ds:CurrentPos			;after executing full move sequence increment visit counter for current position
		INC		ds:BookOfVisits[bx]
		
		POP		bx
		POP		ax
		RET
movebishop endp;---------------------------------------------
moveleft proc;----------$$$ H SHIFT FUNCTIONS $$$------------
		PUSH	ax
		MOV		ax, ds:[CurrentPos]
		
		MOV		dl, 17						;divide current position by 17 to determine if bishop is touching the left side of table
		DIV		dl
		CMP 	ah, 0						;this is true only if rest of mentioned division is equal 0
		JE		WallLeft
		
		SUB		ds:[CurrentPos], 1			;if bishop is not touching wall move him left
		JMP		DontBounce1
WallLeft:
		CMP		ds:[Buffer], '0'			;if he's touching the wall consider MODE you are working in (first argument), if MODE = 0 dont move, if MODE = 1 bounce from the wall
		JE		DontBounce1
		ADD		ds:[CurrentPos], 1
DontBounce1:
		POP		ax
		RET
moveleft endp;-----------------------------------------------
moveright proc;----------$$$ H SHIFT FUNCTIONS $$$-----------
		PUSH	ax
		MOV		ax, ds:CurrentPos
		
		MOV		dl, 17						;divide current position by 17 to determine if bishop is touching the right side of table
		DIV		dl
		CMP 	ah, 16						;this is true only if rest of mentioned division is equal 16
		JE		WallRight
		
		ADD		ds:CurrentPos, 1			;if bishop is not touching wall move him right
		JMP		DontBounce2
WallRight:
		CMP		ds:Buffer, '0'			;if he's touching the wall consider MODE you are working in, bounce or don't move
		JE		DontBounce2
		SUB		ds:CurrentPos, 1
DontBounce2:
		POP		ax
		RET
moveright endp;----------------------------------------------
moveup proc;-----------$$$ V SHIFT FUNCTIONS $$$-------------
		PUSH	ax
		MOV		ax, ds:CurrentPos
		
		CMP		ax, 16						;check if bishop is touching the upper side of the table
		JLE		WallUp
		
		SUB		ds:CurrentPos, 17			;if bishop is not touching wall move him up
		JMP		DontBounce3
WallUp:
		CMP		ds:Buffer, '0'			;if he's touching the wall consider MODE you are working in, bounce or don't move
		JE		DontBounce3
		ADD		ds:CurrentPos, 17
DontBounce3:
		POP		ax
		RET
moveup endp;-------------------------------------------------
movedown proc;----------$$$ V SHIFT FUNCTIONS $$$------------
		PUSH	ax
		MOV		ax, ds:CurrentPos
		
		CMP		ax, 136						;check if bishop is touching the bottom side of the table
		JGE		WallDown
		
		ADD		ds:CurrentPos, 17 		;if bishop is not touching wall move him down
		JMP		DontBounce4
WallDown:
		CMP		ds:Buffer, '0'			;if he's touching the wall consider MODE you are working in, bounce or don't move
		JE		DontBounce4
		SUB		ds:CurrentPos, 17
DontBounce4:
		POP		ax
		RET
movedown endp;-----------------------------------------------
;############################################################
asciiart proc;-----------------------------------------------
		PUSHA
		XOR		bp, bp						;index register to move around BookOfVisits	
		MOV		cx, 153						;153 is the number of cells in the table
ConvertToArt:
				CMP		ds:BookOfVisits[bp], 14
				JG		ItsOver9000					;clear reference to DBZ
				
				XOR		bh, bh						;if visit counter is lower then 14
				MOV		bl, ds:BookOfVisits[bp]		;move current BookOfVisits cell value to bx so it can be used as index register
				MOV		al, ds:VisitMarks[bx]		;extract symbol depending on current BookOfVisits cell value
				MOV		ds:BookOfVisits[bp], al		;send to BookOfVisits exracted symbol
				JMP		End_ConvertToArt
ItsOver9000:
				MOV		ds:BookOfVisits[bp], '^'	;there are no unique symbols for numbers highier then 14, they all get '^' symbol
End_ConvertToArt:
				INC		bp
				LOOP	ConvertToArt
		
		MOV		bx, ds:[CurrentPos]					
		MOV		ds:BookOfVisits[76], 'S'	;mark starting position as S, and final position as E
		MOV		ds:BookOfVisits[bx], 'E'
		POPA
		RET
asciiart endp;-----------------------------------------------
filltab proc;------------------------------------------------
		PUSHA
		MOV		si, offset BookOfVisits
		MOV		di, offset FParray
		ADD		di, 22						;skip first row, filled with strucural symbols
		MOV		cx, 9						;there are 9 rows
NextLine:
				PUSH	cx							;inner loop, there are 17 cells in a row
				MOV		cx, 17
NextCell:
						MOVSB								;BookOfVisits -> FParray si++ di++
						LOOP	NextCell

				ADD		di, 4						;after completing a row skip structural symbols and consider next one
				POP		cx
				LOOP 	NextLine
		POPA
		RET
filltab endp;------------------------------------------------
code ends
end start