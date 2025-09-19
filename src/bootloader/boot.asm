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

jmp short start                                    ; Jump over BPB data to avoid executing it as code (2 bytes)
nop                                                ; Pad to ensure BPB starts at correct offset (1 byte)

; Standard BPB for FAT12 on 1.44MB floppy
bdb_oem:                    db 'MSWIN4.1'          ; OEM identifier (8 bytes)
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

; =============================================================================
; ERROR HANDLING ROUTINES
; =============================================================================

floppy_error:
    mov si, msg_floppy_read_failed     ; Load error message string
    call puts                          ; Display error message
    jmp wait_key_and_reboot            ; Jump to reboot handler

wait_key_and_reboot:
    mov ah, 0                          ; BIOS function: wait for keypress
    int 16h                            ; Call BIOS keyboard service
    jmp 0FFFFh:0                       ; Jump to BIOS reset vector (reboot system)
    hlt                                ; Halt execution (safety measure)

; =============================================================================
; SYSTEM CONTROL FUNCTIONS
; =============================================================================

.halt:
    cli                                ; Disable interrupts to prevent exiting halt state
    hlt                                ; Halt processor execution

; =============================================================================
; DISK OPERATION ROUTINES
; =============================================================================

; LBA to CHS conversion function
; Converts Logical Block Addressing to Cylinder-Head-Sector addressing
; Parameters:
;   ax: LBA address to convert
; Returns:
;   cx [bits 0-5]: sector number
;   cx [bits 6-15]: cylinder number
;   dh: head number

lba_to_chs:
    push ax                             ; Save original LBA value
    push dx                             ; Save DX register

    xor dx, dx                          ; Clear DX for division
    div word [bdb_sectors_per_track]    ; AX = LBA / sectors per track
                                        ; DX = LBA % sectors per track (sector number - 1)
    inc dx                              ; DX = sector number (1-based)
    mov cx, dx                          ; Store sector number in CL
    
    xor dx, dx                          ; Clear DX for division
    div word [bdb_heads]                ; AX = cylinder number
                                        ; DX = head number
    mov dh, dl                          ; Store head number in DH
    mov ch, al                          ; Store lower 8 bits of cylinder in CH
    shl ah, 6                           ; Shift upper 2 bits of cylinder to bits 6-7
    or cl, ah                           ; Combine sector and cylinder bits in CL

    pop ax                              ; Restore original DX value
    mov dl, al                          ; Move drive number to DL
    pop ax                              ; Restore original AX value
    ret                                 ; Return from function

; Disk read function
; Reads sectors from disk using BIOS interrupt 13h
; Parameters:
;   ax: LBA address to read from
;   cl: number of sectors to read (up to 128)
;   dl: drive number
;   es:bx: memory address where data will be stored

disk_read:
    push ax                             ; Save registers that will be modified
    push bx 
    push cx
    push dx
    push di

    push cx                             ; Save sector count (will be modified by lba_to_chs)
    call lba_to_chs                     ; Convert LBA to CHS format
    pop ax                              ; AL = number of sectors to read
    mov ah, 02h                         ; BIOS function: read sectors
    mov di, 3                           ; Retry counter (3 attempts)

.retry:
    pusha                               ; Save all registers (BIOS may modify them)
    stc                                 ; Set carry flag (some BIOSes don't)
    int 13h                             ; Call BIOS disk service
    jnc .done                           ; Jump if operation succeeded (carry flag clear)
    
    ; Operation failed - retry
    popa                                ; Restore registers
    call disk_reset                     ; Reset disk controller
    dec di                              ; Decrement retry counter
    test di, di                         ; Check if retries exhausted
    jnz .retry                          ; Retry if attempts remaining

.fail:
    jmp floppy_error                    ; Jump to error handler if all retries fail

.done:
    popa                                ; Restore registers saved by pusha
    
    pop di                              ; Restore original register values
    pop dx 
    pop cx
    pop bx
    pop ax
    ret                                 ; Return from function

; Disk reset function (to be implemented)
; Resets disk controller between read attempts
disk_reset:
    ; TODO: Implement disk reset functionality
    ret                                 ; Return (placeholder)

; =============================================================================
; DATA SECTION - MESSAGES
; =============================================================================

msg_q1 db '  ___                   _                   _____ _     _      ___  ____', ENDL, 0
msg_q2 db ' / _ \__   ____ _ _ __ | |_ _   _ _ __ ___ |  ___(_)___| |__  / _ \/ ___| ', ENDL, 0
msg_q3 db '| | | \ \ / / _  |  _ \| __| | | |  _   _ \| |_  | / __|  _ \| | | \___ \ ', ENDL, 0
msg_q4 db '| |_| |\ V / (_| | | | | |_| |_| | | | | | |  _| | \__ \ | | | |_| |___) |', ENDL, 0
msg_q5 db ' \__\_\ \_/ \__ _|_| |_|\__|\__ _|_| |_| |_|_|   |_|___/_| |_|\___/|____/ ', ENDL, 0

msg_floppy_read_failed db 'Failed to read from floppy', ENDL, 0

; =============================================================================
; BOOT SIGNATURE
; =============================================================================
;
; BIOS requires boot sectors to end with signature 0xAA55
; in the last two bytes to identify as bootable

times 510-($-$$) db 0       ; Fill remainder of sector with zeros
dw 0AA55h                   ; Boot signature (little endian)