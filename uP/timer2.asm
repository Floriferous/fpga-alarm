
.include "m103def.inc"
.include "macros.asm"
.include "definitions.asm"


.org	0
	rjmp	reset
.org	OVF2addr
	rjmp	timer2_ov

.org	0x30

timer2_ov:
	in	_sreg,	SREG
	in	a0,	PORTB
	ldi	w,	0xff
	eor	a0,	w
	out	PORTE,	a0
	out	PORTB,	a0
	out	SREG,	_sreg
	reti

reset:

OUTI	TCCR2,	2
OUTI	TIMSK,	(1<<TOIE2)
ldi	w,	0xff
out	DDRE,	w
sbi	DDRB,	SPEAKER
sei

main:	nop
	nop
	rjmp	main