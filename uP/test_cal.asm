; file	test_cal.asm
.include "m103def.inc"			; include AVR port/bit definitions
.include "macros.asm"			; include macro definitions
.include "definitions.asm"		; include register/constant definitions

reset:	
	LDSP	RAMEND			; Load Stack Pointer (SP)
	sbi	DDRE,SPEAKER		; make speaker output
	
	rcall	calendar_init

	;OUTI	DDRB,	0xff
	
main:	sbi	PORT_CAL, CE
	jmp	next
next:	ldi	a0, 	0x81
	call	cal_putc
	call	cal_getc
	out	PORTB,	a0
	cbi	PORT_CAL, CE
	rjmp	main

calendar_init:
	; enable ports
	OUTI	DDR_CAL, (1<<CE)+(1<<C_CLK)
	
	; clear write protection
	sbi	PORT_CAL,	CE
	ldi	a0,	0x8E
	call	cal_putc
	clr	a0
	call	cal_putc
	cbi	PORT_CAL,	CE
	jmp	next1
	; start clock
next1:	sbi	PORT_CAL,	CE
	ldi	a0,	0x80
	call	cal_putc
	clr	a0
	call	cal_putc
	cbi	PORT_CAL,	CE
	jmp	next2
;	; set year to (20)12
;	ldi	a0,	0x8C
;	call	cal_putc
;	ldi	a0,	0x12
;	call	cal_putc
	; enable tickle charge
next2:	sbi	PORT_CAL,	CE
	ldi	a0,	0x90
	call	cal_putc
	ldi	a0,	0b10100110
	call	cal_putc
	cbi	PORT_CAL,	CE
	ret
	
cal_putc:
	sbi	DDR_CAL, C_DATA
	sec
pc_lp:	ror	a0
	C2P	PORT_CAL, C_DATA
	sbi	PORT_CAL, C_CLK
	nop
	nop
	nop
	cbi	PORT_CAL, C_CLK
	clc
	cpi	a0,1
	brne	pc_lp
	ret

cal_getc:
	cbi	DDR_CAL, C_DATA
	ldi	a0,0x80
gc_lp:	sbi	PORT_CAL, C_CLK
	nop
	nop
	nop
	P2C	PIN_CAL, C_DATA
	cbi	PORT_CAL, C_CLK
	ror	a0
	brcc	gc_lp
	ret