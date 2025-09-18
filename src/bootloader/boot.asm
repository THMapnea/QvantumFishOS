; ___                   _                   _____ _     _      ___  ____  
;/ _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___| 
;| | | \ \ / / _` | '_ \| __| | | | '_ ` _ \| |_  | / __| '_ \| | | \___ \ 
;| |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |
; \__\_\ \_/ \__,_|_| |_|\__|\__,_|_| |_| |_|_|   |_|___/_| |_|\___/|____/ 

org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A


jmp short start
nop

bdb_oem:                    db 'MSWIN4.1'           ;8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sector:        dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h
bdb_total_sectors:          dw 2880                 ;2880 * 512 = 1.44Mb
bdb_media_descriptor_type:  db 0F0h                 ;F0 = 3.5" floppy disk
bdb_sectors_per_fat:        dw 9                    ;9 sectors/fat
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

ebd_drive_number:           db 0                    ;0x00 floppy, 0x80 hdd
                            db 0                    ;reserved
ebr_signature:              db 29h
ebr_volume_id:              db 13h, 17h, 33h, 69h   ;serial number value doesn't matter
ebr_volume_label:           db 'QvantumFish'        ;11 bytes padded with spaces
ebr_system_id:              db 'FAT12   '           ;8 byt padded with spaces

start:
    jmp main

;function that prints a string to video
;   Params: ds:si point to string
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

    ;printing the welcome
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

.halt
    jmp .halt


msg_q1 db ' ___                   _                   _____ _     _      ___  ____', ENDL, 0
msg_q2 db '/ _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___| ', ENDL, 0
msg_q3 db '| | | \ \ / / _  |  _ \| __| | | |  _   _ \| |_  | / __|  _ \| | | \___ \ ', ENDL, 0
msg_q4 db '| |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |', ENDL, 0
msg_q5 db ' \__\_\ \_/ \__ _|_| |_|\__|\__ _|_| |_| |_|_|   |_|___/_| |_|\___/|____/ ', ENDL, 0

times 510-($-$$) db 0

dw 0AA55h

