
disp_show_date:
	;day of week (lookup table)
	RD_CAL	0x8b
	andi	a0,	0x07
	lsl	a0
	lsl	a0
	ldi	zl,	low(week_tb*2-4)
	ldi	zh,	high(week_tb*2-4)
	add	zl,	a0
	clr	a0
	adc	zh,	a0
	ldi	a1,	2
lp_d:	lpm
	mov	a0,	r0
	call	LCD_putc
	inc	zl
	dec	a1
	brge	lp_d
	
	ldi	a0,	' '
	call	LCD_putc
	
	
	;day of month
	RD_CAL	0x87
	mov	a1,	a0
	swap	a0
	andi	a0,	0x03
	subi	a0,	-'0'
	call	LCD_putc
	andi	a1,	0x0f
	ldi	a0,	'0'
	add	a0,	a1
	call	LCD_putc
	ldi	a0,	'.'
	call	LCD_putc

	;month
	RD_CAL	0x89
	mov	a1,	a0
	swap	a0
	andi	a0,	0x01
	subi	a0,	-'0'
	call	LCD_putc
	andi	a1,	0x0f
	ldi	a0,	'0'
	add	a0,	a1
	call	LCD_putc
	ldi	a0,	'.'
	call	LCD_putc
	
	;year
	RD_CAL	0x8d
	mov	a1,	a0
	swap	a0
	andi	a0,	0x0f
	subi	a0,	-'0'
	call	LCD_putc
	andi	a1,	0x0f
	ldi	a0,	'0'
	add	a0,	a1
	call	LCD_putc
	ret

disp_show_time:
	;hours
	RD_CAL	0x85
	mov	a1,	a0
	mov	a2,	a0
	swap	a0
	andi	a0,	0x03
	sbrc	a2,	7
	andi	a0,	0x01
	subi	a0,	-'0'
	call	LCD_putc
	andi	a1,	0x0f
	ldi	a0,	'0'
	add	a0,	a1
	call	LCD_putc
	ldi	a0,	':'
	call	LCD_putc
	
	;minutes
	RD_CAL	0x83
	mov	a1,	a0
	swap	a0
	andi	a0,	0x07
	subi	a0,	-'0'
	call	LCD_putc
	andi	a1,	0x0f
	ldi	a0,	'0'
	add	a0,	a1
	call	LCD_putc
	ldi	a0,	':'
	call	LCD_putc
	
	;seconds
	RD_CAL	0x81
	mov	a1,	a0
	swap	a0
	andi	a0,	0x07
	subi	a0,	-'0'
	call	LCD_putc
	andi	a1,	0x0f
	ldi	a0,	'0'
	add	a0,	a1
	call	LCD_putc
	
	; write "!A/PM"(bit5) if 12/!24(bit7)
	sbrs	a2,	7
	ret

	ldi	a0,	' '
	call	LCD_putc
	ldi	a0,	'A'
	sbrc	a2,	5
	ldi	a0,	'P'
	call	LCD_putc
	ldi	a0,	'M'
	call	LCD_putc
	ret