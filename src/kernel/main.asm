; ___                   _                   _____ _     _      ___  ____  
;/ _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___| 
;| | | \ \ / / _` | '_ \| __| | | | '_ ` _ \| |_  | / __| '_ \| | | \___ \ 
;| |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |
; \__\_\ \_/ \__,_|_| |_|\__|\__,_|_| |_| |_|_|   |_|___/_| |_|\___/|____/ 

; =============================================================================
; SIMPLE BOOTLOADER FOR NBOS OPERATING SYSTEM
; =============================================================================
;
; Basic bootloader that displays a welcome message on screen
; Loaded by BIOS at address 0x7C00 and must be exactly 512 bytes

org 0x7C00                  ; BIOS loads bootloader at this address
bits 16                     ; 16-bit real mode

%define ENDL 0x0D, 0x0A     ; Define carriage return + line feed constants

; =============================================================================
; ENTRY POINT
; =============================================================================

start:
    jmp main                ; Jump to main code (bypassing any potential data)



; =============================================================================
; PUTS FUNCTION
; =============================================================================
;
; Prints a null-terminated string to screen using BIOS interrupt
; Parameters:
;   ds:si - pointer to string to print

puts:
    push si                 ; Save registers
    push ax 

.loop:  
    lodsb                   ; Load byte from [si] into AL, increment SI
    or al, al               ; Check if AL = 0 (end of string)
    jz .done 

    mov ah, 0x0e            ; BIOS teletype output function
    mov bh, 0               ; Video page 0
    int 0x10                ; Call BIOS video service
    
    jmp .loop               ; Continue with next character
    
.done:
    pop ax                  ; Restore registers
    pop si      
    ret                     ; Return from function



; =============================================================================
; MAIN FUNCTION
; =============================================================================

main:
    ; Initialize segment registers
    mov ax, 0
    mov ds, ax              ; Data segment = 0
    mov es, ax              ; Extra segment = 0

    ; Initialize stack
    mov ss, ax              ; Stack segment = 0
    mov sp, 0x7C00          ; Stack pointer starts at 0x7C00 (grows downward)

    ; Print welcome messages
    mov si, msg_q1
    call puts
    mov si, msg_q2
    call puts
    mov si, msg_q3
    call puts
    mov si, msg_q4
    call puts
    mov si, msg_q5
    call puts

    ; Infinite loop (placeholder for future kernel loading code)
.halt:
    jmp .halt



; =============================================================================
; WELCOME MESSAGES
; =============================================================================

msg_q1 db ' ___                   _                   _____ _     _      ___  ____', ENDL, 0
msg_q2 db '/ _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___| ', ENDL, 0
msg_q3 db '| | | \ \ / / _  |  _ \| __| | | |  _   _ \| |_  | / __|  _ \| | | \___ \ ', ENDL, 0
msg_q4 db '| |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |', ENDL, 0
msg_q5 db ' \__\_\ \_/ \__ _|_| |_|\__|\__ _|_| |_| |_|_|   |_|___/_| |_|\___/|____/ ', ENDL, 0



; =============================================================================
; BOOT SIGNATURE
; =============================================================================
;
; BIOS requires boot sectors to end with signature 0xAA55
; in the last two bytes to identify as bootable

times 510-($-$$) db 0       ; Fill remainder of sector with zeros
dw 0AA55h                   ; Boot signature (little endian)