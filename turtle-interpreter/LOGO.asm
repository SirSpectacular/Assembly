.286
.387
;====DATA SEGMENT===========================================
data segment

ParserBuffer	db 	256 dup(0)
ArgSizes		db	128	dup(?)						;sizes of parrsed arguments
ArgQuantity		db	0								;quantity of parrsed arguments

Buffer			db	16384 dup(?)					;data from input file is 

InputName		dw	?
InputHandle		dw	?

CurrentX		dw	160
CurrentY		dw	100
CurrentAngle	dw	0

CurrentColor	db	15
PenStatus		db	0

OneDegree		dw	180

Error00			db "You didnt parse any arguments", '$'
Error01			db "You parsed too many argumnts", '$'
Error02			db "Couldnt open input file", '$'
Error03			db "Was unable to read from file", '$'
Error04			db "Unsupported move", '$'
Error05			db "Couldnt get operator", '$'
Error06			db "Couldnt close input file", '$'

data ends

;====STACK SEGMENT===========================================
stackseg segment stack
				dw	256 dup(?)
stacktop 		dw	?
stackseg ends
;====MACROS==================================================
writeMsg macro  arg1
		MOV		ax, seg data
		MOV		ds, ax
		MOV		dx, offset arg1
		
		MOV		ah,	9						;print string function
		INT		21h
		
		MOV		ah, 4ch 					;return to DOS
		INT		21h
endm
;====CODE SEGMENT============================================
code segment
start:	
		MOV		ax, seg stackseg			;initialize stack
		MOV		ss, ax
		MOV		sp, offset stacktop
		
		CALL parser							;sends CMD line input to Buffer, removes white spaces
		CALL interpreter					;verify and adjust arguments so they are easy to use
		CALL logo

EndOfProgram:		

		MOV		ah, 4ch 					;return to DOS
		INT		21h
;====INTERNAL PROCEDURES=====================================
;############################################################
parser proc;-------------------------------------------------
		PUSH	ax
		PUSH	bp
		PUSH	si
		PUSH	di
		PUSH	cx
		
		MOV 	ax, seg data				;insert adress of data segment in es
		MOV 	es, ax
		
		MOV		ah, 62h						;insert adress of PSP segment in ds
		INT		21h
		
		XOR		bp, bp
		MOV 	di, offset ParserBuffer
		MOV		si, 81h						;offset 81h is where PSP buffer begins
		
		MOV 	cl, ds:[80h]				;save lenght of PSP buffer (which is stored in offset 80h oF PSP) in counter
		XOR		ch, ch		
		
		MOV		ax, 0
		CMP		cl, 0						;in case lenght is equal to 0, return error msg no. 0 (no aguments parsed)
		JNE		Parse
		writeMsg Error00
Parse:	
				CALL	eatwhite					;skip neighboring blank signs, stop whenever any other sign occures
				CALL	eatblack					;store other neighboring signs, stop whenever blank sign occures
		
				CMP		cl, 0
				JNE		Parse						;repeat until there are no signs left (cl is reduced inside of functions eatwhite and eatblack)
		
		MOV		ax, seg data				;from now on PSP won't be useful, so ds will contain adress of data segment
		MOV		ds, ax
		
		POP		cx
		POP		di
		POP		si
		POP		bp
		POP		ax
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
		
				MOVSB								;PSP -> ParserBuffer si++ di++
				INC		byte ptr es:ArgSizes[bp]	;increment size od current argument
		
				LOOP	eatblack
EndEatBlack:
		INC		di							;make NULL space between arguments
		INC		bp							;consider next argument
		INC		es:[ArgQuantity]			;increment quantity of arguments
		RET
eatblack endp;-----------------------------------------------
;############################################################
interpreter proc;--------------------------------------------
		CMP		byte ptr ds:ArgQuantity, 1
		JE		EndCheckingQuantity	
		
		writeMsg Error01
EndCheckingQuantity:
		MOV		ax, offset ParserBuffer
		MOV		ds:InputName, ax
		RET
interpreter endp;--------------------------------------------
;############################################################
logo proc;---------------------------------------------------
		
		CALL	openfile
		CALL	initgraphmode
		CALL	initfpu
ExecuteInput:
			CALL	readfile
			CMP		cx, 0
			JE		CleanUp
			CALL	getcommand
			
			JMP 	ExecuteInput
CleanUp:	
		CALL	closefile
		
		MOV		ah, 0
		INT		16h
		
		XOR		ah, ah
		MOV		al, 03h
		INT		10h
		
		RET
logo endp;---------------------------------------------------
openfile proc;-----------------------------------------------
		PUSH	ax
		PUSH	dx
		MOV		ah, 3Dh					;open file function
		MOV		al, 0					;read only
		MOV		dx, ds:InputName		;offset of the InputFile name ASCIIZ string
		INT		21h						;excute commands above		
		JNC		EndOpenInput			;CF = 0 -> success

		writeMsg Error02
EndOpenInput:
		MOV		ds:InputHandle, ax		;save file handle
		POP		dx
		POP		ax
		RET
openfile endp;-----------------------------------------------
initfpu proc;------------------------------------------------
		FINIT
		FLDPI
		FILD	word ptr ds:CurrentY
		FILD	word ptr ds:CurrentX
		
		RET
initfpu endp;------------------------------------------------
initgraphmode proc;------------------------------------------
		PUSH	ax
		XOR		ah, ah
		MOV		al, 13h
		INT		10h
		
		MOV		ax, 0A000h
		MOV		es, ax
		POP		ax
		RET
initgraphmode endp;------------------------------------------
;|	Gets: InputHandler										|
;|	Does: Puts up to 16 kB of data from file to Buffer		|
;|	Returns: cx - amount of read signs, bx := 0				|
readfile proc;-----------------------------------------------
		PUSH	ax
		PUSH	dx
		MOV		ah, 3Fh					;read file function
		MOV		bx, ds:InputHandle		;read fom InputFile
		MOV		cx, 16384				;16kB
		MOV		dx, offset Buffer		;write to Buffer
		INT		21h						;execute commands above
		JNC		EndReadFile				;CF = 0 -> success
		
		XOR		ah, ah
		MOV		al, 03h
		INT		10h
		
		writeMsg Error03				;CF = 1 -> return error msg
EndReadFile:
		XOR		bx, bx
		MOV		cx ,ax
		POP		dx
		POP		ax
		RET
readfile endp;-----------------------------------------------
getcommand proc;---------------------------------------------
		CMP		bx, cx
		JNE		KeepGettingCMD
		CALL	readfile
		CMP		cx, 0
		JE		End_getcommand
KeepGettingCMD:
		CMP		byte ptr ds:Buffer[bx], ' '
		JLE		Space
		CMP		byte ptr ds:Buffer[bx], 'm'
		JE		ModeM
		CMP		byte ptr ds:Buffer[bx], 'r'
		JE		ModeR
		CMP		byte ptr ds:Buffer[bx], 'c'
		JE		ModeC
		CMP		byte ptr ds:Buffer[bx], 'u'
		JE		ModeU
		CMP		byte ptr ds:Buffer[bx], 'd'
		JE		ModeD
		
		XOR		ah, ah
		MOV		al, 03h
		INT		10h
		
		writeMsg Error04	
ModeM:
		INC		bx
		CALL	getoperator
		CALL	move
		JMP		getcommand
ModeR:
		INC		bx
		CALL	getoperator
		CALL	rotate
		JMP		getcommand
ModeC:
		INC		bx
		CALL	getoperator
		MOV		ds:CurrentColor, al
		JMP		getcommand
ModeU:
		INC		bx
		MOV		byte ptr ds:PenStatus, 1
		JMP		getcommand
ModeD:
		INC		bx
		MOV		byte ptr ds:PenStatus, 0
		JMP		getcommand
Space:
		INC		bx
		JMP		getcommand

End_getcommand:
		
		RET
		
getcommand endp;---------------------------------------------
getoperator proc;--------------------------------------------
		PUSH	di
		PUSH	dx
		XOR		ax, ax
		MOV		di, 10
NextDigit:	
		CMP		bx, cx
		JNE		KeepGettingOp
		
		CALL	readfile
		CMP		cx, 0
		JE		CheckOperator
KeepGettingOp:		

		CMP		byte ptr ds:Buffer[bx], ' '
		JLE		JustINCbx
		CMP		byte ptr ds:Buffer[bx], '0'
		JL		CheckOperator
		CMP		byte ptr ds:Buffer[bx], '9'
		JG		CheckOperator

		XOR		dx, dx
		MUL		di
		MOV		dl, ds:Buffer[bx]
		SUB		dl, 48
		ADD		ax, dx
		XOR		dx, dx
JustINCbx:
		INC		bx
		JMP		NextDigit

CheckOperator:
		CMP		ax, 0
		JNE		CorrectOperator
		
		XOR		ah, ah
		MOV		al, 03h
		INT		10h
		
		writeMsg	Error05
CorrectOperator:
		POP		dx
		POP		di
		RET		
getoperator endp;--------------------------------------------	
move proc;---------------------------------------------------
		PUSH	cx
		MOV		cx, ax
		
		FILD	word ptr ds:CurrentAngle;st(0): CurrentAngle, st(1): CurrentX, st(2): CurrentY, st(3): Pi
		FIDIV	word ptr ds:OneDegree	;st(0): CurrentAngle / 180, st(1): CurrentX, st(2): CurrentY, st(3): Pi
		FMUL	st(0), st(3)			;st(0): CurrentAngle / 180 * Pi, st(1): CurrentX, st(2): CurrentY, st(3): Pi
		FSINCOS							;st(0): CurrentAngle / 180 * Pi,st(1): CurrentAngle / 180 * Pi, st(2): CurrentX, st(3): CurrentY, st(4): Pi
		
		CALL	drawpixel
NextPosition:

		FADD 	st(2), st(0)			;st(0): Cos(CurrentAngle), st(1): Sin(CurrentAngle), st(2): CurrentX + cos, st(3): CurrentY, st(4): Pi
		FXCH							;st(0): Sin(CurrentAngle), st(1): Cos(CurrentAngle), st(2): CurrentX + cos, st(3): CurrentY, st(4): Pi
		FADD 	st(3),	st(0)			;st(0): Sin(CurrentAngle), st(1): Cos(CurrentAngle), st(2): CurrentX + cos, st(3): CurrentY + sin, st(4): Pi
		FXCH							;st(0): Cos(CurrentAngle), st(1): Sin(CurrentAngle), st(2): CurrentX + cos, st(3): CurrentY + sin, st(4): Pi
		
		FLD 	st(2)					;st(0): CurrentX + cos, st(1): Sin(CurrentAngle), st(2): Cos(CurrentAngle), st(3): CurrentX + cos, st(4): CurrentY + sin, st(5): Pi
		FRNDINT							;st(0): CurrentX INT, st(1): Cos(CurrentAngle), st(2): Sin(CurrentAngle), st(3): CurrentX + cos, st(4): CurrentY + sin, st(5): Pi
		FISTP 	word ptr ds:CurrentX	;st(0): Cos(CurrentAngle), st(1): Sin(CurrentAngle), st(2): CurrentX + cos, st(3): CurrentY + sin, st(4): Pi
		
		FLD 	st(3)					;st(0): CurrentY + sin, st(1): Sin(CurrentAngle), st(2): Cos(CurrentAngle), st(3): CurrentX + cos, st(4): CurrentY + sin, st(5): Pi
		FRNDINT							;st(0): CurrentY INT, st(1): Cos(CurrentAngle), st(2): Sin(CurrentAngle), st(3): CurrentX + cos, st(4): CurrentY + sin, st(5): Pi
		FISTP 	word ptr ds:CurrentY	;st(0): Cos(CurrentAngle), st(1): Sin(CurrentAngle), st(2): CurrentX + cos, st(3): CurrentY + sin, st(4): Pi
		
		CALL	drawpixel
		
		LOOP	NextPosition
		FSTP 	st(0)
		FSTP	st(0)
		POP		cx
		RET
move endp;---------------------------------------------------
drawpixel proc;----------------------------------------------
		PUSH	ax
		PUSH	bx
		
		CMP		ds:PenStatus, 1
		JE		DontDraw
		CMP		word ptr ds:CurrentX, 319
		JG		DontDraw
		CMP		word ptr ds:CurrentX, 0
		JL		DontDraw
		CMP		word ptr ds:CurrentY, 199
		JG		DontDraw
		CMP		word ptr ds:CurrentY, 0
		JL		DontDraw
		
		MOV		ax, ds:CurrentY
		MOV		bx, ax
		SHL		bx, 8
		SHL		ax, 6
		ADD		bx, ax
		ADD		bx,	ds:CurrentX
		MOV		al, ds:CurrentColor
		MOV		es:[bx], al
DontDraw:
		POP		bx
		POP		ax
		RET
drawpixel endp;----------------------------------------------
rotate proc;-------------------------------------------------
		PUSH	dx
		PUSH	bp
		ADD		ds:CurrentAngle, ax
		CMP		ds:CurrentAngle, 360
		JL		Periods
		MOV		ax, ds:CurrentAngle
		MOV		bp, 360
		XOR		dx, dx
		DIV		bp
		MOV		ds:CurrentAngle, dx
Periods:
		POP		bp
		POP		dx
		RET
rotate endp;-------------------------------------------------
closefile proc;----------------------------------------------
		PUSH	ax
		PUSH	bx
		MOV		ah, 3Eh					;close file function
		MOV		bx, ds:InputHandle		;close InputFile
		INT		21h						;execute commands above
		JNC		EndCloseFile			;CF = 0 -> success
		
		writeMsg Error06				;CF = 1 -> return error msg
EndCloseFile:
		POP		bx
		POP		ax
		RET
closefile endp;---------------------------------------------

code ends
end start