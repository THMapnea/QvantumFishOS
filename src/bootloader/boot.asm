;  ___                   _                   _____ _     _      ___  ____
; / _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___|
;| | | \ \ / / _` | '_ \| __| | | | '_ ` _ \| |_  | / __| '_ \| | | \___ \
;| |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |
; \__\_\ \_/ \__,_|_| |_|\__|\__,_|_| |_| |_|_|   |_|___/_| |_|\___/|____/

; =============================================================================
; BOOTLOADER FOR NBOS OPERATING SYSTEM
; =============================================================================
;
; This bootloader follows the FAT12 standard for 1.44MB floppy disks
; and resides in the boot sector (sector 0) of the disk.
;
; Structure:
; - BPB (BIOS Parameter Block): filesystem information
; - Bootstrap code: loads and starts the kernel
; - Boot signature: 0xAA55 (required by BIOS)
;
; The bootloader is loaded by BIOS at address 0x7C00
; and must be exactly 512 bytes (sector size)

org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

; =============================================================================
; BIOS PARAMETER BLOCK (BPB)
; =============================================================================
;
; The BPB contains critical information about the FAT12 filesystem
; needed to locate and load the kernel from disk

jmp short start                                    ;jumps all the BPB to avoid executing them as machine code 2 byte
nop                                                ;jumps by one byte skipping the remaining part of the BPB

; Standard BPB for FAT12 on 1.44MB floppy
bdb_oem:                    db 'MSWIN4.1'          ; OEM identifier
bdb_bytes_per_sector:       dw 512                 ; Sector size in bytes
bdb_sectors_per_cluster:    db 1                   ; Sectors per cluster
bdb_reserved_sector:        dw 1                   ; Reserved sectors (bootloader)
bdb_fat_count:              db 2                   ; Number of FAT copies
bdb_dir_entries_count:      dw 0E0h                ; Root directory entries
bdb_total_sectors:          dw 2880                ; Total sectors (1.44MB)
bdb_media_descriptor_type:  db 0F0h                ; Media type (3.5" floppy)
bdb_sectors_per_fat:        dw 9                   ; Sectors per FAT
bdb_sectors_per_track:      dw 18                  ; Sectors per track
bdb_heads:                  dw 2                   ; Heads
bdb_hidden_sectors:         dd 0                   ; Hidden sectors
bdb_large_sector_count:     dd 0                   ; Large sector count

; Extended Boot Record
ebd_drive_number:           db 0                   ; Drive number (0 = floppy)
                            db 0                   ; Reserved
ebr_signature:              db 29h                 ; Signature
ebr_volume_id:              db 13h, 17h, 33h, 69h  ; Volume ID (serial number)
ebr_volume_label:           db 'QvantumFish'       ; Volume label (11 bytes)
ebr_system_id:              db 'FAT12   '          ; Filesystem type (8 bytes)



; =============================================================================
; BOOTSTRAP CODE
; =============================================================================
;
; Main bootloader code that:
; 1. Initializes registers and stack
; 2. Displays welcome message
; 3. (Future) Loads kernel from filesystem
; 4. (Future) Transfers execution to kernel

start:
    jmp main



; =============================================================================
; PUTS FUNCTION
; =============================================================================
;
; Prints a null-terminated string to video
; Parameters:
;   ds:si - pointer to string to print

puts:
    push si
    push ax

.loop:
    lodsb                   ; Load byte from [si] into al, increment si
    or al, al               ; Check for end of string (al = 0)
    jz .done

    mov ah, 0x0e            ; BIOS teletype output function
    mov bh, 0               ; Video page 0
    int 0x10                ; BIOS call

    jmp .loop

.done:
    pop ax
    pop si
    ret



; =============================================================================
; MAIN FUNCTION
; =============================================================================

main:
    ; Initialize data segments
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; Initialize stack
    mov ss, ax
    mov sp, 0x7C00          ; Stack grows downward from 0x7C00

    ; Display welcome message
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

    ; Infinite loop (to be removed when kernel loading is implemented)
.halt:
    jmp .halt



; =============================================================================
; WELCOME MESSAGES
; =============================================================================

msg_q1 db '  ___                   _                   _____ _     _      ___  ____', ENDL, 0
msg_q2 db ' / _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___| ', ENDL, 0
msg_q3 db '| | | \ \ / / _  |  _ \| __| | | |  _   _ \| |_  | / __|  _ \| | | \___ \ ', ENDL, 0
msg_q4 db '| |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |', ENDL, 0
msg_q5 db ' \__\_\ \_/ \__ _|_| |_|\__|\__ _|_| |_| |_|_|   |_|___/_| |_|\___/|____/ ', ENDL, 0



; =============================================================================
; BOOT SIGNATURE
; =============================================================================
;
; BIOS requires boot sectors to end with signature 0xAA55
; in the last two bytes

times 510-($-$$) db 0       ; Fill rest of sector with zeros
dw 0AA55h                   ; Boot signature (little endian)
