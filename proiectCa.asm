; auth: JavaKet (Mitran Andrei)
; computes frame buffer size + I2C timing
; prints to screen & simulates sending a line to Arduino over COM1.
; 

org 100h
jmp start

; Inputs
WIDTH       dw 320
HEIGHT      dw 240
BPP         dw 2 ; bytes per pixel
APB_KHZ     dd 80000 ; 80 MHz = 80000 kHz
SCL_KHZ     dw 400 ; 400
                                         
;Nota bene: apb khz must be dd because dw is 16 bits and we dont want that
; we need 32 bit because we will overwflow at 65535 otherwise                                         
                                         
;outputs
FRAME_LO    dw 0
FRAME_HI    dw 0 ;hi low frame bites (32 bits)

TOTAL_CYC   dw 0
HIGH_CYC    dw 0
LOW_CYC     dw 0
WH_LO       dw 0
WH_HI       dw 0

REM_CYC     dw 0
OUT_NR      dw 0 ; output counter

msgTitle    db 13,10,'Computation Results',13,10,'$'

msgOutNr    db 'Output nr = $'
msgFrame    db 13,10,'Frame bytes = $'
msgI2C      db 13,10,'I2C: total_cycles = $'
msgHigh     db 13,10,'I2C: high_cycles  = $'
msgLow      db 13,10,'I2C: low_cycles   = $'
msgWH       db 13,10,'W*H = $'
msgBPP      db 13,10,'BPP = $'
msgAPB      db 13,10,'APB_KHZ = $'
msgSCL      db 13,10,'SCL_KHZ = $'
msgRem      db 13,10,'I2C: remainder    = $'
msgNL       db 13,10,'$'

msgSend     db 13,10,'Sending to COM1 as: $'
msgAgain    db 13,10,13,10,'Press R to recompute, ESC to quit$'

; sim serial buffer
COMBUF      db 128 dup(0)
COMIDX      dw 0

; FB=<u32>,T=<u16>,H=<u16>,L=<u16>\r\n

start:
main_loop:
    call ComputeAll
    call PrintResults
    call SimSendResultsToCom1

    lea dx, msgAgain
    call PrintStr

    ; wait key
    mov ah, 00h
    int 16h
    cmp al, 27 ; ESC
    je  exit
    cmp al, 'r'
    je  main_loop
    cmp al, 'R'
    je  main_loop
    jmp main_loop

exit:
    mov ax, 4C00h
    int 21h

ComputeAll:
    ; output counter
    inc word ptr [OUT_NR]

    ; frame_bytes = WIDTH * HEIGHT * BPP 
    mov ax, [WIDTH]
    mov bx, [HEIGHT]
    mul bx ; DX:AX = WIDTH*HEIGHT

    ; save W*H for display/debug
    mov [WH_LO], ax
    mov [WH_HI], dx

    ; mult 32bit (DX:AX) by 16bit BPP
    mov bx, [BPP]

    push dx ; save WH_hi
    push ax ; and WH_lo

    ; low_part = WH_lo * BPP
    pop ax
    mul bx ; DX:AX = low_part
    mov [FRAME_LO], ax
    mov [FRAME_HI], dx

    ; high_part = WH_hi * BPP shifted by 16 => add into FRAME_HI
    pop ax ; AX = WH_hi
    xor dx, dx
    mul bx ; DX:AX = high_part
    add [FRAME_HI], ax ; add shifted contribution

    ; I2C total cycles: TOTAL = APB_KHZ / SCL_KHZ
    mov ax, word ptr [APB_KHZ] ; low word
    mov dx, word ptr [APB_KHZ+2] ; high word
    mov bx, [SCL_KHZ]
    call DivU32ByU16

    ; store quotient + remainder for display/debug
    mov [TOTAL_CYC], ax
    mov [REM_CYC], dx

    ; high = total / 2
    mov ax, [TOTAL_CYC]
    shr ax, 1
    mov [HIGH_CYC], ax

    ; low = total - high
    mov ax, [TOTAL_CYC]
    sub ax, [HIGH_CYC]
    mov [LOW_CYC], ax

    ret

PrintResults:                                      ;print results logic
   
    lea dx, msgTitle
    call PrintStr

    ; Output nr
    lea dx, msgOutNr
    call PrintStr
    mov ax, [OUT_NR]
    call PrintU16
    lea dx, msgNL
    call PrintStr

    ; Frame bytes 32bit
    lea dx, msgFrame
    call PrintStr
    mov dx, [FRAME_HI]
    mov ax, [FRAME_LO]
    call PrintU32
    lea dx, msgNL
    call PrintStr

    ; total cycles
    lea dx, msgI2C
    call PrintStr
    mov ax, [TOTAL_CYC]
    call PrintU16

    ; high cycles
    lea dx, msgHigh
    call PrintStr
    mov ax, [HIGH_CYC]
    call PrintU16

    ; low cycles
    lea dx, msgLow
    call PrintStr
    mov ax, [LOW_CYC]
    call PrintU16

    lea dx, msgNL
    call PrintStr
    
    ;debug displays for the computation steps

    ; W*H
    lea dx, msgWH
    call PrintStr
    mov dx, [WH_HI]
    mov ax, [WH_LO]
    call PrintU32

    ; BPP
    lea dx, msgBPP
    call PrintStr
    mov ax, [BPP]
    call PrintU16

    ; APB_KHZ (32-bit)
    lea dx, msgAPB
    call PrintStr
    mov ax, word ptr [APB_KHZ]
    mov dx, word ptr [APB_KHZ+2]
    call PrintU32

    ; SCL_KHZ
    lea dx, msgSCL
    call PrintStr
    mov ax, [SCL_KHZ]
    call PrintU16

    ; remainder from APB_KHZ SCL_KHZ
    lea dx, msgRem
    call PrintStr
    mov ax, [REM_CYC]
    call PrintU16

    lea dx, msgNL
    call PrintStr
    ret

; sim for sendin the frame buffer to com1
SimSendResultsToCom1:
    ; reset buffer index
    mov word ptr [COMIDX], 0

    ;"FB="
    mov al, 'F'; build buffer
    call BufPutChar
    mov al, 'B'
    call BufPutChar
    mov al, '='
    call BufPutChar

    ;FB value (u32)
    mov dx, [FRAME_HI]
    mov ax, [FRAME_LO]
    call BufPutU32

    mov al, ','
    call BufPutChar
    mov al, 'T'
    call BufPutChar
    mov al, '='
    call BufPutChar
    mov ax, [TOTAL_CYC]
    call BufPutU16

    mov al, ','
    call BufPutChar
    mov al, 'H'
    call BufPutChar
    mov al, '='
    call BufPutChar
    mov ax, [HIGH_CYC]
    call BufPutU16

    mov al, ','
    call BufPutChar
    mov al, 'L'
    call BufPutChar
    mov al, '='
    call BufPutChar
    mov ax, [LOW_CYC]
    call BufPutU16

    ; line end \r\n 
    
    mov al, 13
    call BufPutChar
    mov al, 10
    call BufPutChar

    ;terminate for PrintStr ($)
    
    mov al, '$'
    call BufPutChar

    ;display
    lea dx, msgSend
    call PrintStr
    lea dx, COMBUF
    call PrintStr
    lea dx, msgNL
    call PrintStr
    ret
;append AL into COMBUF at COMIDX

BufPutChar:
    push bx
    push di

    mov bx, [COMIDX]
    lea di, COMBUF
    add di, bx
    mov [di], al
    inc bx
    mov [COMIDX], bx

    pop di
    pop bx
    ret

;append unsigned 16-bit AX in decimal to COMBUF
BufPutU16:
    push ax
    push bx
    push cx
    push dx

    mov cx, 0
    mov bx, 10
    cmp ax, 0
    jne b16_loop
    mov al, '0'
    call BufPutChar
    jmp b16_done

b16_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    cmp ax, 0
    jne b16_loop

b16_print:
    pop dx
    add dl, '0'
    mov al, dl
    call BufPutChar
    loop b16_print

b16_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

;append unsigned 32bit DX:AX in decimal to COMBUF
BufPutU32:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov si, ax
    or  si, dx
    jne b32_conv
    mov al, '0'
    call BufPutChar
    jmp b32_out

b32_conv:
    mov cx, 0
    mov bx, 10

b32_next:
; divide 32bit DX:AX by 10
    mov si, ax
    mov di, dx

                                       ; q_high = high/10, rem_high = high%10
    mov ax, di
    xor dx, dx
    div bx
    mov di, ax ; q_high
                                      ; q_low = (rem_high<<16 + low)/10
    mov ax, si
    div bx             ; AX=q_low, DX=remainder
    mov si, ax          ; !!! IMPORTANT: update quotient low !!!

    push dx
    inc cx

    mov dx, di
    mov ax, si
    mov si, ax
    or  si, dx
    jne b32_next

b32_print:
    pop dx
    add dl, '0'
    mov al, dl
    call BufPutChar
    loop b32_print

b32_out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; input:  DX:AX = numerator 32 bit & BX    = divisor 16 bit
; output: AX    = quotient 7 DX    = remainder
DivU32ByU16:
    push si
    push di

    mov si, ax      ; low
    mov di, dx      ; high

    ; q_high = high / BX, rem_high = high % BX
    mov ax, di
    xor dx, dx
    div bx          ; AX=q_high, DX=rem_high

    ; Now divide (rem_high<<16 + low) by BX
    mov ax, si      ; low in AX, rem_high already in DX
    div bx          ; AX=q_low, DX=remainder

    pop di
    pop si
    ret

; DS:DX points to '$'-terminated string
PrintStr:
    mov ah, 09h
    int 21h
    ret

; prints unsigned 16-bit AX in decimal
PrintU16:
    push ax
    push bx
    push cx
    push dx

    mov cx, 0
    mov bx, 10
    cmp ax, 0
    jne pu16_loop
    mov dl, '0'
    mov ah, 02h
    int 21h
    jmp pu16_done

pu16_loop:
    xor dx, dx
    div bx
    push dx
    inc cx
    cmp ax, 0
    jne pu16_loop

pu16_print:
    pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    loop pu16_print

pu16_done:
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; prints unsigned 32bit DX:AX in decimal/
PrintU32:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov si, ax
    or  si, dx
    jne pu32_conv
    mov dl, '0'
    mov ah, 02h
    int 21h
    jmp pu32_out

pu32_conv:
    mov cx, 0
    mov bx, 10

pu32_next:
    mov si, ax
    mov di, dx

    mov ax, di
    xor dx, dx
    div bx
    mov di, ax

    mov ax, si
    div bx          
    mov si, ax          
    push dx
    inc cx

    mov dx, di
    mov ax, si
    mov si, ax
    or  si, dx
    jne pu32_next

pu32_print:
    pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    loop pu32_print

pu32_out:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret
