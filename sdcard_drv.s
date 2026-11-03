.segment "BIOS"
.ifdef BOOGS

; =============================================================================
; 6502 SD CARD DRIVER - ALL SD CARDS (SDSC v1/v2 up to 2GB, SDHC/SDXC)
; Based on the driver of 08-04-2026 (2GB SD, byte addressing).
; 27-10-2026: card type detection (CMD8/CMD58), addresses in SECTORS
; (converted to bytes for SDSC), command timeouts, writing (CMD24) and
; single sector read/write for programs (jump table).
; =============================================================================

PORTA_SD = $DD81
DDRA_SD  = $DD83

SD_CS    = %00010000        ; PA4 - OUTPUT
SD_SCK   = %00001000        ; PA3 - OUTPUT
SD_MOSI  = %00000100        ; PA2 - OUTPUT
SD_MISO  = %00000010        ; PA1 - INPUT

PORTA_SD_OUTPUTPINS = SD_CS | SD_SCK | SD_MOSI

sd_tmp            = $44
zp_sd_cmd_address = $45 ;2 byte
sd_zp_ptr         = $47 ;2 byte
sd_sector         = $49 ;4 byte: sector number (512 bytes), big endian: $49 = bits 31-24 ... $4C = bits 7-0
sd_retry          = $4D ; retry counter during init
sd_slot           = $4E ; requested program slot (0-based)
cmd17_ram         = $0300    ; Command buffer in RAM outside ZP (6 bytes: opcode, address, CRC)

sd_type           = $030A    ; card type: 0 = not initialized/missing
SD_TYPE_SC1       = 1        ;   SDSC v1 (byte address)
SD_TYPE_SC2       = 2        ;   SDSC v2 (byte address)
SD_TYPE_HC        = 3        ;   SDHC/SDXC (sector address)
sd_resp           = $030B    ; 4 bytes: R3/R7 response (OCR / CMD8 echo)
sd_retry_hi       = $030F    ; outer counter of the ACMD41 retries

; Load variables (RAM outside ZP, 6 consecutive bytes: check that $0310-$0315 are free)
sd_len            = $0310    ; 2 bytes: bytes still to copy into RAM
sd_start          = $0312    ; 2 bytes: RAM load address of the program
sd_entry          = $0314    ; 2 bytes: run address (entry point) of the program

; PUBLIC parameter of SD_READ_SECTOR / SD_WRITE_SECTOR (fixed address, do not move it):
SD_LBA            = $0316    ; 4 bytes: sector number, little endian ($0316 = bits 7-0)

; "[TYPE] Name" line for the serial terminal (30-10-2026): type and name of the slot are copied here
; by sd_get_params, because loading the program overwrites the directory at $1000.
sd_ann_type       = $031A    ; entry type: 0 unknown (no line), 1 GAME, 2 APP, 3 TOOL, 4 SOUND
sd_ann_name       = $031B    ; 32 bytes: name to send on the serial, terminated by $00
sd_ann_max        = 31       ; maximum characters

sd_buffer_start   = $1000    ; RAM buffer of the directory sector (and default program address)
sd_slot_sectors   = $40      ; 32KB block per program on the SD = 64 sectors
sd_load_sectors   = $08      ; the program data is at block + $1000 = 8 sectors
sd_min_load       = $0F00    ; lowest RAM address allowed for loading (protects ZP, stack, $0300-$04FF...)
sd_max_end        = $8000    ; first address that can NOT be written (end of RAM)
sd_dir_version    = 3        ; directory version made by make_sd.py (3 = paged)
sd_dir_version_min = 2       ; v2 (a single page, max 9 programs) is still accepted
sd_page_size      = 9        ; programs per directory page
sd_dir_params     = 16       ; offset of the parameter table: 8 bytes per program
; PAGED program directory (version 3). Every page holds 9 programs and takes the
; first sector (512 bytes) of the 32KB block with the SAME number as the page: page P is
; at P * $8000 (the reserved area of the blocks is never loaded into RAM). The page read goes to
; sd_buffer_start ($1000-$11FF).  Slot S (0..254) is in page S/9, entry S mod 9.
;   +0..3   magic "BOGS"   +4 version (3)   +5 number of programs IN THIS PAGE (1..9)
;   +6..14  flags of entries 0..8 of the page (bit0=1: the menu RUNS it after loading)
;   +15     TOTAL number of programs (0 in v2 directories: total = +5)
;   +16 + i*8  parameters of entry i: load (lo,hi), length in bytes (lo,hi), entry (lo,hi),
;              type (0 unknown, 1 GAME, 2 APP, 3 TOOL), name length for the serial (0 = all)
;              (these last two bytes were reserved: the standard BIOS ignores them)
;   +96 + i*32 name of entry i (ASCII, max 31 characters + $00)

; ==========================================
; ENTRY POINT: INIT AND READING
; Input:  A = program slot number (0-based, 0..254).
; Output: C=0 ok (program in RAM; sd_start/sd_entry = load/run addresses)
;         C=1 error (no valid SD, directory not valid, slot does not exist or parameters
;                    out of range); A/X/Y always preserved.
; Every program is in a 32KB block: slot N starts at sector N * 64 and its data
; at sector N * 64 + 8 (= byte N * $8000 + $1000). Load address, length and
; entry point are read from the directory: RAM is written ONLY in [load, load+length).
; ==========================================
INIT_SDCARD:
  PHA
  PHX
  PHY
  STA sd_slot                ; save the requested slot (PHA/PHX/PHY do not touch A)
  SEI                        ; Disable interrupts during the SPI read
  JSR sd_card_init           ; card init (CMD0 / CMD8 / ACMD41 / CMD58)
  BCS sd_exit_err

  LDA sd_slot
  JSR sd_slot_div9           ; X = directory page of the slot (slot / 9)
  TXA
  JSR sd_dir_setup           ; 1) reads the directory page into sd_buffer_start
  JSR sd_read_loop
  BCS sd_exit_err
  JSR sd_get_params          ; 2) checks the directory and takes load/len/entry of the slot
  BCS sd_exit_err

  ; 3) sector = slot * 64 + 8   (the low 6 bits of slot * 64 are zero)
  LDA sd_slot
  JSR sd_block_addr          ; sd_sector = slot * 64
  LDA sd_sector+3
  ORA #sd_load_sectors       ; + 8 sectors ($1000 bytes)
  STA sd_sector+3
  JSR sd_read_loop           ; copies sd_len bytes into RAM from sd_start
  BCS sd_exit_err
  BRA sd_exit_ok

; ==========================================
; SD_READ_DIR: reads a directory page (program names) into RAM
; $1000-$11FF and RETURNS. Input: A = page number (0-based). Only touches $1000-$11FF.
; Output: C=0 (the caller checks whether the content is valid: if the card is missing or the
; read fails the first byte of the buffer is 0, so the directory is not valid).
; ==========================================
SD_READ_DIR:
  PHA
  PHX
  PHY
  STA sd_slot                ; (sd_slot is reused to keep the page during the init)
  SEI
  STZ sd_buffer_start        ; magic not valid until the read succeeds
  JSR sd_card_init
  BCS sd_exit_ok
  LDA sd_slot
  JSR sd_dir_setup
  JSR sd_read_loop
  BCC sd_exit_ok
  STZ sd_buffer_start        ; read interrupted: directory not valid
  ; (falls through to sd_exit_ok)

; --- common exits: C=0 ok / C=1 error. No instruction after CLC/SEC touches the Carry ---
sd_exit_ok:
  CLC
  BRA sd_exit
sd_exit_err:
  SEC
sd_exit:
  ; PS/2 keyboard: during the SEI the scancodes (e.g. the release of the key pressed to choose
  ; the program) were not handled: the $F0 prefix is lost and after the CLI the last scancode
  ; would be read as a NEW key, skipping any "press a key". So everything that arrived
  ; in the meantime is dropped: empty buffer, RELEASE/SHIFT flags cleared, CA1 cleared.
  LDA kb_wptr
  STA kb_rptr                ; empties the keyboard buffer
  STZ kb_flags               ; consistent keyboard state (no pending RELEASE/SHIFT)
  LDA #%00000010
  STA IFR                    ; clears the CA1 flag (like FLUSH_KEYBOARD_HARD does)
  CLI                        ; Enable interrupt
  PLY
  PLX
  PLA
  RTS

; ==========================================
; Loads slot A and runs it (JMP to the entry point of the program).
; Point of no return: on success it never does RTS. The caller (BIOS or an
; SD program through JT_LOAD_RUN_SLOT) must get here with JMP and not with JSR, because
; the code it would return to could be overwritten by the load itself.
; On error it goes back to the BIOS menu.
; ==========================================
LOAD_AND_RUN_SLOT:
  JSR INIT_SDCARD
  BCS @err
  JSR SD_ANNOUNCE            ; "[TYPE] Name" on the serial
  JMP (sd_entry)             ; runs the program just loaded
@err:
  JMP SHOW_MENU

; ==========================================
; SD_INIT (JT_SD_INIT): initializes (or initializes again, e.g. after a card change) the SD.
; Output: C=0 ok, A = type (1 SDSC v1, 2 SDSC v2, 3 SDHC/SDXC)
;         C=1 no card or card not recognized, A = 0.
; Preserves X, Y and the I flag.
; ==========================================
SD_INIT:
  PHP
  PHX
  PHY
  SEI
  JSR sd_card_init
  PLY
  PLX
  LDA sd_type                ; (LDA does not touch the Carry)
  BCS sd_flag_err
  PLP
  CLC
  RTS
sd_flag_err:
  PLP
  SEC
  RTS

; ==========================================
; SD_READ_SECTOR (JT_SD_READ_SECTOR) / SD_WRITE_SECTOR (JT_SD_WRITE_SECTOR)
; Input:  SD_LBA ($0316-$0319, little endian) = number of the 512 byte sector,
;         X = buffer address (low byte), Y = high byte. The buffer is 512 bytes.
; Output: C=0 ok, C=1 error. Preserves A, X, Y and the I flag.
; If the card is not initialized yet (sd_type = 0) it initializes it.
; The sector is always a sector number, also on SDSC cards (the conversion is internal).
; At the end Shift/Ctrl/Alt and the keyboard CA1 flag are cleared (as in sd_exit, the
; prefixes that arrived during the SD access are lost); Caps Lock and the buffer stay.
; ==========================================
SD_READ_SECTOR:
  PHP
  PHA
  PHX
  PHY
  SEI
  STX sd_zp_ptr
  STY sd_zp_ptr+1
  JSR sd_sector_setup
  BCS sd_sector_exit
  STZ sd_len                 ; one sector: 512 bytes
  LDA #$02
  STA sd_len+1
  JSR sd_read_loop
  BRA sd_sector_exit

SD_WRITE_SECTOR:
  PHP
  PHA
  PHX
  PHY
  SEI
  STX sd_zp_ptr
  STY sd_zp_ptr+1
  JSR sd_sector_setup
  BCS sd_sector_exit
  JSR sd_write_block

sd_sector_exit:              ; C = result (LDA/AND/STA do not touch the Carry)
  LDA kb_flags
  AND #KB_CAPS
  STA kb_flags
  LDA #%00000010
  STA IFR                    ; clears the CA1 flag
  PLY
  PLX
  PLA
  BCS sd_flag_err
  PLP
  CLC
  RTS

; sd_sector_setup: initializes the card if needed and copies SD_LBA (little endian) to sd_sector.
; Output: C=1 if the card does not answer.
sd_sector_setup:
  LDA sd_type
  BNE @ready
  JSR sd_card_init
  BCS @end
@ready:
  LDA SD_LBA
  STA sd_sector+3
  LDA SD_LBA+1
  STA sd_sector+2
  LDA SD_LBA+2
  STA sd_sector+1
  LDA SD_LBA+3
  STA sd_sector
  CLC
@end:
  RTS

; ==========================================
; sd_block_addr: A = block number n -> sd_sector = n * 64 (32KB block = 64 sectors)
; Clobbers A and X.
; ==========================================
sd_block_addr:
  STZ sd_sector              ; bits 31-24
  STZ sd_sector+1            ; bits 23-16
  STZ sd_sector+2            ; bits 15-8
  LDX #6
@shift:
  ASL                        ; n << 6 on 16 bits
  ROL sd_sector+2
  DEX
  BNE @shift
  STA sd_sector+3            ; bits 7-0
  RTS

; ==========================================
; sd_slot_div9: A = slot -> A = slot mod 9 (entry in the page), X = slot / 9 (page)
; ==========================================
sd_slot_div9:
  LDX #0
@l:
  CMP #sd_page_size
  BCC @d
  SBC #sd_page_size          ; Carry is 1 after the CMP
  INX
  BRA @l
@d:
  RTS

; ==========================================
; sd_dir_setup: A = page. Prepares the read of its directory sector
; (sector 0 of 32KB block number A) -> sd_buffer_start (512 bytes)
; ==========================================
sd_dir_setup:
  JSR sd_block_addr          ; sector = page * 64
  LDA #0
  STA sd_len                 ; length $0200
  LDA #<sd_buffer_start
  STA sd_zp_ptr
  LDA #>sd_buffer_start
  STA sd_zp_ptr+1
  LDA #$02
  STA sd_len+1
  RTS

; ==========================================
; sd_get_params: checks the directory page just read and takes the parameters of the slot.
; Output: C=0 ok (sd_start, sd_zp_ptr = load; sd_len = length; sd_entry = entry)
;         C=1 error
; ==========================================
sd_get_params:
  LDX #3                     ; magic "BOGS" (4 bytes, from the last to the first)
@magic:
  LDA sd_buffer_start,X
  CMP sd_magic,X
  BNE @bad
  DEX
  BPL @magic
  LDA sd_buffer_start+4
  CMP #sd_dir_version_min
  BCC @bad                   ; directory too old
  CMP #(sd_dir_version+1)
  BCS @bad                   ; directory of a newer version
  LDA sd_slot
  JSR sd_slot_div9           ; A = entry in the page (the page is the one just read)
  CMP sd_buffer_start+5
  BCS @bad                   ; entry >= programs in the page
  ASL
  ASL
  ASL                        ; slot * 8
  TAX
  LDA sd_buffer_start+sd_dir_params,X
  STA sd_start
  STA sd_zp_ptr
  LDA sd_buffer_start+sd_dir_params+1,X
  STA sd_start+1
  STA sd_zp_ptr+1
  LDA sd_buffer_start+sd_dir_params+2,X
  STA sd_len
  LDA sd_buffer_start+sd_dir_params+3,X
  STA sd_len+1
  LDA sd_buffer_start+sd_dir_params+4,X
  STA sd_entry
  LDA sd_buffer_start+sd_dir_params+5,X
  STA sd_entry+1

  ; limits: load >= sd_min_load, length > 0, load + length <= sd_max_end
  LDA sd_start+1
  CMP #>sd_min_load
  BCC @bad
  LDA sd_len
  ORA sd_len+1
  BEQ @bad
  CLC
  LDA sd_start
  ADC sd_len
  TAX                        ; X = low part of the end address
  LDA sd_start+1
  ADC sd_len+1               ; A = high part, Carry = beyond $FFFF
  BCS @bad
  CMP #>sd_max_end
  BCC @ok                    ; < $8000
  BNE @bad                   ; > $80xx
  CPX #0
  BNE @bad                   ; $80xx with xx != 0
@ok:
  JSR sd_save_announce
  CLC
  RTS
@bad:
  SEC
  RTS

; ==========================================
; sd_save_announce: copies type and name of the slot (directory page in sd_buffer_start) to
; sd_ann_type / sd_ann_name. The name is cut to the length in byte +7 of the parameters
; (make_sd.py puts there the length without the " - GAME" suffix of the menu; 0 = whole name).
; Uses zp_sd_cmd_address as pointer (it is set again before every SD command). Clobbers A, X, Y.
; ==========================================
sd_save_announce:
  LDA sd_slot
  JSR sd_slot_div9           ; A = entry in the page (0..8)
  PHA
  ASL
  ASL
  ASL
  TAX                        ; X = entry * 8
  LDA sd_buffer_start+sd_dir_params+6,X
  STA sd_ann_type
  LDA sd_buffer_start+sd_dir_params+7,X
  PHA                        ; name length for the serial
  ; pointer = sd_buffer_start + 96 + entry * 32 (entry * 32 reaches 256: the high byte is needed)
  STZ zp_sd_cmd_address+1
  TSX
  LDA $0102,X                ; A = entry (below the length on the stack)
  LDY #5
@mul:
  ASL
  ROL zp_sd_cmd_address+1
  DEY
  BNE @mul
  CLC
  ADC #<(sd_buffer_start+96)
  STA zp_sd_cmd_address
  LDA zp_sd_cmd_address+1
  ADC #>(sd_buffer_start+96)
  STA zp_sd_cmd_address+1
  PLX                        ; X = length (0 = whole)
  BNE @len_ok
  LDX #sd_ann_max
@len_ok:
  CPX #(sd_ann_max+1)
  BCC @copy0
  LDX #sd_ann_max
@copy0:
  LDY #0
@copy:
  LDA (zp_sd_cmd_address),Y
  BEQ @end
  STA sd_ann_name,Y
  INY
  DEX
  BNE @copy
  LDA #0
@end:
  STA sd_ann_name,Y          ; terminator
  PLA                        ; removes the entry from the stack
  RTS

; ==========================================
; SD_ANNOUNCE: sends "[TYPE] Name" + CR LF ONLY on the serial (not on the screen), with the type and
; the name saved by the last successful INIT_SDCARD. Type 0 or unknown: no line.
; Never blocks: like CHROUT it writes to ACIA_DATA and waits with a fixed delay (W65C51
; bug), so without a serial board nothing happens. Preserves A, X, Y.
; ==========================================
SD_ANNOUNCE:
  PHA
  PHX
  PHY
  LDX sd_ann_type
  BEQ @end
  CPX #5
  BCS @end                   ; unknown type
  LDA #'['
  JSR sd_ser_out
  LDY sd_ann_tofs-1,X
@type:
  LDA sd_ann_tstr,Y
  BEQ @type_end
  JSR sd_ser_out
  INY
  BRA @type
@type_end:
  LDA #']'
  JSR sd_ser_out
  LDA #' '
  JSR sd_ser_out
  LDY #0
@name:
  LDA sd_ann_name,Y
  BEQ @name_end
  JSR sd_ser_out
  INY
  CPY #sd_ann_max
  BCC @name
@name_end:
  LDA #$0D
  JSR sd_ser_out
  LDA #$0A
  JSR sd_ser_out
@end:
  PLY
  PLX
  PLA
  RTS

; sd_ser_out: A -> serial only (like CHROUT but without print_crt_ch)
sd_ser_out:
  STA ACIA_DATA
  LDA #$FF
@txdelay:
  DEC
  BNE @txdelay
  RTS

sd_ann_tofs:    .byte 0, 5, 9, 14          ; type 1..4 -> position in sd_ann_tstr
sd_ann_tstr:    .byte "GAME", 0, "APP", 0, "TOOL", 0, "SOUND", 0

; ==========================================
; sd_card_init: card init sequence
;   80 clocks, CMD0 (up to 8 tries), CMD8: "illegal" -> SDSC v1, $1AA echo -> v2,
;   CMD55/ACMD41 (HCS=1 on v2) until the card is ready (max ~3 s),
;   v2: CMD58 -> OCR CCS bit = SDHC/SDXC; SDSC: CMD16 = 512 byte blocks.
; Output: C=0 ok (sd_type = 1/2/3), C=1 no card or error (sd_type = 0).
; ==========================================
sd_card_init:
  STZ sd_type

  ; Hardware Conf VIA
  LDA #PORTA_SD_OUTPUTPINS
  STA DDRA_SD

; --- Sinc SD (80 clock cycles) ---
  LDA #SD_CS | SD_MOSI       ; CS HIGH, MOSI HIGH
  STA PORTA_SD
  LDX #$A0                   ; 160 trans = 80 cycles

SD_PREINIT:
  EOR #SD_SCK
  STA PORTA_SD
  DEX
  BNE SD_PREINIT

; --- CMD0: the card enters SPI mode (answer $01 = idle) ---
  LDA #8
  STA sd_retry
@cmd0:
  LDA #<cmd0_bytes
  LDX #>cmd0_bytes
  JSR sd_cmd_at
  CMP #$01
  BEQ @cmd8
  DEC sd_retry
  BNE @cmd0
  JMP @fail                  ; no card

; --- CMD8: v2 cards answer with the $1AA echo, v1 cards with "illegal command" ---
@cmd8:
  LDA #<cmd8_bytes
  LDX #>cmd8_bytes
  JSR sd_cmd_r7
  AND #$04                   ; "illegal command" bit
  BNE @v1
  LDA sd_resp+3
  CMP #$AA                   ; echo of the check pattern
  BNE @fail
  LDA #SD_TYPE_SC2
  BRA @set_type
@v1:
  LDA #SD_TYPE_SC1
@set_type:
  STA sd_type                ; temporary: decides the ACMD41 argument

; --- CMD55 + ACMD41 until the card leaves the idle state (256 x 4 tries) ---
  STZ sd_retry
  LDA #4
  STA sd_retry_hi
@acmd_loop:
  LDA #<cmd55_bytes
  LDX #>cmd55_bytes
  JSR sd_cmd_at
  LDA sd_type
  CMP #SD_TYPE_SC1
  BEQ @a41_v1
  LDA #<acmd41hc_bytes       ; v2: HCS=1 (the host accepts SDHC/SDXC)
  LDX #>acmd41hc_bytes
  BRA @a41
@a41_v1:
  LDA #<acmd41_bytes
  LDX #>acmd41_bytes
@a41:
  JSR sd_cmd_at
  CMP #$00                   ; Answer waiting R1 = 0 (Ready)
  BEQ @ready
  DEC sd_retry
  BNE @acmd_loop
  DEC sd_retry_hi
  BNE @acmd_loop
  BRA @fail

@ready:
  LDA sd_type
  CMP #SD_TYPE_SC1
  BEQ @blklen
  ; --- v2: CMD58 reads the OCR, the CCS bit (bit 30) tells whether the address is in sectors ---
  LDA #<cmd58_bytes
  LDX #>cmd58_bytes
  JSR sd_cmd_r7
  CMP #$00
  BNE @fail
  LDA sd_resp
  AND #$40                   ; CCS
  BEQ @blklen
  LDA #SD_TYPE_HC
  STA sd_type
  CLC
  RTS

@blklen:
  ; --- SDSC: 512 byte blocks (usually already so, but it is not guaranteed) ---
  LDA #<cmd16_bytes
  LDX #>cmd16_bytes
  JSR sd_cmd_at
  CMP #$00
  BNE @fail
  CLC
  RTS

@fail:
  STZ sd_type
  SEC
  RTS

; ==========================================
; sd_set_cmd: A = opcode (CMD17 $51 / CMD24 $58). Prepares in cmd17_ram the command with
; the address of sd_sector: in sectors for SDHC/SDXC, in bytes (sector * 512) for SDSC.
; ==========================================
sd_set_cmd:
  STA cmd17_ram
  LDA #$01                   ; Dummy CRC
  STA cmd17_ram+5
  LDA sd_type
  CMP #SD_TYPE_HC
  BNE @bytes
  LDA sd_sector
  STA cmd17_ram+1
  LDA sd_sector+1
  STA cmd17_ram+2
  LDA sd_sector+2
  STA cmd17_ram+3
  LDA sd_sector+3
  STA cmd17_ram+4
  RTS
@bytes:                      ; sector << 9 = (sector << 8) << 1
  LDA sd_sector+1
  STA cmd17_ram+1
  LDA sd_sector+2
  STA cmd17_ram+2
  LDA sd_sector+3
  STA cmd17_ram+3
  STZ cmd17_ram+4
  ASL cmd17_ram+3
  ROL cmd17_ram+2
  ROL cmd17_ram+1
  RTS

; ==========================================
; sd_read_loop: reads from the SD (from sd_sector, 512 byte sectors) and writes to RAM from (sd_zp_ptr)
; EXACTLY sd_len bytes: the rest of the last partial sector is read and dropped,
; so RAM outside [ptr, ptr+len) is never touched.
; Output: C=0 ok, C=1 error (command refused or data token not arrived).
; ==========================================
sd_read_loop:
@next:
  LDA sd_len
  ORA sd_len+1
  BNE @go
  CLC
  RTS                        ; nothing more to copy
@go:
  LDA #$51                   ; CMD17
  JSR sd_set_cmd
  LDA #<cmd17_ram
  LDX #>cmd17_ram
  JSR sd_cmd_at
  CMP #$00
  BEQ @cmd_ok
  SEC                        ; command refused (e.g. address beyond the card)
  RTS
@cmd_ok:
  JSR sd_wait_token          ; Waiting Data Token ($FE)
  BCC @token_ok
  RTS                        ; C=1: error
@token_ok:

  LDA sd_len+1
  CMP #2
  BCS @full                  ; at least 512 bytes left: whole sector

  ; --- last partial sector: copies only sd_len bytes, then drops the rest ---
  LDY #0
  LDX #2                     ; 2 pages of 256 bytes
@by:
  LDA sd_len
  ORA sd_len+1
  BEQ @drop                  ; useful bytes finished: read and drop
  JSR sd_readbyte
  STA (sd_zp_ptr),Y
  LDA sd_len
  BNE @dl
  DEC sd_len+1
@dl:
  DEC sd_len
  BRA @cont
@drop:
  JSR sd_readbyte
@cont:
  INY
  BNE @by
  INC sd_zp_ptr+1
  DEX
  BNE @by
  BRA @crc

@full:
  ; --- whole sector: 512 bytes (256 + 256) ---
  LDY #0
  LDX #0
@p1:
  JSR sd_readbyte
  STA (sd_zp_ptr),Y
  INY
  DEX
  BNE @p1
  INC sd_zp_ptr+1            ; To next RAM page
@p2:
  JSR sd_readbyte
  STA (sd_zp_ptr),Y
  INY
  DEX
  BNE @p2
  INC sd_zp_ptr+1            ; Next Block
  DEC sd_len+1
  DEC sd_len+1               ; sd_len -= 512

@crc:
  JSR sd_readbyte            ; JMP CRC 1
  JSR sd_readbyte            ; JMP CRC 2

  ; next sector
  INC sd_sector+3
  BNE @again
  INC sd_sector+2
  BNE @again
  INC sd_sector+1
  BNE @again
  INC sd_sector
@again:
  JMP @next                  ; (JMP: the loop body is longer than a branch)

; sd_wait_token: waits for the $FE token that comes before the data of a block (max ~1.5 s).
; Output: C=0 token arrived, C=1 error token or timeout. Clobbers X and Y.
sd_wait_token:
  LDX #$20
  LDY #0
@l:
  JSR sd_readbyte
  CMP #$FE
  BEQ @ok
  CMP #$FF
  BNE @bad                   ; error token (0000xxxx)
  DEY
  BNE @l
  DEX
  BNE @l
@bad:
  SEC
  RTS
@ok:
  CLC
  RTS

; ==========================================
; sd_write_block: writes the 512 bytes of (sd_zp_ptr) to sector sd_sector (CMD24).
; Output: C=0 ok, C=1 error (command refused, data not accepted or card busy for too long).
; ==========================================
sd_write_block:
  LDA #$58                   ; CMD24
  JSR sd_set_cmd
  LDA #<cmd17_ram
  STA zp_sd_cmd_address
  LDA #>cmd17_ram
  STA zp_sd_cmd_address+1
  JSR sd_cmd_send            ; CS stays low until the end of the write
  CMP #$00
  BNE @fail
  LDA #$FF
  JSR sd_writebyte           ; one wait byte before the token
  LDA #$FE
  JSR sd_writebyte           ; "start of data" token
  LDY #0
@p1:
  LDA (sd_zp_ptr),Y
  JSR sd_writebyte
  INY
  BNE @p1
  INC sd_zp_ptr+1
@p2:
  LDA (sd_zp_ptr),Y
  JSR sd_writebyte
  INY
  BNE @p2
  LDA #$FF
  JSR sd_writebyte           ; CRC (ignored in SPI mode)
  JSR sd_writebyte
  JSR sd_readbyte            ; data response: xxx00101 = data accepted
  AND #$1F
  CMP #$05
  BNE @fail
  LDX #0                     ; wait for the end of the write: the card keeps MISO at 0 (max ~12 s)
  LDY #0
@busy:
  JSR sd_readbyte
  CMP #$00
  BNE @done
  DEY
  BNE @busy
  DEX
  BNE @busy
@fail:
  JSR sd_cmd_release
  SEC
  RTS
@done:
  JSR sd_cmd_release
  CLC
  RTS

; ==========================================
; SUBROUTINES
; ==========================================

; sd_cmd_at: A = low byte, X = high byte of the 6 command bytes. Sends the command,
; A = R1 response ($FF = no response), then releases CS.
sd_cmd_at:
  STA zp_sd_cmd_address
  STX zp_sd_cmd_address+1
sd_sendcommand:
  JSR sd_cmd_send
sd_cmd_release:              ; CS HIGH + idle clocks; preserves A
  PHA
  LDA #SD_CS | SD_MOSI       ; CS HIGH
  STA PORTA_SD
  JSR sd_readbyte            ; Dummy clocks
  PLA
  RTS

; sd_cmd_r7: like sd_cmd_at, but also reads the 4 bytes that follow R1 (R3/R7 responses) into sd_resp
sd_cmd_r7:
  STA zp_sd_cmd_address
  STX zp_sd_cmd_address+1
  JSR sd_cmd_send
  PHA
  LDY #0
@r:
  JSR sd_readbyte
  STA sd_resp,Y
  INY
  CPY #4
  BNE @r
  PLA
  BRA sd_cmd_release

; sd_cmd_send: sends the 6 bytes of (zp_sd_cmd_address) with CS low and waits for R1 (CS stays low)
sd_cmd_send:
  LDA #SD_MOSI               ; CS LOW
  STA PORTA_SD
  LDY #0
SD_LOOP:
  LDA (zp_sd_cmd_address),Y
  JSR sd_writebyte
  INY
  CPY #6
  BNE SD_LOOP
  ; (falls through to sd_waitresult)

; sd_waitresult: reads until a byte other than $FF arrives (max ~2000 bytes, ~0.4 s).
; The R1 response comes within 8 bytes: the timeout is only needed if the card is missing.
sd_waitresult:
  LDX #$08
SD_OUTER:
  LDY #$FF
SD_INNER:
  JSR sd_readbyte
  CMP #$FF
  BNE SD_DONE
  DEY
  BNE SD_INNER
  DEX
  BNE SD_OUTER
SD_DONE:
  RTS

sd_writebyte:
  PHA
  PHX
  STA sd_tmp                 ;
  LDX #8                     ;
@loop:
  ASL sd_tmp                 ; bit MSB into Carry
  LDA #0                     ; Preparing MOSI=0
  BCC @skip_high             ; IF bit = 0, JMP
  LDA #SD_MOSI               ; IF bit = 1, MOSI=1
@skip_high:
  STA PORTA_SD               ; Send bit bit (MOSI)
  ORA #SD_SCK                ; SCK HIGH (Clock On)
  STA PORTA_SD               ;
  EOR #SD_SCK                ; SCK LOW (Clock Off)
  STA PORTA_SD               ;
  DEX                        ;
  BNE @loop
  PLX
  PLA                  ;
  RTS                        ;

sd_readbyte:
  PHX
  LDA #0
  STA sd_tmp
  LDX #8
SD_RL:
  LDA #SD_MOSI        ; Put MOSI HIGH and SCK LOW at same time
  STA PORTA_SD
  ORA #SD_SCK         ; SCK going HIGH
  STA PORTA_SD
  LDA PORTA_SD        ; Read bit
  AND #SD_MISO
  CLC
  BEQ SD_RN
  SEC
SD_RN:
  ROL sd_tmp
  DEX
  BNE SD_RL
  LDA sd_tmp          ; Result in A
  PLX
  RTS

; --- STATIC COMMAND DATA ---
sd_magic:       .byte "BOGS"
cmd0_bytes:     .byte $40, $00, $00, $00, $00, $95
cmd8_bytes:     .byte $48, $00, $00, $01, $AA, $87
cmd16_bytes:    .byte $50, $00, $00, $02, $00, $01
cmd55_bytes:    .byte $77, $00, $00, $00, $00, $01
acmd41_bytes:   .byte $69, $00, $00, $00, $00, $01
acmd41hc_bytes: .byte $69, $40, $00, $00, $00, $01
cmd58_bytes:    .byte $7A, $00, $00, $00, $00, $01
cmd17_bytes:    .byte $51, $00, $00, $00, $00, $01

.endif
