package main

import "base:runtime"
import "core:fmt"

Prefab_Allocator :: struct{
    bytes:[]u8,
}
prefab_allocator_proc: runtime.Allocator_Proc: proc(allocator_data: rawptr, mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr, old_size: int,
    location:= #caller_location) -> (data: []byte, err: runtime.Allocator_Error){
    err = .None
    data = nil
    switch mode{
        case .Alloc:
            err = .Mode_Not_Implemented
        case .Alloc_Non_Zeroed:
            err = .Mode_Not_Implemented
        case .Free:
            err = .Mode_Not_Implemented
        case .Free_All:
            err = .Mode_Not_Implemented
        case .Resize:
            err = .Mode_Not_Implemented
        case .Query_Features:
            err = .Mode_Not_Implemented
        case .Query_Info:
            err = .Mode_Not_Implemented
        case .Resize_Non_Zeroed:
            err = .Mode_Not_Implemented
    }
    return
}

prefab_allocator :: proc(allocator:^Prefab_Allocator) -> runtime.Allocator{
    return runtime.Allocator{
        procedure = prefab_allocator_proc,
        data = allocator,
    }
}


Counting_Allocator :: struct{
    backing:^runtime.Allocator,
    count:u64,
    realloc_count:u64,
}

counting_allocator_proc: runtime.Allocator_Proc: proc(allocator_data: rawptr, mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr, old_size: int,
    location:= #caller_location) -> (data: []byte, err: runtime.Allocator_Error){
    allocator:^Counting_Allocator = cast(^Counting_Allocator)allocator_data
    switch mode{
        case .Alloc, .Alloc_Non_Zeroed:
            allocator.count+=1
        case .Free:
        case .Free_All:
        case .Resize:
            allocator.realloc_count += 1
        case .Query_Features:
        case .Query_Info:
        case .Resize_Non_Zeroed:
    }
    return allocator.backing.procedure(allocator.backing, mode, size, alignment, old_memory, old_size, location)
}

counting_allocator :: proc(backing:^runtime.Allocator) -> runtime.Allocator{
    allocator:= Counting_Allocator{
        backing = backing,
        count = 0,
    }
    return runtime.Allocator{
        procedure = prefab_allocator_proc,
        data = &allocator,
    }
}

Logging_Allocator :: struct{
    backing:^runtime.Allocator,
    id:string,
}

logging_allocator_proc: runtime.Allocator_Proc: proc(allocator_data: rawptr, mode: runtime.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr, old_size: int,
    location:= #caller_location) -> (data: []byte, err: runtime.Allocator_Error){
    allocator:^Logging_Allocator = cast(^Logging_Allocator)allocator_data
    switch mode{
        case .Alloc, .Alloc_Non_Zeroed:
            fmt.println(allocator.id,"allocated",size,"bytes")
        case .Free:
        case .Free_All:
        case .Resize:
        case .Query_Features:
        case .Query_Info:
        case .Resize_Non_Zeroed:
    }
    return allocator.backing.procedure(allocator.backing, mode, size, alignment, old_memory, old_size, location)
}

logging_allocator :: proc(backing:^runtime.Allocator) -> runtime.Allocator{
    allocator:= Logging_Allocator{
        backing = backing,
    }
    return runtime.Allocator{
        procedure = prefab_allocator_proc,
        data = &allocator,
    }
}

panicking_allocator_proc :: proc(
	data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	[]byte,
	runtime.Allocator_Error,
) {
	panic(fmt.tprint("asked to allocate!", mode))
}

panicking_allocator :: proc() -> runtime.Allocator {
	return {data = nil, procedure = panicking_allocator_proc}
}