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
                jsr     CHROUT			; serial echo OK
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
    ldx kb_rptr
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
                pha
.ifdef BOOGS                
                jsr     print_crt_ch ; mod from miniPET
.endif

                sta     ACIA_DATA
                lda     #$FF
@txdelay:       dec
                bne     @txdelay
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

