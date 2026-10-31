.segment "CODE"
.ifdef BOOGS
PORTBK = $d180
PORTAK = $d181
DDRBK  = $d182
DDRAK  = $d183

ACR    = $d18b
PCR    = $d18c
IFR    = $d18d
IER    = $d18e

kb_wptr  = $0306
kb_rptr  = $0307
kb_flags = $0308

RELEASE = %00000001
SHIFT   = %00000010
; kb_flags bits used only in extended mode
KB_E0   = %00000100        ; $E0 prefix received (extended key)
KB_CTRL = %00001000        ; Ctrl pressed (left or right)
KB_ALT  = %00010000        ; Alt pressed (left or right)
KB_CAPS = %00100000        ; Caps Lock on (toggles at every press)

; Keyboard mode: bit 7 = 0 classic (as before: US table, Shift only),
; bit 7 = 1 extended (arrows, Delete, Home/End, PgUp/PgDn, F1-F12, Ctrl, Alt, Caps Lock).
; INIT_KEYBOARD (so every return to the menu) sets classic mode again.
kb_mode  = $0309
KB_MODE_EXT = %10000000

kb_buffer = $0400

; **DEBUG**
DEBUG_LOG   = $0380
DEBUG_PTR   = $037F


INIT_KEYBOARD:
  sei
  cld
  
  lda #$00
  sta kb_wptr
  sta kb_rptr
  sta kb_flags
  sta kb_mode                ; classic mode

  ; **INIT DEBUG**
  sta DEBUG_PTR
  ldx #$7F
@clear:
  lda #$FF
  sta DEBUG_LOG, x
  dex
  bpl @clear

  lda #$01
  sta PCR

  lda #%00000000
  sta DDRAK
  rts

FLUSH_KEYBOARD:
  lda kb_wptr
  sta kb_rptr
  rts


keyboard_interrupt:
  bit kb_mode
  bpl @classic
  jmp kbx_interrupt          ; extended mode (PROGRAM segment)
@classic:
  pha
  txa
  pha
  
  lda PORTAK
  tax
  
  lda kb_flags
  and #RELEASE
  beq read_key

  lda kb_flags
  eor #RELEASE
  sta kb_flags
  
  cpx #$12
  beq shift_up
  cpx #$59
  beq shift_up
  jmp exit

shift_up:
  lda kb_flags
  and #<~SHIFT               ; clear it (with EOR a lost Shift stayed "stuck")
  sta kb_flags
  jmp exit

read_key:
  cpx #$f0
  beq key_release
  cpx #$12
  beq shift_down
  cpx #$59
  beq shift_down

  lda kb_flags
  and #SHIFT
  bne shifted_key

  lda keymap, x
  jmp push_key

shifted_key:
  lda keymap_shifted, x

push_key:
  cmp #'?'
  beq exit
  
  ; **LOG CHARACTER TO DEBUG**
  pha
  phx
  ldx DEBUG_PTR
  cpx #$80
  bcs @skip_log
  sta DEBUG_LOG, x
  inc DEBUG_PTR
@skip_log:
  plx
  pla
  
  ; Write to the buffer
  ldx kb_wptr
  sta kb_buffer, x
  inc kb_wptr
  jmp exit

shift_down:
  lda kb_flags
  ora #SHIFT
  sta kb_flags
  jmp exit

key_release:
  lda kb_flags
  ora #RELEASE
  sta kb_flags

exit:
  pla
  tax
  pla
  rts

keymap:
  .byte "????????????? `?"
  .byte "?????q1???zsaw2?"
  .byte "?cxde43?? vftr5?"
  .byte "?nbhgy6???mju78?"
  .byte "?,kio09??./l;p-?"
  .byte "??", $27, "?[=????",$0d,"]?", $5c, "??"
  .byte "??????",$08,"??1?47???"
  .byte "0.2568",$1B,"??+3-*9??"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"

keymap_shifted:
  .byte "????????????? ~?"
  .byte "?????Q!???ZSAW@?"
  .byte "?CXDE#$?? VFTR%?"
  .byte "?NBHGY^???MJU&*?"
  .byte "?<KIO)(??>?L:P_?"
  .byte "??", $22, "?{+?????", $0d, "}?", $7c, "??"
  .byte "?????????1?47???"
  .byte "0.2568???+3-*9??"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"
  .byte "????????????????"

; =============================================================================
; EXTENDED KEYBOARD MODE (in the program ROM: the CODE segment is almost full)
; Turned on with KB_SET_MODE (JT_KB_SET_MODE). Codes returned in the buffer:
;   ASCII $20-$7E, Enter $0D, Backspace $08, Tab $09, Esc $1B
;   Ctrl+letter  $01-$1A         Alt+letter  $E1-$FA (lowercase letter + $80)
;   $80 up  $81 down  $82 left  $83 right  $84 Home  $85 End
;   $86 PgUp  $87 PgDn  $88 Ins  $89 Delete   $90-$9B F1-F12
; The numeric keypad always gives digits (as if Num Lock were on).
; Caps Lock swaps upper/lower case of letters only (the LED does not light up:
; the keyboard board only receives).
; =============================================================================
.segment "PROGRAM"

; A = 0 classic mode, A <> 0 extended mode. Clears the Shift/Ctrl/Alt/Caps state.
; Preserves A, X, Y.
KB_SET_MODE:
  pha
  cmp #0
  beq @set
  lda #KB_MODE_EXT
@set:
  sta kb_mode
  stz kb_flags
  pla
  rts

; Decodes the scancode on PORTAK (called by keyboard_interrupt
; when kb_mode bit 7 = 1). Preserves A, X, Y.
kbx_interrupt:
  pha
  phx
  phy
  ldx PORTAK                 ; scancode (the read also clears CA1)
  lda kb_flags
  cpx #$F0
  bne @not_f0
  ora #RELEASE               ; the next code is a release
  bra @store
@not_f0:
  cpx #$E0
  bne @code
  ora #KB_E0                 ; the next code is an extended key
@store:
  sta kb_flags
  jmp @done

@code:
  tay                        ; Y = flags with the prefixes of this key
  and #<~(RELEASE | KB_E0)
  sta kb_flags               ; prefixes consumed
  lda #KB_CTRL
  cpx #$14                   ; Ctrl (left $14, right E0 $14)
  beq @mod
  lda #KB_ALT
  cpx #$11                   ; Alt (left $11, right E0 $11)
  beq @mod
  tya
  and #KB_E0
  bne @ext
  lda #SHIFT
  cpx #$12                   ; left Shift
  beq @mod
  cpx #$59                   ; right Shift
  beq @mod
  tya
  and #RELEASE
  beq @make
  jmp @done                  ; release of a normal key: nothing
@make:
  cpx #$58                  ; Caps Lock: toggles at every press
  bne @plain
  lda kb_flags
  eor #KB_CAPS
  sta kb_flags
  bra @done

@mod:                        ; A = modifier bit: pressed -> 1, released -> 0
  pha
  tya
  and #RELEASE
  beq @mod_down
  pla
  eor #$FF
  and kb_flags
  bra @mod_store
@mod_down:
  pla
  ora kb_flags
@mod_store:
  sta kb_flags
  bra @done

@ext:                        ; E0 + code (the fake Shifts E0 12 / E0 59 are not in the table)
  tya
  and #RELEASE
  bne @done
  txa
  ldx #(kbx_e0_vals - kbx_e0_keys - 1)
@find:
  cmp kbx_e0_keys,x
  beq @found
  dex
  bpl @find
  bra @done
@found:
  lda kbx_e0_vals,x
  bra @push

@plain:
  cpx #$84                   ; no keys beyond F7 ($83)
  bcs @done
  lda kb_flags
  and #SHIFT
  beq @unshifted
  lda kbx_map_shifted,x
  bra @got
@unshifted:
  lda kbx_map,x
@got:
  beq @done                  ; 0 = key without a code
  tax                        ; X = character
  and #$DF                   ; uppercase, only to recognize letters
  cmp #'A'
  bcc @not_letter
  cmp #'Z'+1
  bcs @not_letter
  lda kb_flags
  and #KB_CAPS
  beq @no_caps
  txa
  eor #$20                   ; Caps Lock: swaps upper/lower case
  tax
@no_caps:
  lda kb_flags
  and #KB_CTRL
  beq @no_ctrl
  txa
  and #$1F                   ; Ctrl+letter -> $01-$1A
  bra @push
@no_ctrl:
  lda kb_flags
  and #KB_ALT
  beq @not_letter
  txa
  ora #$A0                   ; Alt+letter -> lowercase + $80 ($E1-$FA)
  bra @push
@not_letter:
  txa
@push:
  ldx kb_wptr
  sta kb_buffer,x
  inc kb_wptr
@done:
  ply
  plx
  pla
  rts

; keys with the E0 prefix -> code
kbx_e0_keys:
  .byte $75,$72,$6B,$74,$6C,$69,$7D,$7A,$70,$71,$5A,$4A
kbx_e0_vals:
  .byte $80,$81,$82,$83,$84,$85,$86,$87,$88,$89,$0D,'/'

; scancode set 2 $00-$83 -> code (0 = none); generated by a script
kbx_map:
  .byte $00,$98,$00,$94,$92,$90,$91,$9B,$00,$99,$97,$95,$93,$09,$60,$00   ; $00
  .byte $00,$00,$00,$00,$00,$71,$31,$00,$00,$00,$7A,$73,$61,$77,$32,$00   ; $10
  .byte $00,$63,$78,$64,$65,$34,$33,$00,$00,$20,$76,$66,$74,$72,$35,$00   ; $20
  .byte $00,$6E,$62,$68,$67,$79,$36,$00,$00,$00,$6D,$6A,$75,$37,$38,$00   ; $30
  .byte $00,$2C,$6B,$69,$6F,$30,$39,$00,$00,$2E,$2F,$6C,$3B,$70,$2D,$00   ; $40
  .byte $00,$00,$27,$00,$5B,$3D,$00,$00,$00,$00,$0D,$5D,$00,$5C,$00,$00   ; $50
  .byte $00,$5C,$00,$00,$00,$00,$08,$00,$00,$31,$00,$34,$37,$00,$00,$00   ; $60
  .byte $30,$2E,$32,$35,$36,$38,$1B,$00,$9A,$2B,$33,$2D,$2A,$39,$00,$00   ; $70
  .byte $00,$00,$00,$96                                                   ; $80
kbx_map_shifted:
  .byte $00,$98,$00,$94,$92,$90,$91,$9B,$00,$99,$97,$95,$93,$09,$7E,$00   ; $00
  .byte $00,$00,$00,$00,$00,$51,$21,$00,$00,$00,$5A,$53,$41,$57,$40,$00   ; $10
  .byte $00,$43,$58,$44,$45,$24,$23,$00,$00,$20,$56,$46,$54,$52,$25,$00   ; $20
  .byte $00,$4E,$42,$48,$47,$59,$5E,$00,$00,$00,$4D,$4A,$55,$26,$2A,$00   ; $30
  .byte $00,$3C,$4B,$49,$4F,$29,$28,$00,$00,$3E,$3F,$4C,$3A,$50,$5F,$00   ; $40
  .byte $00,$00,$22,$00,$7B,$2B,$00,$00,$00,$00,$0D,$7D,$00,$7C,$00,$00   ; $50
  .byte $00,$7C,$00,$00,$00,$00,$08,$00,$00,$31,$00,$34,$37,$00,$00,$00   ; $60
  .byte $30,$2E,$32,$35,$36,$38,$1B,$00,$9A,$2B,$33,$2D,$2A,$39,$00,$00   ; $70
  .byte $00,$00,$00,$96                                                   ; $80

.endif