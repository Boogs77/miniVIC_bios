; ============================================================
; SYSTEM VECTOR TABLE ("KERNAL" style, like C64 / Apple //)
; ------------------------------------------------------------
; FIXED, stable addresses: any program loaded from SD
; (including SD0, the dynamic "SD menu") calls the BIOS services
; ONLY through these addresses, NEVER through the internal labels
; of the BIOS (CHROUT, INIT_SDCARD, etc.), which can move
; every time the BIOS is rebuilt/changed.
;
; GOLDEN RULE: once an address below has been "published"
; (that is, once SD programs exist that use it), do not
; move it and do not reassign it. New entries are added ONLY
; at the end of the table.
; ============================================================
.segment "JUMPTBL"

JT_CHROUT:          jmp CHROUT              ; $FD00 - A=character to print
JT_CHRIN_NOECHO:    jmp CHRIN_NO_ECHO       ; $FD03 - Carry=1+A=key if pressed, Carry=0 if none
JT_RESET_TERM:      jmp RESET_SERIAL_TERM  ; $FD06 - ANSI reset of the serial terminal
JT_INIT_CRT:        jmp INIT_CRT            ; $FD09 - reset of the local CRT cursor
JT_LOAD_RUN_SLOT:   jmp LOAD_AND_RUN_SLOT   ; $FD0C - A=SD slot, loads the program (load/length/entry from the directory) AND RUNS IT; error -> BIOS menu (never RTS: call with JMP)
JT_SHOW_MENU:       jmp SHOW_MENU           ; $FD0F - back to the BIOS main menu (never RTS: call with JMP)
JT_INIT_SDCARD:     jmp INIT_SDCARD         ; $FD12 - A=SD slot, loads the program (load/length from the directory) and RETURNS without running it: C=0 ok, C=1 error
JT_FLUSH_KB:        jmp FLUSH_KEYBOARD_HARD ; $FD15 - empties the keyboard buffer/state (~0.5 s, saves A/X/Y): call it before a "press a key"
; --- added on 27-10-2026 (BIOS KEYB_SD) ---
JT_SD_READ_SECTOR:  jmp SD_READ_SECTOR      ; $FD18 - reads sector SD_LBA ($0316-$0319, little endian) into the buffer X/Y (lo/hi, 512 bytes): C=0 ok, C=1 error; preserves A/X/Y
JT_SD_WRITE_SECTOR: jmp SD_WRITE_SECTOR     ; $FD1B - writes the buffer X/Y (512 bytes) to sector SD_LBA: C=0 ok, C=1 error; preserves A/X/Y
JT_SD_INIT:         jmp SD_INIT             ; $FD1E - (re)initializes the SD: C=0 ok and A=type (1 SDSC v1, 2 SDSC v2, 3 SDHC/SDXC), C=1 no card (A=0)
JT_KB_SET_MODE:     jmp KB_SET_MODE         ; $FD21 - A=0 classic keyboard, A<>0 extended (arrows $80-$89, F1-F12 $90-$9B, Ctrl+letter $01-$1A, Alt+letter $E1-$FA, Caps Lock); the menu sets classic again
