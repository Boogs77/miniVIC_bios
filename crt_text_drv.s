.segment "CODE"
.ifdef BOOGS

VDP_PATTERN_INIT    	= $30
VDP_PATTERN_INIT_HI 	= $31
ROW_VAR               = $32     ; Address of the 'row' variable (8 bit)
COL_VAR               = $33     ; Address of the 'col' variable (8 bit)
TEMP_MULT_LO          = $34     ; Low byte of the temporary result (row * 40)
TEMP_MULT_HI          = $35     ; High byte of the temporary result (row * 40)
X_VIDEO_LO            = $36     ; Low byte of the final result
X_VIDEO_HI            = $37     ; High byte of the final result        
FORTY                 = $28     ; Constant 40 (in hexadecimal)

TEMP          = $38 ; $68
TEMP_ROW      = $39 ; $69


VREG  = $B001                ;VDP REGISTER
VDATA = $B000                ;VDP RAM

VDP_NAME_TABLE_BASE    = $0800      ; NAME TABLE
VDP_PATTERN_TABLE_BASE = $0000      ; PATTERN TABLE 
VDP_WRITE_VRAM_BIT     = %01000000  ; pattern of second vram address write: 01AAAAAA
VDP_REGISTER_BITS      = %10000000  ; pattern of second register write: 10000RRR

INIT_CRT:
  PHA
  PHX
  PHY
  JSR VDP_SET_REGISTERS        ; Setting VDP register
  JSR CLEAR_VRAM
  JSR VDP_SETUP
  PLY
  PLX
  PLA
  RTS


print_crt_ch:                                 ; Write to VRAM 2 bytes and data
  PHA
  PHX
  PHY
  
  cmp #$0a           ; enter - go to second line
  beq enter_pressed
  cmp #$0d           ; enter - go to second line
  beq EXIT_PRINTCH 
  cmp #$1b           ; escape - clear display
  beq esc_pressed
;  cmp #$08           ; backspace - clear last char
;  beq backspace_pressed
;  cmp #$20
;  bcc JUMP_EXIT
;  
  jmp print_char
;
enter_pressed:
  lda #$00
  sta COL_VAR
  INC ROW_VAR
  LDA ROW_VAR
  CMP #24
  BCC NOT_END_LINE2
  LDA #$00
  STA ROW_VAR
  JSR CLEAR_NAME_TABLE
NOT_END_LINE2:
  JSR mol_8bit
JUMP_EXIT:  
  jmp EXIT_PRINTCH  

esc_pressed:
  lda #$00
  sta X_VIDEO_HI
  lda #$78
  sta X_VIDEO_LO
  JSR CLEAR_NAME_TABLE
  jsr VDP_INITIALIZE_NAME_TABLE
  lda #$00
  STA COL_VAR
  LDA #$00
  STA ROW_VAR
  JSR mol_8bit
  jmp EXIT_PRINTCH 
  
;backspace_pressed:
;  ;dec COL_VAR
;  ;jsr mol_8bit
;  ;LDA #32
;  jsr print_char
;  dec COL_VAR
;  jsr mol_8bit
;  jmp EXIT_PRINTCH  
  
print_char:  
  LDX X_VIDEO_LO                              ; 1 byte A6 A7 A8 A9|A10 A11 A12 A13 (LSB)
  STX VREG                       
  TAX                                      ; Copying all TEXT char in VRAM
  LDA #$48                                 ; 2 byte 0 1 A0 A1|A2 A3 A4 A5 the NAME TABLE STARTS AT &0800
  ORA X_VIDEO_HI
  STA VREG
  TXA
  TAY
  STY VDATA                                ; Copying all TEXT char in VRAM
  
  INC COL_VAR
  LDA COL_VAR
  CMP #40
  BCC NOT_END_LINE
  LDA #$00
  STA COL_VAR  
  INC ROW_VAR
  LDA ROW_VAR
  CMP #24
  BCC NOT_END_LINE
  LDA #$00
  STA ROW_VAR
  JSR CLEAR_NAME_TABLE

NOT_END_LINE:
  JSR mol_8bit
EXIT_PRINTCH:  
  PLY
  PLX
  PLA
  RTS



VDP_SETUP:
  JSR VDP_INITIALIZE_PATTERN_TABLE ; Initilizing Pattern Table
  JSR VDP_INITIALIZE_NAME_TABLE    ; Initilizing Name Table only BACKGROUND
  JSR VDP_ENABLE_DISPLAY           ; Enabling Display (ON ARDUINO WE DO NOT ENABLE IT LATER BUT ALREADY AT FIRST START)
  RTS

VDP_INITIALIZE_PATTERN_TABLE:       ; Write to VRAM
  PHA
  PHX
  LDA #<(VDP_PATTERN_TABLE_BASE)    ; Byte 1 loading LSB Pattern Table Address
  STA VREG
  LDA #(VDP_WRITE_VRAM_BIT | >VDP_PATTERN_TABLE_BASE) ; Byte 2 loading MSB Pattern Table Address (combined
  STA VREG                                        ; with 0 1 A0 A1 A2 A3 A4 A5
  LDA #<VDP_PATTERNS                      ; LOAD THE START ADDRESS OF THE PATTERNS TO ZERO PAGE
  STA VDP_PATTERN_INIT
  LDA #>VDP_PATTERNS
  STA VDP_PATTERN_INIT_HI
VDP_PATTERN_TABLE_LOOP:
  LDA (VDP_PATTERN_INIT)                  ; LOAD A WITH THE VALUE AT VDP_PATTERN_INIT
  STA VDATA                            ; AND STORE IT TO VRAM
  LDA VDP_PATTERN_INIT                    ; LOAD THE LOW BYTE OF VDP_PATTERN_INIT ADDRESS INTO A
  CLC                                     ; CLEAR CARRY FLAG
  ADC #1                                  ; ADD 1, WITH CARRY
  STA VDP_PATTERN_INIT                    ; STORE BACK INTO VDP_PATTERN_INIT
  LDA #0                                  ; LOAD A WITH 0
  ADC VDP_PATTERN_INIT_HI                 ; ADD WITH THE CARRY FLAG TO THE HIGH ADDRESS
  STA VDP_PATTERN_INIT_HI                 ; AND STORE THAT BACK INTO THE HIGH BYTE
  CMP #>VDP_END_PATTERNS                  ; COMPARE IF WE'RE AT THE END OF THE PATTERNS
  BNE VDP_PATTERN_TABLE_LOOP              ; IF NOT, LOOP AGAIN
  LDA VDP_PATTERN_INIT                    ; COMPARE THE LOW BYTE
  CMP #<VDP_END_PATTERNS
  BNE VDP_PATTERN_TABLE_LOOP              ; IF NOT EQUAL, LOOP AGAIN
  PLX
  PLA
  RTS

VDP_INITIALIZE_NAME_TABLE:                ; Write to VRAM 2 bytes and data
  PHA
  PHX
  PHY
;  LDX #$00                                 ; 1 byte A6 A7 A8 A9|A10 A11 A12 A13 (LSB) 
;VDP_INITALIZE_NAME_TABLE_LOOP:
;  STX VREG                       
;  LDA #$48                                 ; 2 byte 0 1 A0 A1|A2 A3 A4 A5 the NAME TABLE STARTS AT &0800
;  STA VREG
;  LDY TEXT,X
;  STY VDATA                                ; Copying all TEXT char in VRAM
;  INX
;  CPX #(TEXT_END - TEXT_BEGINNING)
;  BNE VDP_INITALIZE_NAME_TABLE_LOOP
  lda #$00
  STA COL_VAR
  LDA #$0 ;LDA #$03
  STA ROW_VAR
  JSR mol_8bit
  PLY
  PLX
  PLA
  RTS

TEXT_BEGINNING:
TEXT: .byte  "   ****  BO 6502 SYSTEM MONITOR  ****      CLOCK 1MHz 32K RAM 32K ROM 8K VRAM   "
TEXT_END:

VDP_ENABLE_DISPLAY:                       ; Write to VDP REGISTER
  PHA
  LDA #%11010000			                  ; SELECT 16K BYTES OF VRAM, ENABLE THE ACTIVE DISPLAY
  STA VREG                               ; DISABLE VDP INTERRUPT, SET TEXT MODE
  LDA #(VDP_REGISTER_BITS | 1)           ; Selecting register 1 
  STA VREG
  PLA
  RTS


VDP_SET_REGISTERS:
  PHA
  PHY
  LDY #$87                     ;REGISTER SELECT
  LDX #$07                     ;INITIALIZE COUNTER
INIT1:
  LDA ITAB,X                   ;LOAD INIT TABLE
  JSR SREG                     ;WRITE TO VDP 
  DEY                          ;DECREMENT REGISTER
  DEX                          ;DECREMENT COUNTER   
  BNE INIT1                    ;DONE?
  JSR SREG
  PLY
  PLA
  RTS
   
SREG:                 ;STORE VIDEO REGISTER
  PHA
  PHY
  STA VREG
  STY VREG
  PLY
  PLA
  RTS

 CLEAR_VRAM:
   PHA
   PHX
   PHY
   LDY #$40				; SETUP VRAM ADDRESS 
   LDA #0
   STA VREG
   STY VREG
   LDX #$C0				; COUNT HIGH
 NEXF:
   LDY #0				; COUNT LOW
 FILL_:
   LDA #$20

   STA VDATA		   ; WRITE A ZERO TO VRAM
   INY					; NEXT LOC
   BNE FILL_			; KEEP GOING UNTIL PAGE DONE
   INX					; DONE ALL 40 PAGES?
   BNE NEXF				; NO, KEEP GOING
   PLY
   PLX
   PLA
   RTS

ITAB: .BYTE $00,$D0,$02,$00       ;INITIALIZE TABLE
     .BYTE $00,$20,$00,$F5

CLEAR_NAME_TABLE:
    PHA                 ; Save the accumulator on the stack
    PHX                 ; Save register X on the stack
    PHY                 ; Save register Y on the stack

    LDX #$00            ; Set the low counter to 0
    LDY #$05            ; Set the high counter to 3 (960 divided by 256)
    LDA #$00            ; Set the low byte of the Name Table start address
    STA VREG            ; Write the low byte of the address
    LDA #$48            ; Set the high byte of the Name Table start address ($0800) xxxxxxxxxxx
    STA VREG            ; Write the high byte of the address

OUTER_LOOP:
    LDA #$20            ; ASCII value of the blank space (32 decimal)
    STA VDATA           ; Write the value to VRAM

    ; Increment the low counter
    INX                 ; Increment register X
    CPX #$C0
    BNE INNER_LOOP       ; If X != 192, continue the loop
    
    LDX #$00            ; Reset the inner counter (X) to 0
    DEY                 ; Decrement register Y
    BEQ DONE            ; If Y == 0, end the loop

INNER_LOOP:
    JMP OUTER_LOOP      ; Back to the main loop

DONE:
    ; Restore the registers
    PLY                 ; Restore register Y
    PLX                 ; Restore register X
    PLA                 ; Restore the accumulator
    RTS                 ; Return from the subroutine

mol_8bit:
    PHA
    ; Initialize the temporary result
    LDA #$00
    STA TEMP_MULT_LO      ; Low byte of the temporary result
    STA TEMP_MULT_HI      ; High byte of the temporary result

    ; Load ROW and FORTY to compute ROW * 40
    LDA ROW_VAR           ; Load ROW
    BEQ ADD_COL           ; If ROW is 0, jump straight to adding COL
    STA TEMP_ROW          ; Save ROW temporarily
MULT_LOOP:
    ; Add FORTY to the temporary result
    LDA TEMP_MULT_LO
    CLC
    ADC #FORTY            ; Add 40 to the low byte
    STA TEMP_MULT_LO      ; Save the new low byte
    LDA TEMP_MULT_HI
    ADC #$00              ; Add the carry to the high byte
    STA TEMP_MULT_HI      ; Save the new high byte

    ; Decrement ROW
    LDA TEMP_ROW
    SEC
    SBC #$01              ; ROW = ROW - 1
    STA TEMP_ROW          ; Save the new value of ROW
    BNE MULT_LOOP         ; Repeat while ROW > 0
ADD_COL:
    ; Add COL to the temporary result
    LDA TEMP_MULT_LO
    CLC
    ADC COL_VAR           ; Add COL to the low byte
    STA X_VIDEO_LO         ; Save the low byte of the final result
    LDA TEMP_MULT_HI
    ADC #$00              ; Add the carry to the high byte
    STA X_VIDEO_HI         ; Save the high byte of the final result
    ; End
    PLA
    RTS



;TEMP:     .BYTE $0
;TEMP_ROW: .byte $00       ; Temporary variable for ROW


;   .align 8
VDP_PATTERNS:
 ; line drawing
   .byte $00,$00,$00,$FF,$FF,$00,$00,$00 ; lr
   .byte $18,$18,$18,$18,$18,$18,$18,$18 ; ud
   .byte $00,$00,$00,$F8,$F8,$18,$18,$18 ; ld
   .byte $00,$00,$00,$1F,$1F,$18,$18,$18 ; rd
   .byte $18,$18,$18,$F8,$F8,$00,$00,$00 ; lu
   .byte $18,$18,$18,$1F,$1F,$00,$00,$00 ; ur
   .byte $18,$18,$18,$FF,$FF,$18,$18,$18 ; lurd
 ; <nonsense for debug>
   .byte $07,$07,$07,$07,$07,$07,$07,$00 ; 07
   .byte $08,$08,$08,$08,$08,$08,$08,$00 ; 08
   .byte $09,$09,$09,$09,$09,$09,$09,$00 ; 09
   .byte $0A,$0A,$0A,$0A,$0A,$0A,$0A,$00 ; 0A
   .byte $0B,$0B,$0B,$0B,$0B,$0B,$0B,$00 ; 0B
   .byte $0C,$0C,$0C,$0C,$0C,$0C,$0C,$00 ; 0C
   .byte $0D,$0D,$0D,$0D,$0D,$0D,$0D,$00 ; 0D
   .byte $0E,$0E,$0E,$0E,$0E,$0E,$0E,$00 ; 0E
   .byte $0F,$0F,$0F,$0F,$0F,$0F,$0F,$00 ; 0F
   .byte $10,$10,$10,$10,$10,$10,$10,$00 ; 10
   .byte $11,$11,$11,$11,$11,$11,$11,$00 ; 11
   .byte $12,$12,$12,$12,$12,$12,$12,$00 ; 12
   .byte $13,$13,$13,$13,$13,$13,$13,$00 ; 13
   .byte $14,$14,$14,$14,$14,$14,$14,$00 ; 14
   .byte $15,$15,$15,$15,$15,$15,$15,$00 ; 15
   .byte $16,$16,$16,$16,$16,$16,$16,$00 ; 16
   .byte $17,$17,$17,$17,$17,$17,$17,$00 ; 17
   .byte $18,$18,$18,$18,$18,$18,$18,$00 ; 18
   .byte $19,$19,$19,$19,$19,$19,$19,$00 ; 19
   .byte $1A,$1A,$1A,$1A,$1A,$1A,$1A,$00 ; 1A
   .byte $1B,$1B,$1B,$1B,$1B,$1B,$1B,$00 ; 1B
   .byte $1C,$1C,$1C,$1C,$1C,$1C,$1C,$00 ; 1C
   .byte $1D,$1D,$1D,$1D,$1D,$1D,$1D,$00 ; 1D
   .byte $1E,$1E,$1E,$1E,$1E,$1E,$1E,$00 ; 1E
   .byte $1F,$1F,$1F,$1F,$1F,$1F,$1F,$00 ; 1F
 ; </nonsense>
   .byte $00,$00,$00,$00,$00,$00,$00,$00 ; ' '
   .byte $20,$20,$20,$00,$20,$20,$00,$00 ; !
   .byte $50,$50,$50,$00,$00,$00,$00,$00 ; "
   .byte $50,$50,$F8,$50,$F8,$50,$50,$00 ; #
   .byte $20,$78,$A0,$70,$28,$F0,$20,$00 ; $
   .byte $C0,$C8,$10,$20,$40,$98,$18,$00 ; %
   .byte $40,$A0,$A0,$40,$A8,$90,$68,$00 ; &
   .byte $20,$20,$40,$00,$00,$00,$00,$00 ; '
   .byte $20,$40,$80,$80,$80,$40,$20,$00 ; (
   .byte $20,$10,$08,$08,$08,$10,$20,$00 ; )
   .byte $20,$A8,$70,$20,$70,$A8,$20,$00 ; *
   .byte $00,$20,$20,$F8,$20,$20,$00,$00 ; +
   .byte $00,$00,$00,$00,$20,$20,$40,$00 ; ,
   .byte $00,$00,$00,$F8,$00,$00,$00,$00 ; -
   .byte $00,$00,$00,$00,$20,$20,$00,$00 ; .
   .byte $00,$08,$10,$20,$40,$80,$00,$00 ; /
   .byte $70,$88,$98,$A8,$C8,$88,$70,$00 ; 0
   .byte $20,$60,$20,$20,$20,$20,$70,$00 ; 1
   .byte $70,$88,$08,$30,$40,$80,$F8,$00 ; 2
   .byte $F8,$08,$10,$30,$08,$88,$70,$00 ; 3
   .byte $10,$30,$50,$90,$F8,$10,$10,$00 ; 4
   .byte $F8,$80,$F0,$08,$08,$88,$70,$00 ; 5
   .byte $38,$40,$80,$F0,$88,$88,$70,$00 ; 6
   .byte $F8,$08,$10,$20,$40,$40,$40,$00 ; 7
   .byte $70,$88,$88,$70,$88,$88,$70,$00 ; 8
   .byte $70,$88,$88,$78,$08,$10,$E0,$00 ; 9
   .byte $00,$00,$20,$00,$20,$00,$00,$00 ; :
   .byte $00,$00,$20,$00,$20,$20,$40,$00 ; ;
   .byte $10,$20,$40,$80,$40,$20,$10,$00 ; <
   .byte $00,$00,$F8,$00,$F8,$00,$00,$00 ; =
   .byte $40,$20,$10,$08,$10,$20,$40,$00 ; >
   .byte $70,$88,$10,$20,$20,$00,$20,$00 ; ?
   .byte $70,$88,$A8,$B8,$B0,$80,$78,$00 ; @
   .byte $20,$50,$88,$88,$F8,$88,$88,$00 ; A
   .byte $F0,$88,$88,$F0,$88,$88,$F0,$00 ; B
   .byte $70,$88,$80,$80,$80,$88,$70,$00 ; C
   .byte $F0,$88,$88,$88,$88,$88,$F0,$00 ; D
   .byte $F8,$80,$80,$F0,$80,$80,$F8,$00 ; E
   .byte $F8,$80,$80,$F0,$80,$80,$80,$00 ; F
   .byte $78,$80,$80,$80,$98,$88,$78,$00 ; G
   .byte $88,$88,$88,$F8,$88,$88,$88,$00 ; H
   .byte $70,$20,$20,$20,$20,$20,$70,$00 ; I
   .byte $08,$08,$08,$08,$08,$88,$70,$00 ; J
   .byte $88,$90,$A0,$C0,$A0,$90,$88,$00 ; K
   .byte $80,$80,$80,$80,$80,$80,$F8,$00 ; L
   .byte $88,$D8,$A8,$A8,$88,$88,$88,$00 ; M
   .byte $88,$88,$C8,$A8,$98,$88,$88,$00 ; N
   .byte $70,$88,$88,$88,$88,$88,$70,$00 ; O
   .byte $F0,$88,$88,$F0,$80,$80,$80,$00 ; P
   .byte $70,$88,$88,$88,$A8,$90,$68,$00 ; Q
   .byte $F0,$88,$88,$F0,$A0,$90,$88,$00 ; R
   .byte $70,$88,$80,$70,$08,$88,$70,$00 ; S
   .byte $F8,$20,$20,$20,$20,$20,$20,$00 ; T
   .byte $88,$88,$88,$88,$88,$88,$70,$00 ; U
   .byte $88,$88,$88,$88,$50,$50,$20,$00 ; V
   .byte $88,$88,$88,$A8,$A8,$D8,$88,$00 ; W
   .byte $88,$88,$50,$20,$50,$88,$88,$00 ; X
   .byte $88,$88,$50,$20,$20,$20,$20,$00 ; Y
   .byte $F8,$08,$10,$20,$40,$80,$F8,$00 ; Z
   .byte $F8,$C0,$C0,$C0,$C0,$C0,$F8,$00 ; [
   .byte $00,$80,$40,$20,$10,$08,$00,$00 ; \
   .byte $F8,$18,$18,$18,$18,$18,$F8,$00 ; ]
   .byte $00,$00,$20,$50,$88,$00,$00,$00 ; ^
   .byte $00,$00,$00,$00,$00,$00,$F8,$00 ; _
   .byte $40,$20,$10,$00,$00,$00,$00,$00 ; `
   .byte $00,$00,$70,$88,$88,$98,$68,$00 ; a
   .byte $80,$80,$F0,$88,$88,$88,$F0,$00 ; b
   .byte $00,$00,$78,$80,$80,$80,$78,$00 ; c
   .byte $08,$08,$78,$88,$88,$88,$78,$00 ; d
   .byte $00,$00,$70,$88,$F8,$80,$78,$00 ; e
   .byte $30,$40,$E0,$40,$40,$40,$40,$00 ; f
   .byte $00,$00,$70,$88,$F8,$08,$F0,$00 ; g
   .byte $80,$80,$F0,$88,$88,$88,$88,$00 ; h
   .byte $00,$40,$00,$40,$40,$40,$40,$00 ; i
   .byte $00,$20,$00,$20,$20,$A0,$60,$00 ; j
   .byte $00,$80,$80,$A0,$C0,$A0,$90,$00 ; k
   .byte $C0,$40,$40,$40,$40,$40,$60,$00 ; l
   .byte $00,$00,$D8,$A8,$A8,$A8,$A8,$00 ; m
   .byte $00,$00,$F0,$88,$88,$88,$88,$00 ; n
   .byte $00,$00,$70,$88,$88,$88,$70,$00 ; o
   .byte $00,$00,$70,$88,$F0,$80,$80,$00 ; p
   .byte $00,$00,$F0,$88,$78,$08,$08,$00 ; q
   .byte $00,$00,$70,$88,$80,$80,$80,$00 ; r
   .byte $00,$00,$78,$80,$70,$08,$F0,$00 ; s
   .byte $40,$40,$F0,$40,$40,$40,$30,$00 ; t
   .byte $00,$00,$88,$88,$88,$88,$78,$00 ; u
   .byte $00,$00,$88,$88,$90,$A0,$40,$00 ; v
   .byte $00,$00,$88,$88,$88,$A8,$D8,$00 ; w
   .byte $00,$00,$88,$50,$20,$50,$88,$00 ; x
   .byte $00,$00,$88,$88,$78,$08,$F0,$00 ; y
   .byte $00,$00,$F8,$10,$20,$40,$F8,$00 ; z
   .byte $38,$40,$20,$C0,$20,$40,$38,$00 ; {
   .byte $40,$40,$40,$00,$40,$40,$40,$00 ; |
   .byte $E0,$10,$20,$18,$20,$10,$E0,$00 ; }
   .byte $00,$00,$24,$00,$00,$42,$3C,$00 ; ~
   .byte $A8,$50,$A8,$50,$A8,$50,$A8,$00 ; checkerboard
VDP_END_PATTERNS:


.endif