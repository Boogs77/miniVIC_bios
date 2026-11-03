.segment "PROGRAM"
.define BIOS_VER "03.11.26 KEYB/SD"

ZP_PTR = $40
ZP_PTR2 = $42

; PAGED SD directory (version 3). Page P (9 programs) is in the first sector of
; 32KB block number P and is read by SD_READ_DIR (A = page) into RAM $1000-$11FF:
;   +0..3 "BOGS"   +4 version (3)   +5 number of programs IN THIS PAGE (1..9)
;   +6..14 flags of entry 0..8 (bit0 = 1: after loading RUN at the entry point; 0: load only)
;   +15 TOTAL number of programs (0 in v2 directories with a single page: total = +5)
;   +16 + i*8: load/length/entry of entry i (used by the SD driver)
;   +96 + i*32: name of entry i (max 31 chars + $00)
; The slot to load = page * 9 + entry.
SD_DIR_BUF    = $1000
SD_DIR_COUNT  = SD_DIR_BUF+5
SD_DIR_FLAGS  = SD_DIR_BUF+6
SD_DIR_TOTAL  = SD_DIR_BUF+15
SD_DIR_HDR    = 96
SD_DIR_VER    = 3
SD_DIR_VER_MIN = 2          ; v2 directories (one page) still work
SD_DIR_ESIZE  = 32
SD_PAGE_SIZE  = 9           ; one key ('1'..'9') per program, 9 programs per page

; SD menu state: RAM right after the directory buffer. It lives only while the menu is active
; (a load can overwrite it, but by then it is no longer needed).
MENU_PAGE     = $1200       ; page shown (0-based)
MENU_PAGES    = $1201       ; number of pages
MENU_TOTAL    = $1202       ; total number of programs
MENU_IDX      = $1203       ; entry chosen in the page (0..8)
MENU_CAT      = $1204       ; submenu: 0 ALL (SD pages as they are), 1 GAMES, 2 APPS, 3 SOUNDS
MENU_FCNT     = $1205       ; number of programs in the submenu (1..255)
MENU_SCAN     = $1206       ; directory page being scanned
MENU_DPAGES   = $1207       ; number of directory pages on the SD
MENU_TMP      = $1208       ; scratch byte

; Submenu (MENU_CAT 1..3): sd_scan reads every directory page once and keeps the matching programs
; in RAM. A page of the submenu is then rebuilt at $1000 in the same layout as a directory page,
; so sd_draw works the same way for both.
FILT_SLOT     = $1300       ; SD slot of program n of the submenu
FILT_FLAG     = $1400       ; flags of program n
FILT_NAME     = $2000       ; 32-byte name of program n (255 * 32 = $1FE0 bytes, up to $3FDF)

; directory type byte (+6 of the entry parameters): 1 GAME, 2 APP, 3 TOOL, 4 SOUND
SD_DIR_TYPE   = SD_DIR_BUF+16+6

KEY_ESC       = $1B
KEY_PREV      = 'A'         ; previous page ('a' is accepted too)
KEY_NEXT      = 'D'         ; next page ('d' is accepted too)

    ;jsr INIT_SDCARD
SHOW_MENU:
    jsr FLUSH_KEYBOARD_HARD
    JSR INIT_SERIAL                         ;from serial_drv
    JSR INIT_KEYBOARD 
    stz sd_type                             ; SD to be initialized again (RAM is random at power-on)
    jsr RESET_SERIAL_TERM                   ; Send ANSI codes to clear terminal
    jsr INIT_CRT                             ;from keyboard_drv
    ;jsr RESET_SERIAL_TERM                   ; Send ANSI codes to clear terminal         
    ldx #$FF
    txs
    jsr print_boot_menu       ; Display Logo and Main Menu options

wait_key_main:
    jsr CHRIN_NO_ECHO                ; Call BIOS character input
    bcc wait_key_main         ; Carry clear means no key, keep checking
    
    cmp #'1'            
    beq go_woz                ; '1' -> Jump to Woz Monitor
    cmp #'2'            
    beq go_basic              ; '2' -> Jump to MS BASIC
    cmp #'3'            
    beq go_sdcard            ; '3' -> SD menu: GAMES / APPS / SOUNDS / ALL
    cmp #'4'            
    bne wait_key_main         ; other keys: ignore
    jmp go_info               ; '4' -> System Info (jmp: the beq no longer reaches after the additions to the SD submenu)

go_woz:
    jsr FLUSH_KEYBOARD_HARD  
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT
    jmp RESET           

go_basic:
    jsr FLUSH_KEYBOARD_HARD  
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT
    jmp $8000           

go_sdcard:
    jsr FLUSH_KEYBOARD_HARD
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT

    ; --- Paged SD submenu: names and parameters are in the directory pages of the SD ---
    lda #<sys_sd_reading
    ldx #>sys_sd_reading
    jsr print_str               ; "READING SD DIRECTORY..."

    lda #0
    sta MENU_PAGE
    jsr SD_READ_DIR             ; A = 0: page 0 -> RAM $1000-$11FF (only touches that area)
    jsr sd_validate
    bcc @dir_ok
    jmp sd_dir_bad
@dir_ok:

    lda SD_DIR_TOTAL            ; total programs (v3)...
    bne @tot_ok
    lda SD_DIR_COUNT            ; ...or, in a v2 directory, the programs of page 0
@tot_ok:
    sta MENU_TOTAL
    jsr sd_calc_pages
    stx MENU_DPAGES
    jmp sd_cat_menu

; sd_calc_pages: A = number of programs (1..255) -> X = pages of 9, rounded up
sd_calc_pages:
    ldx #0
@pg:
    inx
    sec
    sbc #SD_PAGE_SIZE
    beq @pg_done                ; remainder 0: exact pages
    bcs @pg                     ; some are still left
@pg_done:
    rts

; ---------------------------------------------------------------
; submenu choice: 1 GAMES, 2 APPS (APP and TOOL), 3 SOUNDS, 4 ALL
; ---------------------------------------------------------------
sd_cat_menu:
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT
    lda #<sys_cat_text
    ldx #>sys_cat_text
    jsr print_str
    jsr FLUSH_KEYBOARD_HARD
@wait:
    jsr CHRIN_NO_ECHO
    bcc @wait
    cmp #KEY_ESC
    bne @not_esc
    jmp SHOW_MENU               ; ESC -> back to the main menu
@not_esc:
    cmp #'4'
    beq @all
    cmp #'1'
    bcc @wait
    cmp #'3'+1
    bcs @wait                   ; only '1'..'4'
    sec
    sbc #'0'
    sta MENU_CAT                ; 1..3
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT
    lda #<sys_sd_reading
    ldx #>sys_sd_reading
    jsr print_str               ; "READING SD DIRECTORY..." (one read per directory page)
    jsr sd_scan
    bcc @scan_ok
    jmp sd_dir_bad
@scan_ok:
    lda MENU_FCNT
    beq @empty
    jsr sd_calc_pages
    stx MENU_PAGES
    stz MENU_PAGE
    jsr sd_build_page
    jmp sd_draw
@empty:
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT
    lda #<sys_cat_empty
    ldx #>sys_cat_empty
    jsr print_str               ; "NO PROGRAMS OF THIS KIND ON THE SD"
@empty_wait:
    jsr CHRIN_NO_ECHO
    bcc @empty_wait
    jmp sd_cat_menu
@all:
    stz MENU_CAT                ; ALL: the SD pages as they are, like the old menu
    lda MENU_DPAGES
    sta MENU_PAGES
    lda #0
    sta MENU_PAGE
    jsr SD_READ_DIR             ; page 0 again (a submenu may have left another page at $1000)
    jsr sd_validate
    bcc @all_ok
    jmp sd_dir_bad
@all_ok:
    jmp sd_draw

; sd_scan: reads every directory page and keeps the programs of submenu MENU_CAT in
; FILT_SLOT/FILT_FLAG/FILT_NAME. Out: MENU_FCNT = how many; C=1 if a page is not valid
sd_scan:
    stz MENU_FCNT
    stz MENU_SCAN
@page:
    lda MENU_SCAN
    jsr SD_READ_DIR             ; page -> $1000
    jsr sd_validate
    bcc @valid
    rts                         ; C=1
@valid:
    stz MENU_IDX                ; entry in the page
@entry:
    lda MENU_IDX
    asl
    asl
    asl
    tay                         ; Y = entry * 8 (parameters)
    lda SD_DIR_TYPE,y
    jsr sd_type_match
    bcc @next
    ldy MENU_FCNT
    lda MENU_SCAN
    asl
    asl
    asl
    clc
    adc MENU_SCAN               ; page * 9
    clc
    adc MENU_IDX                ; + entry = slot
    sta FILT_SLOT,y
    ldx MENU_IDX
    lda SD_DIR_FLAGS,x
    sta FILT_FLAG,y
    lda MENU_IDX
    ldx #>(SD_DIR_BUF+SD_DIR_HDR)
    jsr sd_name_ptr             ; ZP_PTR = name in the directory page
    lda ZP_PTR
    sta ZP_PTR2
    lda ZP_PTR+1
    sta ZP_PTR2+1
    lda MENU_FCNT
    ldx #>FILT_NAME
    jsr sd_name_ptr             ; ZP_PTR = name n in RAM
    jsr sd_copy_name            ; (ZP_PTR2) -> (ZP_PTR)
    inc MENU_FCNT
@next:
    inc MENU_IDX
    lda MENU_IDX
    cmp SD_DIR_COUNT
    bne @entry
    inc MENU_SCAN
    lda MENU_SCAN
    cmp MENU_DPAGES
    bne @page
    clc
    rts

; sd_type_match: A = type byte. C=1 if it belongs to submenu MENU_CAT
sd_type_match:
    ldx MENU_CAT
    cpx #2
    bne @one
    cmp #3                      ; APPS: APP (2) and TOOL (3)
    beq @yes
    bra @cmp
@one:
    cpx #3
    bne @cmp                    ; GAMES: type 1 = MENU_CAT
    ldx #4                      ; SOUNDS: type 4
@cmp:
    stx MENU_TMP
    cmp MENU_TMP
    beq @yes
    clc
    rts
@yes:
    sec
    rts

; sd_name_ptr: ZP_PTR = (X * 256 + offset of the low byte) + A * 32
;   X = high byte of the table: $10 for the names at $1060 (low byte $60), $20 for FILT_NAME
sd_name_ptr:
    pha
    lsr
    lsr
    lsr                         ; A * 32 / 256
    stx ZP_PTR+1
    clc
    adc ZP_PTR+1
    sta ZP_PTR+1
    pla
    asl
    asl
    asl
    asl
    asl                         ; (A * 32) and 255
    cpx #>FILT_NAME
    beq @no_ofs                 ; FILT_NAME starts at a page boundary
    clc
    adc #<(SD_DIR_BUF+SD_DIR_HDR)
    bcc @no_ofs
    inc ZP_PTR+1
@no_ofs:
    sta ZP_PTR
    rts

; sd_copy_name: copies 32 bytes from (ZP_PTR2) to (ZP_PTR)
sd_copy_name:
    ldy #SD_DIR_ESIZE-1
@c:
    lda (ZP_PTR2),y
    sta (ZP_PTR),y
    dey
    bpl @c
    rts

; sd_build_page: rebuilds page MENU_PAGE of the submenu at $1000 (count, flags, names)
sd_build_page:
    lda MENU_PAGE
    asl
    asl
    asl
    clc
    adc MENU_PAGE
    sta MENU_SCAN               ; first program of the page (MENU_SCAN is free after sd_scan)
    lda MENU_FCNT
    sec
    sbc MENU_SCAN               ; programs left
    cmp #SD_PAGE_SIZE+1
    bcc @cnt
    lda #SD_PAGE_SIZE
@cnt:
    sta SD_DIR_COUNT
    stz MENU_IDX
@e:
    lda MENU_SCAN
    clc
    adc MENU_IDX
    tay                         ; Y = program n
    ldx MENU_IDX
    lda FILT_FLAG,y
    sta SD_DIR_FLAGS,x
    tya
    ldx #>FILT_NAME
    jsr sd_name_ptr
    lda ZP_PTR
    sta ZP_PTR2
    lda ZP_PTR+1
    sta ZP_PTR2+1               ; source: name n in RAM
    lda MENU_IDX
    ldx #>(SD_DIR_BUF+SD_DIR_HDR)
    jsr sd_name_ptr             ; destination: entry in the page
    jsr sd_copy_name
    inc MENU_IDX
    lda MENU_IDX
    cmp SD_DIR_COUNT
    bne @e
    rts

sd_dir_bad:
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT
    lda #<sys_sd_nodir
    ldx #>sys_sd_nodir
    jsr print_str
    jmp sd_wait                 ; waits for a key and goes back to the main menu

; checks the directory page at $1000: C=0 valid, C=1 not valid
sd_validate:
    lda SD_DIR_BUF              ; magic "BOGS"
    cmp #'B'
    bne @bad
    lda SD_DIR_BUF+1
    cmp #'O'
    bne @bad
    lda SD_DIR_BUF+2
    cmp #'G'
    bne @bad
    lda SD_DIR_BUF+3
    cmp #'S'
    bne @bad
    lda SD_DIR_BUF+4
    cmp #SD_DIR_VER_MIN
    bcc @bad                    ; directory too old (make the SD again with make_sd.py)
    cmp #SD_DIR_VER+1
    bcs @bad                    ; directory of a newer version than this menu
    lda SD_DIR_COUNT
    beq @bad                    ; 0 programs: page not valid
    cmp #SD_PAGE_SIZE+1
    bcs @bad                    ; more than 9 entries in a page: not valid
    clc
    rts
@bad:
    sec
    rts

; ---------------------------------------------------------------
; draws page MENU_PAGE (already read into $1000-$11FF) and handles the keys
; ---------------------------------------------------------------
sd_draw:
    jsr RESET_SERIAL_TERM       ; clears the screen
    jsr INIT_CRT
    ldx MENU_CAT
    lda sys_head_lo,x
    pha
    lda sys_head_hi,x
    tax
    pla
    jsr print_str               ; title of the submenu
    lda #<sys_sd_page
    ldx #>sys_sd_page
    jsr print_str               ; " PAGE "
    lda MENU_PAGE
    clc
    adc #1
    jsr print_dec               ; current page (1-based)
    lda #'/'
    jsr CHROUT
    lda MENU_PAGES
    jsr print_dec               ; total pages
    lda #<sys_sd_gap
    ldx #>sys_sd_gap
    jsr print_str               ; new line + empty line

    lda #<(SD_DIR_BUF+SD_DIR_HDR)
    sta ZP_PTR                  ; ZP_PTR = name of entry 0
    lda #>(SD_DIR_BUF+SD_DIR_HDR)
    sta ZP_PTR+1
    lda #0                      ; A = entry in the page (0-based)
sd_list_loop:
    pha                         ; the index stays on the stack while printing
    lda #' '
    jsr CHROUT
    pla
    pha
    clc
    adc #'1'
    jsr CHROUT                  ; entry number (key to press, 1..9 in every page)
    pla
    pha
    tax                         ; X = entry
    lda SD_DIR_FLAGS,x
    and #$01
    beq @dot
    lda #'>'                    ; "N>" = loads AND RUNS
    bra @mark
@dot:
    lda #'.'                    ; "N." = only loads into RAM
@mark:
    jsr CHROUT
    lda #' '
    jsr CHROUT
    ldy #SD_DIR_ESIZE-1
    lda #0
    sta (ZP_PTR),y              ; $00 forced at the end of the name field (safety)
    jsr print_debug_string      ; name (up to $00)
    lda #$0D
    jsr CHROUT
    lda #$0A
    jsr CHROUT
    clc
    lda ZP_PTR
    adc #SD_DIR_ESIZE           ; next entry
    sta ZP_PTR
    bcc @nc
    inc ZP_PTR+1
@nc:
    pla
    clc
    adc #1
    cmp SD_DIR_COUNT
    bne sd_list_loop

    lda #<sys_sd_foot1
    ldx #>sys_sd_foot1
    jsr print_str               ; empty line
    lda MENU_PAGES
    cmp #2
    bcc @no_nav                 ; a single page: no A/D
    lda #<sys_sd_nav
    ldx #>sys_sd_nav
    jsr print_str               ; " A = PREV PAGE   D = NEXT PAGE"
@no_nav:
    lda #<sys_sd_foot2
    ldx #>sys_sd_foot2
    jsr print_str               ; ESC, legend, "Select > "
    jsr FLUSH_KEYBOARD_HARD     ; drops the A/D release (F0 + code) that arrived during
                                ; SD_READ_DIR and the redraw: the F0 byte gets overwritten and the
                                ; code left over would be read as a new key press

sd_menu_wait:
    jsr CHRIN_NO_ECHO
    bcc sd_menu_wait
    cmp #KEY_ESC
    beq sd_menu_back            ; ESC -> back to the submenu choice
    cmp #'1'
    bcc @not_num                ; below '1'
    cmp #'9'+1
    bcs @not_num                ; above '9'
    sec
    sbc #'1'                    ; key '1'..'9' -> entry 0..8
    cmp SD_DIR_COUNT
    bcs sd_menu_wait            ; beyond the last entry of the page: no action
    sta MENU_IDX
    lda MENU_PAGE
    asl
    asl
    asl                         ; page * 8 (at most 28 * 8)
    clc
    adc MENU_PAGE               ; page * 9
    clc
    adc MENU_IDX                ; + entry = slot (ALL) or program n (submenu)
    ldx MENU_CAT
    beq @slot
    tax
    lda FILT_SLOT,x             ; submenu: SD slot of program n
@slot:
    jmp sd_do_copy              ; A = slot

@not_num:
    and #$DF                    ; lowercase -> UPPERCASE
    cmp #KEY_NEXT
    beq @next
    cmp #KEY_PREV
    bne sd_menu_wait            ; other keys: ignore
@prev:
    lda MENU_PAGES
    cmp #2
    bcc sd_menu_wait            ; a single page
    lda MENU_PAGE
    bne @p_dec
    lda MENU_PAGES              ; from the first page wrap to the last one
@p_dec:
    sec
    sbc #1
    bra @p_go
@next:
    lda MENU_PAGES
    cmp #2
    bcc sd_menu_wait            ; a single page
    lda MENU_PAGE
    clc
    adc #1
    cmp MENU_PAGES
    bcc @p_go
    lda #0                      ; from the last page wrap to the first one
@p_go:
    sta MENU_PAGE
    ldx MENU_CAT
    beq @p_read
    jsr sd_build_page           ; submenu: page rebuilt from RAM, no SD read
    jmp sd_draw
@p_read:
    jsr SD_READ_DIR             ; A = page to read
    jsr sd_validate
    bcc @page_ok
    jmp sd_dir_bad
@page_ok:
    jmp sd_draw

sd_menu_back:
    jmp sd_cat_menu

sd_do_copy:                     ; input: A = slot (0-based), MENU_IDX = entry in the page
    ldx #$FF
    txs
    pha                         ; slot: needed just below, A is busy
    ldx MENU_IDX
    lda SD_DIR_FLAGS,x          ; "run" flag: must be read NOW, the load overwrites the directory
    and #$01
    tax                         ; X = run flag
    pla                         ; A = slot
    phx                         ; on the stack: run flag...
    pha                         ; ...and the slot on top (they stay during reset/prints)
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT

    lda #<sys_sd_loading
    ldx #>sys_sd_loading
    jsr print_str               ; "LOADING..." (the read takes a few seconds)

    pla                         ; A = slot
    plx                         ; X = run flag (0/1); INIT_SDCARD preserves X
    jsr INIT_SDCARD             ; loads the program (page and entry come from the slot); C=1 = error
    bcs sd_load_err
    cpx #0
    beq @load_only
    jsr SD_ANNOUNCE             ; "[TYPE] Name" on the serial only (type 0: nothing)
    jmp (sd_entry)              ; flag=1: RUNS the program at the entry point
@load_only:
    ; flag=0: loaded only. Message with the real addresses (sd_start = load, sd_entry = entry)
    lda #<sys_sd_t1
    ldx #>sys_sd_t1
    jsr print_str               ; "SD PROGRAM LOADED AT $"
    lda sd_start+1
    jsr print_hex
    lda sd_start
    jsr print_hex
    lda #<sys_sd_t2
    ldx #>sys_sd_t2
    jsr print_str               ; "TYPE "
    lda sd_entry+1
    jsr print_hex
    lda sd_entry
    jsr print_hex
    lda #<sys_sd_t3
    ldx #>sys_sd_t3
    jsr print_str               ; "R AND ENTER ON WOZMON" + "Press any key..."
    jmp sd_wait

sd_load_err:
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT
    lda #<sys_sd_err
    ldx #>sys_sd_err
    jsr print_str
    jmp sd_wait

; print_str: A = lo, X = hi of a $00-terminated string
print_str:
    sta ZP_PTR
    stx ZP_PTR+1
    jmp print_debug_string

; print_dec: prints A (0..99) in decimal, without a leading zero. CHROUT can change the registers
print_dec:
    ldx #'0'
@t:
    cmp #10
    bcc @o
    sbc #10                     ; Carry = 1 after the CMP
    inx
    bra @t
@o:
    pha                         ; units
    txa
    cmp #'0'
    beq @u                      ; no leading zero
    jsr CHROUT
@u:
    pla
    ora #'0'
    jmp CHROUT

; print_hex: prints A as two hex digits
print_hex:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr print_nibble
    pla
print_nibble:
    and #$0F
    cmp #$0A
    bcc @dig
    adc #$06                    ; (Carry=1: +7 in total, 'A'-'0'-10)
@dig:
    adc #'0'
    jmp CHROUT

sd_wait:
    jsr CHRIN_NO_ECHO
    bcc sd_wait
    jmp SHOW_MENU

; --- System Information Page ---
go_info:
    jsr FLUSH_KEYBOARD_HARD
    jsr RESET_SERIAL_TERM
    jsr INIT_CRT

    lda #<sys_info_text
    sta ZP_PTR
    lda #>sys_info_text
    sta ZP_PTR+1

info_loop:
    ldy #0
    lda (ZP_PTR), y      ; read the current byte
    beq info_wait        ; $00 terminator -> stop
    jsr CHROUT           ; print (can change everything except ZP_PTR)
    inc ZP_PTR           ; advance the pointer
    bne info_loop        ; if no page overflow, continue
    inc ZP_PTR+1         ; otherwise advance the page
    jmp info_loop

info_wait:
    jsr CHRIN_NO_ECHO
    bcc info_wait
    jmp SHOW_MENU

; --- Print Routines (Full Stack Protection) ---
print_boot_menu:
    pha
    phx
    phy
    jsr print_logo

    lda #<menu_text
    sta ZP_PTR
    lda #>menu_text
    sta ZP_PTR+1
    ldy #0
main_loop:
    lda (ZP_PTR), y
    beq main_exit
    jsr CHROUT
    iny
    bne main_loop
    inc ZP_PTR+1
    jmp main_loop
main_exit:
    jsr print_version
    ply
    plx
    pla
    rts

print_logo:
    pha
    phx
    phy
    lda #<logo_art
    sta ZP_PTR2
    lda #>logo_art
    sta ZP_PTR2+1
    ldy #0
logo_loop:
    lda (ZP_PTR2), y
    beq logo_exit
    jsr CHROUT
    iny
    bne logo_loop
    inc ZP_PTR2+1      ; next page
    jmp logo_loop
logo_exit:
    ply
    plx
    pla
    rts

print_version:
    pha
    phx
    phy
    ldx #0
version_loop:
    lda bios_footer, x
    beq version_exit
    jsr CHROUT
    inx
    jmp version_loop
version_exit:
    ply
    plx
    pla
    rts
;
; --- Serial Terminal ANSI Reset ---
RESET_SERIAL_TERM:
    pha
    lda #$1B        ; ESC character
    jsr CHROUT
    lda #'['
    jsr CHROUT
    lda #'2'
    jsr CHROUT
    lda #'J'        ; Clear Screen command
    jsr CHROUT
    lda #$1B
    jsr CHROUT
    lda #'['
    jsr CHROUT
    lda #'H'        ; Move Cursor to Home (1,1)
    jsr CHROUT
    pla
    rts

;
CHRIN_NO_ECHO:
    ; Check the serial port
    lda     ACIA_STATUS
    and     #$08
    beq     @check_keyboard
    lda     ACIA_DATA
    sec
    rts

@check_keyboard:
    lda     IFR
    and     #$02
    beq     @check_buffer
    jsr     keyboard_interrupt
    lda     #%00000010
    sta     IFR                   ; force clear of CA1

@check_buffer:
    lda     kb_rptr
    cmp     kb_wptr
    beq     @no_key
    ldx     kb_rptr
    lda     kb_buffer, x
    inc     kb_rptr
    sec
    rts

@no_key:
    clc
    rts
;
FLUSH_KEYBOARD_HARD:
    pha
    phx
    phy
    
   lda kb_wptr
   sta kb_rptr
   
    ldx #$FF
@delay1:
    ldy #$FF
@delay2:
    dey
    bne @delay2
    dex
    bne @delay1
    
    lda kb_wptr
    sta kb_rptr
    
    ; Clear interrupt flag
    lda #%00000010
    sta IFR
    
    ply
    plx
    pla
    rts

DELAY_1289u:
  PHX
  LDX #255 ;  
DELAY_4:
  DEX
  BNE DELAY_4
  PLX
  RTS 


DELAY_500ms:
  PHX        ; save X
  PHY        ; save Y
  LDY #$03   ; outer count = 3
DELAY_500_OUTER:
  LDX #$82   ; inner count = 130 (0x82)
DELAY_500_INNER:
  JSR DELAY_1289u
  DEX
  BNE DELAY_500_INNER
  DEY
  BNE DELAY_500_OUTER
  PLY        ; restore Y
  PLX        ; restore X
  RTS


; Quick helper routine to print debug strings on the fly
print_debug_string:
    ldy #0
@db_loop:
    lda (ZP_PTR), y
    beq @db_exit
    jsr CHROUT
    iny
    bne @db_loop
    inc ZP_PTR+1
    jmp @db_loop
@db_exit:
    rts



; --- Data Section (Strings) ---

logo_art:
    
    .byte "----------------------------------------", $0A
    .byte "   ___    ___   ___   ___   ___   ", $0A
    .byte "  / __\  |     |     |   |     |   ", $0A
    .byte "  ||     |___  |___  |   |  ___|   ", $0A
    .byte "  ||__   |   |     | |   | |   ", $0A
    .byte "  \___/  |___| |___| |___| |___   ", $0A
    .byte " ",$0D, $0A
    .byte "---------------MiniVIC------------------", $0A, $00

menu_text:
    .byte " ",$0D, $0A
    .byte " 1. WOZ MONITOR APPLE I", $0D, $0A
    .byte " ",$0D, $0A
    .byte " 2. MICROSOFT BASIC 1977", $0D, $0A
    .byte " ",$0D, $0A
    .byte " 3. SDCARD PROGRAMS MENU", $0D, $0A
    .byte " ",$0D, $0A
    .byte " 4. MiniVIC SYSTEM INFORMATION", $0D, $0A, 0

sys_info_text:
    .byte " ",$0D, $0A
    .byte "   --- MiniVic SYSTEM INFORMATION ---", $0D, $0A
    .byte " ",$0D, $0A
    .byte "CPU : W65C02S 8 bit Microprocessor", $0A
    .byte "CLOCK Frequency:    1MHz", $0D, $0A
    .byte "RAM Memory:         32KB", $0D, $0A
    .byte "RAM Address:        $0000-7FFF", $0D, $0A
    .byte "ROM Memory:         32KB", $0D, $0A
    .byte "ROM Address:        $8000-FFFF", $0D, $0A
    .byte "SERIAL Interface:   DB9", $0D, $0A
    .byte "SERIAL IC: 6551     Address $C000", $0D, $0A
    .byte "KEYBOARD Interface: 5DIN", $0D, $0A
    .byte "KEYBOARD IC: 6522   Address $D180", $0D, $0A
    .byte "VIDEO CRT TEXT:     40x24 character", $0D, $0A
    .byte "VIDEO CRT GRAPHICS: 256x192 pixel", $0D, $0A
    .byte "VIDEO CRT ADDRESS:  $D190", $0D, $0A
    .byte "POWER ADAPTER:      5V DC REGULATED", $0D, $0A
    .byte "VERSION:            ", BIOS_VER , $0D, $0A;, $0A
    .byte "OPERATING SYSTEM:   WozMon", $0D, $0A
    .byte " ",$0D, $0A
    .byte "       --------------------------", $0A
    .byte "            Press any key...     ", 0

sys_sd_loading:
    .byte " ",$0D, $0A
    .byte "LOADING FROM SD, PLEASE WAIT...", $0D, $0A, 0

sys_sd_t1:
    .byte " ",$0D, $0A
    .byte "SD PROGRAM LOADED AT $", 0
sys_sd_t2:
    .byte $0D, $0A
    .byte " ",$0D, $0A
    .byte "TYPE ", 0
sys_sd_t3:
    .byte "R AND ENTER ON WOZMON", $0D, $0A
    .byte " ",$0D, $0A
    .byte "Press any key...     ", 0
sys_sd_err:
    .byte " ",$0D, $0A
    .byte "SD LOAD ERROR", $0D, $0A
    .byte "(CARD, DIRECTORY OR PROGRAM PARAMS)", $0D, $0A
    .byte " ",$0D, $0A
    .byte "Press any key...     ", 0

bios_footer:
    .byte $0D, $0A
    .byte "----------------------------------------", $0A
    .byte "BIOS Version ", BIOS_VER, $0D, $0A
    .byte "Select > ", 0


dbg_msg_1:
    .byte "DEBUG: Avvio INIT_SDCARD...", $0D, $0A, 0
dbg_msg_2:
    .byte "DEBUG: SD caricata con successo! Salto a $1000...", $0D, $0A, 0

sys_sd_reading:
    .byte " ", $0D, $0A
    .byte "READING SD DIRECTORY...", $0D, $0A, 0

sys_cat_text:
    .byte " ", $0D, $0A
    .byte " --- SD PROGRAMS MENU ---", $0D, $0A
    .byte " ", $0D, $0A
    .byte " 1. GAMES", $0D, $0A
    .byte " ", $0D, $0A
    .byte " 2. APPS", $0D, $0A
    .byte " ", $0D, $0A
    .byte " 3. SOUNDS", $0D, $0A
    .byte " ", $0D, $0A
    .byte " 4. ALL PROGRAMS", $0D, $0A
    .byte " ", $0D, $0A
    .byte " ESC = MAIN MENU", $0D, $0A
    .byte " ", $0D, $0A
    .byte "Select > ", 0

sys_cat_empty:
    .byte " ", $0D, $0A
    .byte "NO PROGRAMS OF THIS KIND ON THE SD", $0D, $0A
    .byte "(SD MADE BEFORE THE TYPES? TRY 4. ALL)", $0D, $0A
    .byte " ", $0D, $0A
    .byte "Press any key...     ", 0

; title of the list, by MENU_CAT
sys_head_lo:
    .byte <sys_head_all, <sys_head_games, <sys_head_apps, <sys_head_sounds
sys_head_hi:
    .byte >sys_head_all, >sys_head_games, >sys_head_apps, >sys_head_sounds
sys_head_all:
    .byte " ", $0D, $0A
    .byte " --- SD ALL PROGRAMS ---", $0D, $0A, 0
sys_head_games:
    .byte " ", $0D, $0A
    .byte " --- SD GAMES ---", $0D, $0A, 0
sys_head_apps:
    .byte " ", $0D, $0A
    .byte " --- SD APPS ---", $0D, $0A, 0
sys_head_sounds:
    .byte " ", $0D, $0A
    .byte " --- SD SOUNDS ---", $0D, $0A, 0

sys_sd_page:
    .byte " PAGE ", 0

sys_sd_gap:
    .byte $0D, $0A
    .byte " ", $0D, $0A, 0

sys_sd_foot1:
    .byte " ", $0D, $0A, 0

sys_sd_nav:
    .byte " A = PREV PAGE   D = NEXT PAGE", $0D, $0A, 0

sys_sd_foot2:
    .byte " ESC = BACK", $0D, $0A
    .byte " N> = RUNS AFTER LOADING", $0D, $0A
    .byte " ", $0D, $0A
    .byte "Select > ", 0

sys_sd_nodir:
    .byte " ", $0D, $0A
    .byte "NO VALID SD DIRECTORY FOUND", $0D, $0A
    .byte "(NO CARD, OR NOT MADE BY make_sd.py)", $0D, $0A
    .byte " ", $0D, $0A
    .byte "Press any key...     ", 0