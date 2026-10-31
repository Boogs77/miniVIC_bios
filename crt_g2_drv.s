.segment "CODE"
.ifdef BOOGS
NMI_HANDLER:
; The settings are changed again by the program

  PHA
  PHX
  PHY
  JSR $0FD0         ; CALL DISPATCH (IN RAM)
  LDA VREG          ; acknowledge VDP
  PLY
  PLX
  PLA
  RTI
.endif