; file	clock.asm
.include "m103def.inc"			; include AVR port/bit definitions
.include "macros.asm"			; include macro definitions
.include "definitions.asm"		; include register/constant definitions

; === interrupt table ===
.org	0
	jmp	reset

.org	OVF0addr
	jmp	timer0_ov
.org	OVF1addr
	jmp	timer1_ov
.org	OVF2addr
	jmp	timer2_ov
	
.org	INT0addr
	jmp	ext_int0
.org	INT1addr
	jmp	ext_int1

.org	0x30

.include "string.asm"			; include string manipulation routines	
.include "lcd.asm"
.include "printf.asm"			; include formatted printing routines

; === interrupt service routines ===
ext_int0:
	reti
ext_int1:
	reti
timer0_ov:
	reti
timer1_ov:
	reti
timer2_ov:
	reti

; === initialisation (reset) ===
reset:	
	LDSP	RAMEND			; Load Stack Pointer (SP)
	sbi	DDRE,SPEAKER		; make speaker output
	
	rcall	LCD_init		; initialize LCD
	rcall	timer_init
	rcall	calendar_init
	
	OUTI	TIMSK,	(1<<TOIE0)+(1<<TOIE1)+(1<<TOIE2)
	OUTI	EIMSK,	0b00000011	; Enable extern interrupts
	;OUTI	DDRB,	0xff
	;sei				; Enable global interrupts

; === main program ===
main:
;	call	cal_gettd
	call	disp_show_time2
	WAIT_MS	40
	rjmp	main

; === subroutines ===
timer_init:
	OUTI	ASSR,	(1<<AS0)	; clock from TOSC1 (external)
	OUTI	TCCR0,	2		; CSxx=2 CK/8	
	OUTI	TCCR1B,	2		; CSxx=2 CK/8
	OUTI	TCCR2,	3		; CSxx=3 CK/64
	ret

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

swap_1224:
	; get hour and check mode
	ldi	a0,	0x85
	call	cal_putc
	call	cal_getc
	sbrc	a0,	7
	rjmp	swp12_2_24	
	
	tst	a0
	breq	PM_0
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
	mov	w,	a0
	ori	w,	(1<<7)+(1<<5)
	rjmp	end_swap
	
PM_0:	ldi	w,	(1<<7)+(1<<5)+0x12
	rjmp	end_swap
	
swp12_2_24:
	andi	a0,	0x3F
	mov	w,	a0
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
	cpi	w,	0x24
	brne	end_swap
	clr	w

	; write new value (in w) to calendar
end_swap:
	ldi	a0,	0x84
	call	cal_putc
	mov	a0,	w
	call	cal_putc
	ret

disp_show_time2:
	call	LCD_clear
	call	LCD_home
	
	sbi	PORT_CAL, CE
	jmp	next
next:	ldi	a0, 	0x81
	call	cal_putc
	call	cal_getc
	cbi	PORT_CAL, CE
	;out	PORTB,	a0
	mov	a1,	a0
	swap	a0

	andi	a0,	0x07
	subi	a0,	-'0'
	call	LCD_putc
	ldi	a0,	'0'
	andi	a1,	0x0f
	add	a0,	a1
	call	LCD_putc
	ldi	a0,	':'
	call	LCD_putc
	
	
;	sbiw	zl,	6
;	ld	w,	z
;	sbrs	a0,	3
;	ret
;	ldi	w,	'A'
;	sbrc	a0,	1
;	ldi	w,	'P'
;	mov	a0,w
;	call	LCD_putc
;	ldi	a0,	'M'
;	call	LCD_putc
	ret

week_tb:
.db	"MON",0
.db	"TUE",0
.db	"WED",0
.db	"THU",0
.db	"FRI",0
.db	"SAT",0
.db	"SUN",0

disp_show_date:
	call	LCD_lf
	pop	xh
	pop	xl
	ldi	zl,	low(week_tb*2-1)
	ldi	zh,	high(week_tb*2-1)
	pop	a3
	pop	a2
	pop	w
	pop	w
	add	zl,	w
	clr	w
	adc	zh,	w
	ldi	a1,	3
loop:	lpm
	mov	a0,	r0
	call	LCD_putc
	inc	zl
;	sbic	SREG,	C
;	inc	zh
	dec	a1
	brge	loop
	ret

disp_show_chrono:
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
	
	
