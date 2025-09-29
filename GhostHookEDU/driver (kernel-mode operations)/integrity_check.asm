.data
    hash_table dq 16 dup(?)
    verification_key dq 0DEADBEEF12345678h
    
.code
integrity_check proc
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    
    mov rax, gs:[60h]
    test rax, rax
    jz integrity_fail
    
    mov rbx, [rax + 10h]
    mov rcx, [rax + 18h]
    
    xor r8, r8
    mov r9, verification_key
    
hash_loop:
    test rcx, rcx
    jz verify_hash
    
    movzx rdx, byte ptr [rbx]
    xor r8, rdx
    rol r8, 7
    xor r8, r9
    
    inc rbx
    dec rcx
    jmp hash_loop
    
verify_hash:
    mov rax, r8
    and rax, 0FFFFFFFFh
    cmp rax, 5A5A5A5Ah
    jne integrity_fail
    
    mov rax, 1
    jmp cleanup
    
integrity_fail:
    xor rax, rax
    
cleanup:
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret
integrity_check endp

anti_debug_check proc
    push rbx
    push rcx
    
    rdtsc
    mov rbx, eax
    
    nop
    nop
    nop
    
    rdtsc
    sub eax, ebx
    
    cmp eax, 1000
    jg debug_detected
    
    mov rax, 1
    jmp anti_debug_exit
    
debug_detected:
    xor rax, rax
    
anti_debug_exit:
    pop rcx
    pop rbx
    ret
anti_debug_check endp

end
