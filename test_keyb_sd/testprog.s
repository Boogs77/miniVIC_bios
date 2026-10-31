; Test driver for the KEYB_SD BIOS: commands arrive in a RAM mailbox from the test harness
.setcpu "65C02"
.segment "CODE"
MBOX   = $0FF0      ; 1 read sector, 2 write sector, 3 SD init, 4 kb extended, 5 kb classic
RES_C  = $0FF1
RES_A  = $0FF2
RES_X  = $0FF3
RES_Y  = $0FF4
KEYS_N = $0FF5
KEYS   = $2000
BUF    = $3000
start:
  sei
  ldx #$FF
  txs
  stz MBOX
  stz KEYS_N
loop:
  lda MBOX
  beq keys
  ldx #<BUF
  ldy #>BUF
  cmp #1
  bne :+
  jsr $FD18
  bra done
: cmp #2
  bne :+
  jsr $FD1B
  bra done
: cmp #3
  bne :+
  jsr $FD1E
  bra done
: cmp #4
  bne :+
  lda #1
  jsr $FD21
  bra done
: lda #0
  jsr $FD21
done:
  sta RES_A
  stx RES_X
  sty RES_Y
  lda #0
  rol
  sta RES_C
  stz MBOX
  bra loop
keys:
  jsr $FD03
  bcc loop
  ldx KEYS_N
  sta KEYS,x
  inc KEYS_N
  bra loop
