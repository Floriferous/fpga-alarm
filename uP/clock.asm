; file	clock.asm
; Florian Bienefelt; Beat Geissmann
; 2012-05-27
.include "m103def.inc"			; include AVR port/bit definitions
.include "macros.asm"			; include macro definitions
.include "definitions.asm"		; include register/constant definitions

; === definitions ===
; Flags in status register r10
.equ	ALARM	= 0
.equ	GAME	= 1
.equ	CHRONO	= 2

.equ	MAX_LEAP=30
; use some registers as cache
.def	alarm_m	= r8
.def	alarm_h	= r9
.def	state	= r10
.def	N_leap	= r11
.def	chr_100	= r12
.def	chr_s	= r13
.def	chr_m	= r14
.def	chr_h	= r15
.def	buf_b	= r25
; y points always to the byte after the last byte
; of the currently shown leap

; date and time use the same registers,
; since they are never used the same time
; the function disp chrono uses them too,
; since they are not used when the chrono
; 
.def	time_s	= r5
.def	time_m	= r4
.def	time_h	= r6
.def	dat_dm	= r5
.def	dat_m	= r6
.def	dat_y	= r7
.def	dat_dw	= r4

; === macros ===
.macro	INC_BCD ;reg, lower_lim, upper_lim
; increment register in BCD-mode between limits
; in: reg except a0
; out: same reg as input
; mod: w
	mov	w,	@0
	andi	w,	0x0f
	cpi	w,	9	; check for BCD overflow
	mov	w,	@0
	brlo	_n10
	subi	w,	-6	; add 6 to pass from 0x0a to 0x10
_n10:	inc	w		; increment
	cpi	w,	(@2)+1	; check for upper limit
	brlo	_done
	ldi	w,	@1	; load with lower limit if too high
_done:	mov	@0,	w
.endmacro

.macro	DEC_BCD	;reg, lower_lim, upper_lim
; decrement register in BCD-mode between limits
; register:
; in: reg except a0
; out: same reg as input
; mod: w
	mov	w,	@0
	andi	w,	0x0f
	cpi	w,	1	; check for BCD underflow
	mov	w,	@0
	brge	_n10
	subi	w,	6	; subtract 6 to pass from 0x10 to 0x0a
_n10:	dec	w		; decrement
	cpi	w,	@1	; check for the lower limit
	brge	_done
	ldi	w,	@2	; load with upper limit if too low
_done:	mov	@0,	w
.endmacro

.macro	BTN_BUF	;btn_reg, buffer, jump_adr
; tests if new button has been pressed since last check
; if true, corresponding bit is set in btn_reg
; otherwise relative jump to the given adress
; register:
; in: btn_reg, buffer
; mod: w
	in	@0,	BUTTON
	com	@0		; the buttons are active low
	mov	w,	@0	; save copy
	eor	@0,	@1	; check for actions (differences to buffer)
	mov	@1,	w	; safe current state to buffer
	and	@0,	w	; check if action was press, not release
	breq	@2		; branch if no btn pressed
.endmacro

.macro	DIV_W4	;higher byte, lower byte
; divide word by 4
	clc
	ror	@0
	ror	@1
	clc
	ror	@0
	ror	@1
.endmacro

.macro	MUL_W4	;higher byte, lower byte
; multiply word by 4
	clc
	rol	@1
	rol	@0
	clc
	rol	@1
	rol	@0
.endmacro

.macro SHOW_BCD ; BCD_reg, extractor1, extractor2
; modified: a0,a1,w
; out: LCD
	mov	a0,	@0	; copy for first digit
	mov	a1,	a0	; copy for second digit
	swap	a0		; extract first digit
	andi	a0,	@1
	subi	a0,	-'0'	; add ASCII offset
	call	LCD_putc	; print first digit
	andi	a1,	@2	; extract second digit
	ldi	a0,	'0'	; add AsCII offset
	add	a0,	a1
	call	LCD_putc	; print second digit
.endmacro

; === interrupt table ===
.org	0
	rjmp	reset

.org	OC1Aaddr
	rjmp	timer1_oc
.org	OVF2addr
	rjmp	timer2_ov
	
.org	INT0addr
	rjmp	ext_int0
.org	INT1addr
	rjmp	ext_int1

.dseg
.org	0x60
.byte	4*MAX_LEAP+1	; space for MAX_LEAP leaps at beginning of intern SRAM

.cseg
.org	0x30

.include "lcd.asm"
.include "calendar.asm"

; === interrupt service routines ===
ext_int0:
; btn start/stop of chrono
; in: buf_b, state, BUTTON
; out: TCCR1B, state, buf_b
; mod: _w, _u, _sreg
	in	_sreg,	SREG		; save SREG in r1
	mov	_w,	w		; safe working register in r17 (used in macros)
	BTN_BUF	_u,	buf_b,	i0_end	; detect falling edge on (active low) btn0
	sbrs	_u,	0
	rjmp	i0_end
	
	in	_u,	TCCR1B		; start / stop timer1
	ldi	w,	1
	eor	_u,	w
	out	TCCR1B,	_u
	ldi	w,	(1<<CHRONO)
	eor	state,	w		; toggle chrono state (running/stopped)
	
i0_end:	mov	w,	_w
	out	SREG,	_sreg
	reti

ext_int1:
; btn leap/reset of chrono
; copies current chrono time to memory if chrono is running,
; otherwise the chrono is reseted
; the interrupt might be interrupted
; in: buf_b, state, BUTTON, N_leap, chr_100, chr_s, chr_m, chr_h
; out: y, N_leap, SRAM
; mod but not used: _sreg
; used nut not mod: w,u
	in	_sreg,	SREG		; push SREG, w and u on stack
	push	_sreg
	push	w
	push	u
	OUTI	EIMSK,	0b00000001	; disable this interrupt
	sei				; reenable interrupts (long interrupt handling)
	BTN_BUF	u,	buf_b,	i1_end	; detect falling edge on (active low) btn1
	sbrs	u,	1
	rjmp	i1_end
	sbrs	state,	CHRONO		; add leap if chrono running
	rjmp	ch_res			; reset leaps if chrono halted
	
	ldi	w,	MAX_LEAP	; only save leap if still memory left
	cp	N_leap,	w
	brsh	i1_end
	inc	N_leap			; inc number of leaps and calculate adress
	mov	u,	N_leap		; of its place in memory
	ldi	yl,	low(0x60)
	ldi	yh,	high(0x60)
	lsl	u
	lsl	u
	add	yl,	u
	brcc	PC+2
	inc	yh
	st	y+,	chr_100
	st	y+,	chr_s
	st	y+,	chr_m
	st	y+,	chr_h

	rjmp	i1_end
	
ch_res:	clr	N_leap
	rcall	chrono_reset
i1_end:	cli				; disable interrupts for recreating the environment
	OUTI	EIMSK,	0b00000011	; reenable this interrupt
	pop	u
	pop	w
	pop	_sreg
	out	SREG,	_sreg
	reti

timer1_oc:
; increment chrono time by cs
; max val: 99h59m59s99cs
	in	_sreg,	SREG		; safe processor state in r1
	mov	_w,	w		; safe working register in r2 (used in macros)
	INC_BCD	chr_100, 0x00,	0x99	; increment counter
	tst	chr_100			; detect ofervlow (reg is clear)
	brne	t1_end
	INC_BCD	chr_s,	0x00,	0x59
	tst	chr_s
	brne	t1_end
	INC_BCD	chr_m,	0x00,	0x59
	tst	chr_m
	brne	t1_end
	INC_BCD	chr_h,	0x00,	0x99
t1_end:	mov	w,	_w
	out	SREG,	_sreg
	reti

timer2_ov:
	; toggle SPEAKER -> make sound (~1kHz)
	in	_sreg,	SREG
	
	in	_u,	PORTE
	ldi	_w,	(1<<SPEAKER)
	eor	_u,	_w
	out	PORTE,	_u
	
	out	SREG,	_sreg
	reti

; === initialisation (reset) ===
reset:	
	LDSP	RAMEND			; Load Stack Pointer (SP)

	clr	state			; clear alarm/chrono state
	
	call	calendar_init
	call	LCD_init
	call	chrono_reset
	call	alarm_init
	call	timer_init

	OUTI	TIMSK,	(1<<OCIE1A)	; enable chrono timer interrupt
	sei				; enable global interrupts
	
	sbi	DDRE,	SPEAKER		; make speaker output

	jmp	mode_clk

; === subroutines ===
alarm_init:
; clear minutes
; initialize avec current hour
	clr	alarm_m
	RD_CAL	0x85
	mov	alarm_h, a0
	ret

timer_init:
	; timer1
	OUTI	TCCR1A,	0x00		; disconnect timer1 from output
	OUTI	TCCR1B,	(1<<CTC1)	; CSxx=0 timer1 not started yet	CTC1=1
	OUTI	OCR1AH,	high(clock/100)	; fill compare register, high byte first
	OUTI	OCR1AL,	low(clock/100)	; 100 interrupts per second
	; timer2
	OUTI	TCCR2,	2		; CSxx=2 CK/8
	ret

chrono_reset:
	clr	N_leap
	clr	chr_100
	clr	chr_s
	clr	chr_m
	clr	chr_h
	ret
; use the same two macros but with different borders and registers
; use functions because skip command does not skip a whole macro
incs:	INC_BCD	time_s,	0x00,	0x59
	ret
decs:	DEC_BCD	time_s,	0x00,	0x59
	ret
incmin:	INC_BCD	time_m,	0x00,	0x59
	ret
decmin:	DEC_BCD	time_m,	0x00,	0x59
	ret

incm_a:	INC_BCD	alarm_m, 0x00,	0x59
	ret
decm_a:	DEC_BCD	alarm_m, 0x00,	0x59
	ret

incdm:	INC_BCD	dat_dm,	0x01,	0x31
	ret
decdm:	DEC_BCD	dat_dm,	0x01,	0x31
	ret
incm:	INC_BCD	dat_m,	0x01,	0x12
	ret
decm:	DEC_BCD	dat_m,	0x01,	0x12
	ret
incy:	INC_BCD	dat_y,	0x00,	0x99
	ret
decy:	DEC_BCD	dat_y,	0x00,	0x99
	ret
incdw:	INC_BCD	dat_dw,	0x01,	0x07
	ret

; to inc / dec the hour, 24h mode is used
; so if the register is in 12h, it's toggled to
; 24h and then toggled back
inch_a:	clr	a2
	sbrs	alarm_h, 7		; if 12h, change to 24h
	rjmp	iha_1
	ser	a2			; r2=0xff if mode changed
	mov	a0,	alarm_h
	call	swp_h
	mov	alarm_h, a0
iha_1:	INC_BCD	alarm_h, 0x00,	0x23	; inc in 24h mode
	sbrs	a2,	0		; test if changed
	ret
	mov	a0,	alarm_h
	call	swp_h
	mov	alarm_h, a0		; change back if changed
	ret

dech_a:	clr	a2
	sbrs	alarm_h, 7
	rjmp	dha_1
	ser	a2
	mov	a0,	alarm_h
	call	swp_h
	mov	alarm_h, a0
dha_1:	DEC_BCD	alarm_h, 0x00,	0x23
	sbrs	a2,	0
	ret
	mov	a0,	alarm_h
	call	swp_h
	mov	alarm_h, a0
	ret
	
inch:	clr	a2
	sbrs	time_h,	7
	rjmp	ih_1
	ser	a2
	mov	a0,	time_h
	call	swp_h
	mov	time_h,	a0
ih_1:	INC_BCD	time_h,	0x00,	0x23
	sbrs	a2,	0
	ret
	mov	a0,	time_h
	call	swp_h
	mov	time_h,	a0
	ret

dech:	clr	a2
	sbrs	time_h,	7
	rjmp	dh_1
	ser	a2
	mov	a0,	time_h
	call	swp_h
	mov	time_h,	a0
dh_1:	DEC_BCD	time_h,	0x00,	0x23
	sbrs	a2,	0
	ret
	mov	a0,	time_h
	call	swp_h
	mov	time_h,	a0
	ret

;main structure
;uC stays in one of the modes
;jump to the other modes if corresponding btn is pressed (polling)

;in mode_clk if time and alarm correspond, the alarm function is called
;it is not possible to go back to any other state while alarm is ringing

mode_clk:
;standard time mode, shows time and date
;verifies alarm, lets user switch on and off the alarm
;polling for the buttons
	call	LCD_clear
	call	LCD_home
	call	disp_show_time_io
	call	LCD_lf
	call	disp_show_date_io
	
	;verify if alarm on or off
	sbrc	state,	0
	rjmp	on
	
	rcall 	LCD_puts
.db	" Off",0,0
	rjmp	off
on:
	rcall 	LCD_puts
.db	"  On",0,0
	rcall	verify_alarm
off:	
	; display blurs without wait
	WAIT_MS	30
	
	; check butons (polling)
	BTN_BUF	r0,	buf_b,	mode_clk

	sbrc	r0,	0
	rjmp	mode_ch_clk
	
	sbrc	r0,	1
	call	swp_1224

	ldi	w,	(1<<ALARM)
	sbrc	r0,	2
	eor	state,	w
	
	sbrc	r0,	5
	rjmp	mode_ch_alarm
	
	sbrc	r0,	6
	rjmp	mode_chrono

	rjmp	mode_clk

mode_ch_clk:
; mode to change time, followed by mode to change date
	; read current time to cache registers
	RD_CAL	0x85
	mov	time_h,	a0
	RD_CAL	0x83
	mov	time_m,	a0
	RD_CAL	0x81
	mov	time_s,	a0

	; show cached time and short "mode d'emploi"
ch_clk:	call	LCD_clear
	call	LCD_home
	call	disp_show_time_reg
	call	LCD_lf
	call	LCD_puts
.db	"h+/-m+/-s+/-24dt",0,0

	WAIT_MS	30			; avoid display blur
	
	; check butons (polling)
	BTN_BUF	r0,	buf_b,	ch_clk

	sbrc	r0,	1
	call	swp_1224

	sbrc	r0,	2
	call	decs
	sbrc	r0,	3
	call	incs
	sbrc	r0,	4
	call	decmin
	sbrc	r0,	5
	call	incmin
	sbrc	r0,	6
	call	dech
	sbrc	r0,	7
	call	inch
	
	sbrs	r0,	0
	rjmp	ch_clk

	; write cached time back to calendar
	WR_CAL	0x84,	time_h
	WR_CAL	0x82,	time_m
	WR_CAL	0x80,	time_s

mode_ch_dat:
; mode to change date
	; read current date to cache registers
	RD_CAL	0x8b
	mov	dat_dw,	a0
	RD_CAL	0x87
	mov	dat_dm, a0
	RD_CAL	0x89
	mov	dat_m,	a0
	RD_CAL	0x8d
	mov	dat_y,	a0
	; show cached date and short buton description
ch_dat:	call	LCD_clear
	call	LCD_home
	call	disp_show_date_reg
	call	LCD_lf
	call	LCD_puts
.db	"d+/-m+/-y+/-dwck",0,0
	WAIT_MS	30			;avoid display blur
	
	; check butons (polling)
	BTN_BUF	r0,	buf_b,	ch_dat
	
	sbrc	r0,	1
	call	incdw
	sbrc	r0,	2
	call	decy
	sbrc	r0,	3
	call	incy
	sbrc	r0,	4
	call	decm
	sbrc	r0,	5
	call	incm
	sbrc	r0,	6
	call	decdm
	sbrc	r0,	7
	call	incdm


	sbrs	r0,	0
	rjmp	ch_dat
	
	; write cached date back to calendar
	WR_CAL	0x8a,	dat_dw
	WR_CAL	0x86,	dat_dm
	WR_CAL	0x88,	dat_m
	WR_CAL	0x8c,	dat_y

	rjmp	mode_clk

mode_chrono:
; chrono mode, stop and leap btns are checked by interrupts
; shows current chrono-time and leap, scrolling in leaps possible
; chrono continues if mode is changed

	; Enable extern interrupts (buton start/stop and leap/reset
	OUTI	EIMSK,	0b00000011

chrono_lp:
	; display leaps (if any) and current chrono
	call	LCD_clear
	call	LCD_home
	call	disp_show_leap
	call	LCD_lf
	call	disp_show_chrono_r
	
	WAIT_MS	30			; avoid display blur
	
	; check butons except leap/reset and start/stop by polling
	BTN_BUF	r0,	buf_b,	chrono_lp

	sbrc	r0,	7
	rjmp	goto_clk
	sbrc	r0,	5
	rjmp	goto_ch_alarm
	
	sbrc	r0,	2
	call	chrono_dec_leap
	sbrc	r0,	3
	call	chrono_inc_leap
	
	rjmp	chrono_lp

goto_clk:
	OUTI	EIMSK,	0x00		; Disable extern interrupts
	rjmp	mode_clk

goto_ch_alarm:
	OUTI	EIMSK,	0x00		; Disable extern interrupts

mode_ch_alarm:
; mode to change the alarm
	; display current alarm time, 
	call	LCD_clear
	call	LCD_home
	call	disp_show_alarm_reg

	; display if game mode on or off
	sbrs	state,	GAME
	rjmp	g_off
	call	LCD_puts
.db	" game",0
g_off:
	call	LCD_lf
	call	LCD_puts
.db	" h+/-m+/- 124jeu",0,0

	WAIT_MS	30			; avoid disp blur
	
	; check butons by polling
	BTN_BUF	r0,	buf_b,	mode_ch_alarm
	
	ldi	w,	(1<<GAME)	; toggle game in state register
	sbrc	r0,	0
	eor	state,	w
	sbrc	r0,	1
	call	swp_1224

	sbrc	r0,	2
	call	decm_a
	sbrc	r0,	3
	call	incm_a
	sbrc	r0,	4
	call	dech_a
	sbrc	r0,	5
	call	inch_a

	sbrc	r0,	6
	rjmp	mode_chrono
	sbrc	r0,	7
	rjmp	mode_clk

	rjmp	mode_ch_alarm


disp_show_alarm_reg:
; shows the content of the alarm registers
; in: alarm_h, alarm_m
; out: on display
; mod:	a0,a1,w
	;hours
	mov	a0,	alarm_h	; in BCD format
	mov	a1,	a0	; make copy for second digit
	swap	a0		; extract first digit
	andi	a0,	0x03
	sbrc	alarm_h, 7	; if 12h mode must be lower/equal 1
	andi	a0,	0x01
	subi	a0,	-'0'	; add ASCII offset
	call	LCD_putc	; print first digit
	andi	a1,	0x0f	; extract second digit
	ldi	a0,	'0'	; add ASCII offset
	add	a0,	a1
	call	LCD_putc	; print second digit
	ldi	a0,	':'	; print separator
	call	LCD_putc
	
	;minutes
	SHOW_BCD alarm_m,0x07,0x0f
	
	; write "!A/PM"(bit5) if 12/!24(bit7)
	sbrs	alarm_h, 7
	ret

	ldi	a0,	' '	; print separator
	call	LCD_putc
	ldi	a0,	'A'	; load A, overwrite with P if bit5 (!AM/PM) set
	sbrc	alarm_h, 5
	ldi	a0,	'P'
	call	LCD_putc
	ldi	a0,	'M'	; print second char
	call	LCD_putc
	ret	


verify_alarm:
; reads and compares time in calendar with alarm time
; calls alarm routine if equal, return otherwise
	RD_CAL	0x85
	mov	time_h,	a0
	RD_CAL	0x83
	mov	time_m,	a0
	RD_CAL	0x81
	mov	time_s,	a0
	
	
	bst	state,	0	;verify if alarm on
	brtc	no_alarm

	tst	time_s		;verify if sec == 0
	brne	no_alarm
	
	cpse	time_h,	alarm_h	;verify if hours == alarm
	rjmp	no_alarm
	
	cpse	time_m,	alarm_m	;verify if minutes == alarm
	rjmp	no_alarm
	
	clr	r24
	clr	r23		;initialize mode_alarm
	ldi	r20,	1
	
	rcall 	mode_alarm
	
no_alarm:	
	ret

mode_alarm:
; called if alarm occured
; enables timer2 interrupt (SPEAKER)
; clears LCD and jumps to game/easymode
	in	w,	TIMSK		;enable timer2 interrupt (speaker)
	ori	w,	(1<<TOIE2)
	out	TIMSK,	w

	call	LCD_clear
	call	LCD_home

	sbrc	state,	GAME
	rjmp	_alarm
	
easymode:
; print nice message
; waits for any buton to be pressed
; disables timer2 interrupt and returns

	call	LCD_puts
.db	"     ALARM!!!",0

easylp:	BTN_BUF	r0,	buf_b,	easylp	; wait for any button to be pressed
	
	in	w,	TIMSK		; disable timer2 interrupt (speaker)
	andi	w,	~(1<<TOIE2)
	out	TIMSK,	w
	ret

_alarm:	
	;r24 is a time counter, r23 is the button counter, 
	;T bit defines mode: change button[T=1]/wait for button push[T=0]


	inc	r20
	cpi	r20,	8
	brne	PC+2
	clr	r20
	
	;game over mechanism
	inc	r24		;r24 is increased at each loop, with a WAIT_MS
	WAIT_MS	4		;it determines the speed of the game		
	cpi	r24,	0xff	;verify if counter has ended
	brne	game_continue	;if it has, print message and reset game
	call	LCD_clear			
	call	LCD_home
	rcall 	LCD_puts
.db	"Try Again",0			
	WAIT_MS	1000
	clr	r24
	clr	r23
	SET				
		
game_continue:		
	cpi	r23,	0	;verify if 1st button, else skip paragraph
	brne	_b1		
	brtc	_b1		;verify T if change button mode, else skip paragraph
	mov	r21,	r20	;pick random value after user has pressed button
	ldi	r22,	1
	call	LCD_clear
	call	LCD_home
	rcall 	LCD_puts
.db	"Press Button ",0	;display which button to press
	ldi	a0,	'0'
	add	a0,	r21
	call	LCD_putc
	CLT			;change T mode to wait for button	
	
_b1:	cpi	r23,	1	;verify if 2nd button
	brne	_b2
	brtc	_b2
	mov	r21,	r20
	ldi	r22,	1
	call	LCD_clear
	call	LCD_home
	rcall 	LCD_puts
.db	"Press Button ",0	
	ldi	a0,	'0'
	add	a0,	r21
	call	LCD_putc
	CLT			
	
_b2:	cpi	r23,	2	;verify if 3rd button
	brne	_b3
	brtc	_b3
	mov	r21,	r20
	ldi	r22,	1
	call	LCD_clear
	call	LCD_home
	rcall 	LCD_puts
.db	"Press Button ",0	
	ldi	a0,	'0'
	add	a0,	r21
	call	LCD_putc
	CLT			

_b3:	

loop:	tst	r21		;create a register (r22) to compare with buttons
	breq	PC+4
	lsl	r22
	dec	r21
	rjmp	loop
	
	BTN_BUF	r0,	buf_b,	alarm_loop
	
	cp	r0,	r22	;test if correct button pressed
	brne	PC+4
	inc	r23		;increase button counter
	clr	r24		;time counter reset
	SET			;change T mode to change button	

	cpi	r23,	3	;end condition
	brne	alarm_loop

	in	w,	TIMSK		;disable timer2 interrupt (speaker)
	andi	w,	~(1<<TOIE2)
	out	TIMSK,	w
	ret
	
alarm_loop:	rjmp 	_alarm	;relative jump out of range

chrono_inc_leap:
; y points to the end of the current shown value
; subtract offset and divide by length(4 bytes)
; inc within 0 and the number of leaps (N_leap)
; add offset and multiply by 4
	DIV_W4	yh,	yl
	sbiw	yl,	0x19
	cp	yl,	N_leap
	brge	cil
	adiw	yl,	0x1a
	MUL_W4	yh,	yl
	ret

cil:	ldi	yl,	low(0x68)
	ldi	yh,	high(0x68)
	ret

chrono_dec_leap:
; y points to the end of the current shown value
; divide  by length of 1 leap (4 bytes)
; dec within 0 and the number of leaps (N_leap)
; multiply by length
	DIV_W4	yh,	yl	; divide word by 4
	cpi	yl,	0x1b	; detect lower limit (ofset)
	brsh	cdl
	add	yl,	N_leap
	
cdl:	dec	yl
	MUL_W4	yh,	yl
	ret

disp_show_leap:
; gets leap before place where y points from SRAM
; returns immediately if there is no leap to show
; otherwise print leap (calls disp_show_chrono)
; and the number of the leap
; in: y, N_leap, SRAM
; mod: r4,r5,r6,r7,w,a0,a1
; out: LCD
	ld	r4,	-y		; load safed leap in registers
	ld	r5,	-y
	ld	r6,	-y
	ld	r7,	-y
	adiw	yl,	4

	; only print leap if there is one
	tst	N_leap			
	breq	disp_sl_end
	rcall	disp_show_chrono
	
	; show number of leap
	ldi	a0,	' '
	rcall	LCD_putc
	mov	a1,	yl		; load ptr and divide by size (4)
	clc
	ror	a1
	ror	a1
	subi	a1,	0x19		; substract offset
	ldi	a0,	'0'		; load char offset
dsl_1:	cpi	a1,	10		; substract 10 (increment char)
	brlo	dsl_2			; until lower than ten
	inc	a0
	subi	a1,	10
	rjmp	dsl_1
dsl_2:	rcall	LCD_putc		; print first char
	mov	a0,	a1
	andi	a0,	0x0f
	subi	a0,	-'0'
	rcall	LCD_putc		; print 2nd char
disp_sl_end:
	ret

disp_show_chrono_r:
; print chrono time on LCD
; in: chr_h, chr_m, chr_s, chr_100
; mod: r4,r5,r6,r7,w,a0,a1
; out: LCD
	mov	r4,	chr_h	
	mov	r5,	chr_m
	mov	r6,	chr_s
	mov	r7,	chr_100

disp_show_chrono:
; print chrono time on LCD
; in: r4,r5,r6,r7
; mod: r4,r5,r6,r7,w,a0,a1
; out: LCD
	;hours
	SHOW_BCD r4,0x0f,0x0f
	ldi	a0,	':'
	call	LCD_putc
	;min
	SHOW_BCD r5,0x07,0x0f
	ldi	a0,	':'
	call	LCD_putc
	;seconds
	SHOW_BCD r6,0x07,0x0f
	ldi	a0,	':'
	call	LCD_putc
	;1/100 seconds
	SHOW_BCD r7,0x0f,0x0f
	ret

week_tb:
.db	"MON",0
.db	"TUE",0
.db	"WED",0
.db	"THU",0
.db	"FRI",0
.db	"SAT",0
.db	"SUN",0

disp_show_date_io:
; read date from calendar and show on LCD
; in: CALENDAR
; out: LCD
; mod: a0,a1,w,z,dat_dw,dat_dm,dat_m,dat_y
	RD_CAL	0x8b
	mov	dat_dw,	a0
	RD_CAL	0x87
	mov	dat_dm,	a0
	RD_CAL	0x89
	mov	dat_m,	a0
	RD_CAL	0x8d
	mov	dat_y,	a0

disp_show_date_reg:
; show date in calendar registers and on LCD
; in: dat_dw,dat_dm,dat_m,dat_y
; out: LCD
; mod: a0,a1,w,z

	;day of week (lookup table)
	mov	a0,	dat_dw
	andi	a0,	0x07
	lsl	a0
	lsl	a0
	ldi	zl,	low(week_tb*2-4)
	ldi	zh,	high(week_tb*2-4)
	add	zl,	a0
	clr	a0
	adc	zh,	a0
	ldi	a1,	2
lp_dr:	lpm			;check for overflow!!!
	mov	a0,	r0
	call	LCD_putc
	inc	zl
	dec	a1
	brge	lp_dr
	
	ldi	a0,	' '
	call	LCD_putc
	
	
	;day of month
	mov	a0,	dat_dm
	SHOW_BCD dat_dm,0x03,0x0f
	ldi	a0,	'.'
	call	LCD_putc
	

	;month
	SHOW_BCD dat_m,0x01,0x0f
	ldi	a0,	'.'
	call	LCD_putc
	
	;year
	SHOW_BCD dat_y,0x0f,0x0f
	ret

disp_show_time_io:
; read time from calendar and show on LCD
; in: CALENDAR
; out: LCD
; mod: a0,a1,w,time_h,time_m,time_s
	RD_CAL	0x85
	mov	time_h,	a0
	RD_CAL	0x83
	mov	time_m,	a0
	RD_CAL	0x81
	mov	time_s,	a0

disp_show_time_reg:
; show time in time registers on LCD
; in: time_h, time_m, time_s
; out: LCD
; mod: a0,a1,w
	;hours
	mov	a0,	time_h	; in BCD format
	mov	a1,	a0	; make copy for second digit
	swap	a0		; extract first digit
	andi	a0,	0x03
	sbrc	time_h,	7	; if 12h mode must be lower/equal 1
	andi	a0,	0x01
	subi	a0,	-'0'	; add ASCII offset
	call	LCD_putc	; print first digit
	andi	a1,	0x0f	; extract second digit
	ldi	a0,	'0'	; add ASCII offset
	add	a0,	a1
	call	LCD_putc	; print second digit
	ldi	a0,	':'	; print separator
	call	LCD_putc
	
	;minutes
	SHOW_BCD time_m,0x07,0x0f
	ldi	a0,	':'
	call	LCD_putc
	
	;seconds
	SHOW_BCD time_s,0x07,0x0f
	
	; write "!A/PM"(bit5) if 12/!24(bit7)
	sbrs	time_h,	7
	ret

	ldi	a0,	' '	; print separator
	call	LCD_putc
	ldi	a0,	'A'	; load A, overwrite with P if bit5 (!AM/PM) set
	sbrc	time_h,	5
	ldi	a0,	'P'
	call	LCD_putc
	ldi	a0,	'M'	; print second char
	call	LCD_putc
	ret

swp_1224:
; swap every time register used for hours 12->24/24->12
; so that user can swap the mode at once for alarm and time
;  in: CALENDAR, alarm_h, time_h
; out: CALENDAR, alarm_h, time_h
; mod: a0, w
	; swap calendrier
	RD_CAL	0x85
	rcall	swp_h;
	mov	w,	a0
	WR_CAL	0x84,	w
	
	; swap alarm
	mov	a0,	alarm_h
	rcall	swp_h
	mov	alarm_h, a0
	
	; swap intern
	mov	a0,	time_h
	rcall	swp_h
	mov	time_h,	a0
	ret
	
swp_h:
; swaps the time in a0 from 12h to 24h mode and inverse
; in: a0
; out: a0
; mod: w
	; detect mode
	sbrc	a0,	7
	rjmp	swp12_2_24	
	
	tst	a0
	breq	AM_12
	cpi	a0,	0x12
	breq	PM_12
	cpi	a0,	0x13
	brge	PM_13

	; 24 to 12

	; before PM
	; change mode to 12hAM, time unaffected
	mov	w,	a0
	ori	w,	(1<<7)
	rjmp	end_swap
	
	; after 13h
	; substract 12h (BCD-mode)
	; change mode to 12hPM
PM_13:	subi	a0,	0x12
	mov	w,	a0
	andi	w,	0x0F
	cpi	w,	10
	brlo	PC+2
	subi	a0,	0x06
	; special case 12PM
PM_12:	mov	w,	a0
	ori	w,	(1<<7)+(1<<5)
	rjmp	end_swap
	
	; special case 12AM
AM_12:	ldi	w,	(1<<7)+0x12
	rjmp	end_swap

	; 12 to 24
swp12_2_24:
	andi	a0,	0x3F	; clear 12h mode bit
	mov	w,	a0
	cpi	a0,	0x12	; midnight?
	breq	_00
	cpi	a0,	0x32	; noon?
	breq	_12
	sbrs	a0,	5	; afternoon?
	; change mode to 24h, time unaffected
	rjmp	end_swap
	
	; recalculate time for 24h mode (add 12h)
	subi	a0,	0x0E
	mov	w,	a0
	andi	a0,	0x0F
	cpi	a0,	0x0A
	brlo	PC+2
	subi	w,	-0x06
	rjmp	end_swap
	
	; special case 00
_00:	clr	w
	rjmp	end_swap
	; special case 12
_12:	ldi	w,	0x12

	; new value in w
end_swap:
	mov	a0,	w
	ret