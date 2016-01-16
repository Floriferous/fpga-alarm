; file	string.asm
; copyright (c) 2000-2002 R.Holzer

strcpy:			; (x) <- (y) string copy
	ld	w,y+
	st	x+,w
	tst	w
	brne	strcpy
	ret
	
strldi:			; (x) <- (z) string load immediate
	lpm
	adiw	zl,1	; increment z
	st	x+,r0
	tst	r0
	brne	strldi
	ret

strncpy:		; (x) <-  n(y) string copy n chars
	ld	w,y+
	st	x+,w
	dec	a0
	brne	strncpy
	st	x+,a0	; terminate with zero
	ret

strend:			; advance x to end of string
	ld	w,x+
	tst	w
	brne	strend
	sbiw	xl,1	; pointing to NUL
	ret
	
strcat:			; (x)+(y) string concatenate
	rcall	strend	; advance x to end(x)
	rjmp	strcpy	; copy (y) to end(x)

strncat:		; (x)+n(y) string concatenate n	
	rcall	strend	; advance x to end(x)
	rjmp	strncpy	; copy n(y) to end(x)
	
strcmp:			; (x) > (y) string compare
	ld	w,x+
	ld	u,y+
	cp	w,u
	breq	PC+2
	ret		; strings are not equal (w!=w1)
	tst	w	; w==w1
	brne	strcmp
	ret		; strings are equal
	
strncmp:		;  (x) > (y)n string compare n
	ld	w,x+
	ld	u,y+
	dec	a0
	brne	PC+2
	ret		; n characters compared
	cp	w,u
	breq	PC+2
	ret		; strings are not equal
	tst	w
	brne	strncmp
	ret		; strings are equal
	
strchr:
	ld	w,x+
	cp	w,a0
	brne	PC+3
	ld	w,-x	; decrement x to point to char
	ret		; found char in (x), Z=1
	tst	w
	brne	strchr
	clz		; clear Z flag (Z=0)
	ret

strrchr:
	ld	w,x+
	cp	w,a0
	brne	strrchr_found
	tst	w
	brne	strrchr
	clz		; not found (Z=0)
	ret
strrchr_found:
	ld	w,x+	; find the end of string (x)
	tst	w
	brne	PC-2
	ld	w,-x	; find the position of (x)=char
	cp	w,a0
	brne	PC-2
	ret
	
strlen:			; returns the string length (x) in reg a
	ldi	a0,-1	
	ld	w,x+
	inc	a0
	tst	w
	brne	strlen+1
	ret

strinv:			; inverses string pointed by x
	PUSHY
	MOV2	yh,yl, xh,xl	; saveguard x in y
	clr	w
	ld	u,x+
	tst	u
	breq	_inv	
	push	u		; push the characters on the stack
	inc	w
	rjmp	PC-5	
_inv:	
	MOV2	xh,xl, yh,yl 	; point x to begin of string
	pop	u		; pop back the characters from the end
	st	x+,u
	dec	w
	brne	PC-3
	st	x+,w		; terminate with zero
	POPY
	ret