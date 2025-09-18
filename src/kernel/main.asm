; ___                   _                   _____ _     _      ___  ____  
;/ _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___| 
;| | | \ \ / / _` | '_ \| __| | | | '_ ` _ \| |_  | / __| '_ \| | | \___ \ 
;| |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |
; \__\_\ \_/ \__,_|_| |_|\__|\__,_|_| |_| |_|_|   |_|___/_| |_|\___/|____/ 

org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

start:
    jmp main


puts:
    push si 
    push ax 

.loop:  
    lodsb   
    or al, al
    jz .done 

    mov ah, 0x0e
    mov bh, 0
    int 0x10  
    
    jmp .loop   
    
.done
    pop ax      
    pop si      
    ret         

main:
    mov ax, 0
    mov ds, ax
    mov es, ax

    mov ss, ax
    mov sp, 0x7C00

    mov si, msg_hello
    call puts

.halt
    jmp .halt


msg_hello db 'Welcome to QvantumFishOS', ENDL, 0

times 510-($-$$) db 0

dw 0AA55h

