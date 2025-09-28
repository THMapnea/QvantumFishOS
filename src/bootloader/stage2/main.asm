; =============================================================================
; SIMPLE BOOTLOADER FOR NBOS OPERATING SYSTEM
; =============================================================================
;
; Basic bootloader that displays a welcome message on screen
; Loaded by BIOS at address 0x7C00 and must be exactly 512 bytes

org 0x0                  ; BIOS loads bootloader at this address
bits 16                  ; 16-bit real mode

%define ENDL 0x0D, 0x0A 

; =============================================================================
; ENTRY POINT
; =============================================================================

start:
    ; Print welcome messages
    mov si, msg_q1        ; Load address of first message line into SI register
    call puts             ; Call print string function to display first line
    mov si, msg_q2        ; Load address of second message line into SI register
    call puts             ; Call print string function to display second line
    mov si, msg_q3        ; Load address of third message line into SI register
    call puts             ; Call print string function to display third line
    mov si, msg_q4        ; Load address of fourth message line into SI register
    call puts             ; Call print string function to display fourth line
    mov si, msg_q5        ; Load address of fifth message line into SI register
    call puts             ; Call print string function to display fifth line

.halt:
    cli                   ; Clear interrupt flag to disable interrupts
    hlt                   ; Halt processor execution



; =============================================================================
; PUTS FUNCTION
; =============================================================================
;
; Prints a null-terminated string to screen using BIOS interrupt
; Parameters:
;   ds:si - pointer to string to print

puts:
    push si                 ; Save SI register value to stack for preservation
    push ax                 ; Save AX register value to stack for preservation
    push bx                 ; Save BX register value to stack for preservation

.loop:  
    lodsb                   ; Load byte from memory address [SI] into AL register, increment SI
    or al, al               ; Perform logical OR operation to check if AL = 0 (end of string)
    jz .done                ; Jump to done label if zero flag set (end of string reached)

    mov ah, 0x0E            ; Set AH register to 0x0E (BIOS teletype output function)
    mov bh, 0               ; Set BH register to 0 (select video page 0)
    int 0x10                ; Call BIOS video service interrupt 0x10
    
    jmp .loop               ; Unconditional jump back to loop label for next character
    
.done:
    pop bx                  ; Restore BX register value from stack
    pop ax                  ; Restore AX register value from stack
    pop si                  ; Restore SI register value from stack
    ret                     ; Return from function to calling code


; =============================================================================
; WELCOME MESSAGES
; =============================================================================

msg_q1 db '    ___                   _                   _____ _     _      ___  ____', ENDL, 0
msg_q2 db '   / _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___| ', ENDL, 0
msg_q3 db '  | | | \ \ / / _  |  _ \| __| | | |  _   _ \| |_  | / __|  _ \| | | \___ \ ', ENDL, 0
msg_q4 db '  | |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |', ENDL, 0
msg_q5 db '   \__\_\ \_/ \__ _|_| |_|\__|\__ _|_| |_| |_|_|   |_|___/_| |_|\___/|____/ ', ENDL, 0

