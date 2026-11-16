.setcpu "65C02"
.debuginfo
.segment "BIOS"


ACIA_DATA	= $c000
ACIA_STATUS	= $c001
ACIA_CMD	= $c002
ACIA_CTRL	= $c003


LOAD:
                rts

SAVE:
                rts


MONRDKEY:
CHRIN:
                lda     ACIA_STATUS
                and     #$08
                beq     @no_keypressed_serial
                lda     ACIA_DATA
                cmp     #$7F            ; DEL (Backspace of many serial terminals)
                bne     @not_del
                lda     #$08
@not_del:
                cmp     #$08
                beq     @no_echo        ; Backspace: the caller erases (BS_ECHO)
                jsr     CHROUT			; serial echo OK
@no_echo:
                sec
                rts
                
@no_keypressed_serial:
                lda kb_rptr
                cmp kb_wptr
                bne key_pressed
                lda IFR
                and #$02
                beq @no_keypressed_both
                jsr keyboard_interrupt
                jmp @no_keypressed_both

@no_keypressed_both:
                clc
                rts

key_pressed:

    phx                 ; <--- SAVE X (BASIC needs it intact!)
    lda kb_rptr
    and #KB_MASK
    tax
    lda kb_buffer, x
    inc kb_rptr
    
    ; Keep the logic that clears the interrupt
    pha
    lda PORTAK    
    pla

    ; Clear bit 7 for BASIC
    and #$7F

    pha                 ; Save the character for the compare
    cmp #$0D            ; Is it ENTER?
    beq @skip_echo      
    cmp #$08            ; Backspace: the caller erases (BS_ECHO)
    beq @skip_echo
    
    pla                 ; Get the character back for the echo
    jsr CHROUT
    jmp @exit

@skip_echo:
    pla                 ; Get the CR ($0D) back
@exit:
    plx                 ; <--- RESTORE X
    sec
    rts


; Output a character (from the A register) to the serial interface.
;
; Modifies: flags
MONCOUT:
CHROUT:
.ifdef BOOGS                
                jsr     print_crt_ch ; mod from miniPET (preserves A, X, Y)
.endif
; serial only
SER_OUT:
                pha
                sta     ACIA_DATA
                lda     #$FF
@txdelay:       dec
                bne     @txdelay
                pla
                rts

; Erases the last typed character: CRT back one place and erase, "BS space BS" on the
; serial terminal. Preserves A, X, Y.
BS_ECHO:
                pha
                lda     #$08
                jsr     print_crt_ch
                jsr     SER_OUT
                lda     #' '
                jsr     SER_OUT
                lda     #$08
                jsr     SER_OUT
                pla
                rts

IRQ_HANDLER:
  PHA
  PHX
  PHY
  JSR $0FA0         ; CALL DISPATCH (IN RAM)
  PLY
  PLX
  PLA
  RTI


;; LOADING DRIVER
.include "serial_drv.s"
.include "keyboard_drv.s"
.include "boot_menu_multi.s"   ; mod from miniPET
.include "crt_text_drv.s"
.include "crt_g2_drv.s"



; LOADING SOFTWARE  
.include "sdcard_drv.s"
.include "wozmon.s"
.include "jumptable.s" ; SD vector






.segment "RESETVEC"
                .word   NMI_HANDLER       ;$0F00           ; NMI vector
                .word   SHOW_MENU   ; RESET vector
                .word   IRQ_HANDLER ; $0000          ; IRQ vector

