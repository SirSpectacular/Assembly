.286
;====DATA SEGMENT===========================================
data segment

ParserBuffer	db 	256 dup(0)
ArgSizes		db	128	dup(?)						;sizes of parrsed arguments
ArgQuantity		db	0								;quantity of parrsed arguments

Buffer			db	16384 dup(?)					;data from input file is 

Mode			db	0
Key				dw	?
InputName		dw	?
OutputName		dw	?
InputHandle		dw	?
OutputHandle	dw	?

errormsg00		db "You didn't parse any arguments                                 ",'$'
errormsg01		db "Too few arguments parsed to program                            ",'$'
errormsg02		db "Too many arguments parsed to program                           ",'$'
errormsg03		db "Unrecognized syntax                                            ",'$'
errormsg04		db "Program was unable to open input file                          ",'$'
errormsg05		db "Program was unable to open/creat output file                   ",'$'
errormsg06		db "Program was unable to read from input file                     ",'$'
errormsg07		db "Program was unable to write to output file                     ",'$'
errormsg08		db "Program was unable to close input file                         ",'$'
errormsg09		db "Program was unable to close output file                        ",'$'
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
		CALL interpreter					;verify and adjust arguments so they are easy to use
		CALL vigenere						;encrypt or decrypt given file

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
		JE		errormsg
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
		PUSH	ax
		PUSH	bx
		PUSH	bp
		PUSH	cx
		
		MOV		bx, offset ParserBuffer
		XOR		bp, bp
		
		MOV		ax, 1
		CMP		ds:ArgQuantity, 3			;check if quantity of arguments is correct (3-4)
		JL		errormsg					;write error msg no. 1 (too few arguments)
		JE		AdaptNames
		
		MOV		ax, 2
		CMP		ds:ArgQuantity, 4			
		JG		errormsg					;write error msg no. 2 (too many arguments)
		;-----
SetMode:
		MOV		ax, 3
		CMP		byte ptr ds:ArgSizes[bp], 2	;4 arguments parsed -> first is longer then 2 -> write error msg no. 3 (unrecognized syntax)
		JNE		errormsg

		CMP		word ptr ds:[bx], 642Dh 	; -d  4 arguments parsed -> first is not equal to -d -> write error msg no. 3
		JNE		errormsg
		MOV		ds:Mode, 1					;change Mode to "decryption"
		ADD		bx, 3							
		INC		bp	
		
AdaptNames: 
		MOV		ds:InputName, bx			;InputName offset
		ADD		bl, ds:ArgSizes[bp]
		INC		bx
		INC		bp
		
		MOV		ds:OutputName, bx			;OutputName offset
		ADD		bl, ds:ArgSizes[bp]
		INC		bx
		INC		bp
		
		MOV		ds:Key, bx					;Key offset
		ADD		bl, ds:ArgSizes[bp]
		INC		bx
		INC		bp
		
		POP		cx
		POP		bp
		POP		bx
		POP		ax
		RET
interpreter endp;--------------------------------------------
;############################################################
vigenere proc;-----------------------------------------------
		PUSH	ax
		PUSH	bx
		PUSH	bp
		PUSH	cx
		PUSH	dx
		
		CALL	openfiles
		CMP		byte ptr ds:Mode, 0
		JE		ConsiderNext
		CALL	invertkey
ConsiderNext:
				CALL 	read	
				CMP		ax, 0
				JE		EndVigenere				;input->buffer
				CALL	convert					;chars in buffer
				CALL	write					;buffor->output
				JMP		ConsiderNext			; as long as there are any chars left
EndVigenere:
		CALL 	closefiles
		
		POP		dx
		POP		cx
		POP		bp
		POP		bx
		POP		ax
		RET
vigenere endp;-----------------------------------------------
openfiles proc;----------------------------------------------
		MOV		ah, 3Dh					;open file function
		MOV		al, 0					;read only
		MOV		dx, ds:InputName		;offset of the InputFile name ASCIIZ string
		INT		21h						;excute commands above		
		JNC		EndOpenInput			;CF = 0 -> success

		MOV		ax, 4					;CF = 1 -> return error no.4
		CALL	errormsg				;"Was unable to open input file"
EndOpenInput:
		MOV		ds:InputHandle, ax		;save file handle
		
		MOV		ah, 3Dh					;open file function
		MOV		al, 1					;write only
		MOV		dx, ds:OutputName		;offset of the OutputFile name ASCIIZ string
		INT		21h						;execute commands above
		JNC		EndOpenOutput			;CF = 0 -> success
		
		MOV		ah, 3Ch					;CF = 1 -> create file function
		XOR		cl, cl					;no special attributes
		INT		21h						;execute commands above
		JNC		EndOpenOutput			;CF = 0 -> success
		
		MOV		ax, 5					;CF = 1 -> return error no.5
		CALL	errormsg				;"Was unable to open/creat output file"

EndOpenOutput:
		MOV		ds:OutputHandle, ax		;save file handle
		
		RET
openfiles endp;----------------------------------------------
invertkey proc;----------------------------------------------
		MOV		bx, ds:Key
		XOR		ch, ch
		MOV		cl, ds:ArgSizes[3]
InvertNextChar:
				MOV		ax, 256
				SUB		al, ds:[bx]
				MOV		ds:[bx], al
				INC		bx
				LOOP	InvertNextChar
		RET
invertkey endp;----------------------------------------------
read proc;----------------------------------------------
		MOV		ah, 3Fh					;read file function
		MOV		bx, ds:InputHandle		;read fom InputFile
		MOV		cx, 16384				;16kB
		MOV		dx, offset Buffer		;write to Buffer
		INT		21h						;execute commands above
		JNC		EndRead					;CF = 0 -> success

		MOV		ax, 6					;CF = 1 -> return error msg no. 6
		CALL 	errormsg				;"Was unable to read input file"
EndRead:
		RET
read endp;----------------------------------------------
convert proc;----------------------------------------------
		PUSH	ax
		MOV		cx, ax
		XOR		bx, bx
		MOV		bp, ds:Key
		
ConvertPortion:
				MOV		al, ds:[bp]				;add to Buffer KeyValue
				ADD		ds:Buffer[bx], al

				INC		bp						;next key sign
				INC		bx						;next buffer sign
				CMP		byte ptr ds:[bp], 0			
				JNE		DontResetKey
				MOV		bp, ds:Key				;if you reached the end of Key, return to its begining
DontResetKey:
				LOOP 	ConvertPortion
		POP		ax
		RET
convert endp;----------------------------------------------
write proc;----------------------------------------------
		MOV		cx, ax					;write to output file as many signs as you read from input file
		MOV		ah, 40h					;write to file function				
		MOV		bx, ds:OutputHandle		;write to OutputFile
		MOV		dx, offset Buffer		;read from Buffer
		INT		21h						;execute commands above
		JNC		EndWrite				;CF = 0 -> success
		
		MOV		ax, 7					;CF = 1 -> return error msg no. 7
		CALL	errormsg				;"Was unable to write to output file"
EndWrite:
		RET
write endp;----------------------------------------------
closefiles proc
		MOV		ah, 3Eh					;close file function
		MOV		bx, ds:InputHandle		;close InputFile
		INT		21h						;execute commands above
		JNC		EndCloseInput			;CF = 0 -> success
		
		MOV		ax, 8					;CF = 1 -> return error msg no. 8
		CALL	errormsg				;"Was unable to close InputFile"
EndCloseInput:
		MOV		ah, 3Eh					;close file function
		MOV		bx, ds:OutputHandle		;close OutputFile
		INT		21h						;execute commands above
		JNC		EndCloseOutput			;CF = 0 -> success
		
		
		MOV		ax, 9					;CF = 1 -> return error msg no. 9
		CALL	errormsg				;"Was unable to close OutputFile"
EndCloseOutput:
		RET
closefiles endp
;############################################################
errormsg proc;-----------------------------------------------
		PUSH	ax
		MOV		ax, seg data				;print error msg
		MOV		ds, ax
		MOV 	dx, offset errormsg00
		POP		ax
		
		MOV		bx, 64		
		MUL		bl
		ADD		dx, ax
		
		MOV		ah,	9						;print string function
		INT		21h
		
		MOV		ah, 4ch 					;return to DOS
		INT		21h
errormsg endp;-----------------------------------------------
code ends
end start