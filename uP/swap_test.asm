.include "m103def.inc"
.include "macros.asm"
.include "definitions.asm"

.macro	INC_BCD
	mov	w,	@0
	andi	w,	0x0f
	cpi	w,	9
	mov	w,	@0
	brlo	_n10
	subi	w,	-6
_n10:	inc	w
	cpi	w,	(@1)+1
	brlo	_done
	clr	w
_done:	mov	@0,	w
.endmacro

.macro	DEC_BCD
	mov	w,	@0
	andi	w,	0x0f
	cpi	w,	1
	mov	w,	@0
	brge	_n10
	subi	w,	6
_n10:	dec	w
	cpi	w,	0
	brge	_done
	ldi	w,	@1
_done:	mov	@0,	w
.endmacro

.org	0
	jmp	reset

.org	0x30
.include "lcd.asm"

reset:	
	LDSP	RAMEND			; Load Stack Pointer (SP)
;	sbi	DDRE,SPEAKER		; make speaker output
;	OUTI	DDRB,	0xf8		; make LED outputs
	
;	rcall	calendar_init
;	rcall	timer_init
;	rcall	LCD_init
	
;	OUTI	TIMSK,	(1<<TOIE0)+(1<<TOIE1)+(1<<TOIE2)
	;sei				; enable global interrupts

; === main program ===	
main:	ldi	a0,	0x00
	rcall	swp_h
	rjmp	main

; swaps the time in a0 to 24 or 12 mode
swp_hr:	; move to correct register
	mov	a0,	r6
	rcall	swp_h
	mov	r6,	w
	ret
	
swp_h:	; detect mode
	sbrc	a0,	7
	rjmp	swp12_2_24	
	
	tst	a0
	breq	AM_0
	cpi	a0,	0x12
	breq	PM_12
	cpi	a0,	0x13
	brge	PM_13
	
	; change mode to 12h, time unaffected
	mov	w,	a0
	ori	w,	(1<<7)
	rjmp	end_swap
	
	; recalculate time for 12h mode
PM_13:	subi	a0,	0x12
	mov	w,	a0
	andi	w,	0x0F
	cpi	w,	10
	brlo	PC+2
	subi	a0,	0x06
PM_12:	mov	w,	a0
	ori	w,	(1<<7)+(1<<5)
	rjmp	end_swap
	
AM_0:	ldi	w,	(1<<7)+0x12
	rjmp	end_swap
	
swp12_2_24:
	andi	a0,	0x3F
	mov	w,	a0
	cpi	a0,	0x12
	breq	_00
	cpi	a0,	0x32
	breq	_12
	sbrs	a0,	5
	; change mode to 24h, time unaffected
	rjmp	end_swap
	
	; recalculate time for 24h mode
	subi	a0,	0x0E
	mov	w,	a0
	andi	a0,	0x0F
	cpi	a0,	0x0A
	brlo	PC+2
	subi	w,	-0x06
	rjmp	end_swap
	
_00:	clr	w
	rjmp	end_swap
_12:	ldi	w,	0x12

	; new value in w
end_swap:
	ret