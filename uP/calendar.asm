; file	calendar.asm
; Florian Bienefelt; Beat Geissmann
; 2012-05-27

; === definitions ===
.equ	PORT_CAL= PORTB
.equ	DDR_CAL	= DDRB
.equ	PIN_CAL	= PINB
.equ	CE	= 0
.equ	C_CLK	= 1
.equ	C_DATA	= 2

; === macros ===
.macro	WRI_CAL	;adress, value
; writes immediate to specific adress in calendar
; register:
; mod: a0
	cli			; disable interrupts (timing)
	sbi	PORT_CAL, CE	; start communication
	ldi	a0,	@0	; write adress
	call	cal_putb
	ldi	a0,	@1	; write data
	call	cal_putb
	cbi	PORT_CAL, CE	; stop communication
	sei			; reenable interrupts
.endmacro

.macro	WR_CAL	;adress, value (reg except a0)
; writes register to specific adress in calendar
; register:
; in: reg except a0
; mod: a0
	cli			; disable interrupts (timing)
	sbi	PORT_CAL, CE	; start communication
	ldi	a0,	@0	; write adress
	call	cal_putb
	mov	a0,	@1	; write data
	call	cal_putb
	cbi	PORT_CAL, CE	; stop communication
	sei
.endmacro

.macro	RD_CAL 	;adress
; reads byte at specific adress in calendar
; register:
; out: a0
	cli			; disable interrupts (timing)
	sbi	PORT_CAL, CE	; start communication
	ldi	a0,	@0	; write adress
	call	cal_putb
	call	cal_getb	; read, result in a0
	cbi	PORT_CAL, CE	; stop communication
	sei
.endmacro

; === subroutines ===
calendar_init:
	; enable ports
	OUTI	DDR_CAL, (1<<CE)+(1<<C_CLK)

	; clear write protection
	WRI_CAL	0x8e,	0x00	

	; clear halt_clock if set
	; (MSB in sec register)
	; keep value of seconds
	RD_CAL	0x81
	andi	a0,	0x7f
	mov	w,	a0
	WR_CAL	0x80,	w

	; enable tickle charge (1 diode; 8kOhm)
	WRI_CAL	0x90,	0b10100110
	ret

cal_putb:
; serial communication to calendar
; in: a0 (modified)
	sbi	DDR_CAL, C_DATA		; bidir. data pin as output
	sec				; set carry to detect end
pc_lp:	ror	a0			; rotate LSB to carry -> shift out
	C2P	PORT_CAL, C_DATA	; write carry to PIN
	sbi	PORT_CAL, C_CLK		; clock->high
	nop				;   '
	nop				;   '
	nop				;   '
	cbi	PORT_CAL, C_CLK		; clock->low
	clc				
	cpi	a0,1			; finish if MSB has been sent
	brne	pc_lp
	ret

cal_getb:
; serial communication from calendar
; out: a0
	cbi	DDR_CAL, C_DATA		; bidir. data pin as input
	ldi	a0,0x80			; load a0 to detect end of transmission
gc_lp:	sbi	PORT_CAL, C_CLK		; clock->high
	P2C	PIN_CAL, C_DATA		; put received bit to carry
	nop
	nop
	cbi	PORT_CAL, C_CLK		; clock->low
	ror	a0			; shift in carry
	brcc	gc_lp			; detect end of transmission (carry set)
	ret