package main

import "core:fmt"
// import "core:bufio"
import "core:io"
import "core:os"
import "core:strings"
import "core:c/libc"
import "core:mem"
// import "core:unicode"
import "core:bufio"
import "core:unicode/utf8"
import "core:time"
import "core:strconv"

read_entire_file_from_handle :: proc(
	fd: os.Handle,
	allocator := context.allocator,
) -> (
	data: []byte,
	success: bool,
) {
	context.allocator = allocator

	length: i64
	err: os.Errno
	if length, err = os.file_size(fd); err != 0 {
		// fmt.println(args = { "ERROR, can't read file size:", i32(err), string(cstring(libc.strerror(i32(err))))}, sep="\t")
		return nil, false
	}

	if length <= 0 {
		// fmt.println(args = { "ERROR:", i32(err), string(cstring(libc.strerror(i32(err))))}, sep="\t")
		return nil, true
	}

	data = make([]byte, int(length), allocator)
	if data == nil {
		// fmt.println(args = { "ERROR:", i32(err), string(cstring(libc.strerror(i32(err))))}, sep="\t")
		return nil, false
	}

	bytes_read, read_err := os.read_full(fd, data)
	if read_err != os.ERROR_NONE {
		fmt.println(
			args = {
				"ERROR while reading file:",
				i32(read_err),
				string(cstring(libc.strerror(i32(read_err)))),
			},
			sep = "\t",
		)
		delete(data)
		return nil, false
	}
	return data[:bytes_read], true
}

read_entire_file_from_filename :: proc(
	name: string,
	allocator := context.allocator,
) -> (
	data: []byte,
	success: bool,
) {
	context.allocator = allocator

	fd, err := os.open(name, 0, 0)
	if i32(err) != 0 {
		fmt.println(
			args = {
				"ERROR while opening the file:",
				i32(err),
				string(cstring(libc.strerror(i32(err)))),
			},
			sep = "\t",
		)
		return nil, false
	}
	defer os.close(fd)

	return read_entire_file_from_handle(fd, allocator)
}

ChessMove::distinct u8

load_file_sequential::proc(fullpath:string){
	start_time:=time.now()
	contents_bytes, success := read_entire_file_from_filename(fullpath)
	{
		buf:=make([]u8, 256)
		defer delete(buf)
		end_time:=time.since(start_time)
		fmt.println("Loading the file into RAM took: ", strconv.itoa(buf, int(i64((end_time)))))
	}
	if success {
	} else {
		fmt.println(args = {"Couldn't read file", fullpath}, sep = "\t")
	}
	i: u64 = 0
	empty_lines: u64 = 0
	char_count: u64 = 0
	arena:mem.Arena
	bytes :[]u8 = make([]u8, os.file_size_from_path(fullpath))
	defer delete(bytes)
	mem.arena_init(&arena,bytes)
	context.temp_allocator = mem.arena_allocator(&arena)
	contents :string= transmute(string)contents_bytes
	iterable_string:=contents
	// TODO: replace BOM if there is any
	maybe_bom, _ := utf8.decode_rune_in_string(iterable_string)
	fmt.printf("prefix: \\u%04x\n", maybe_bom)
	for line in strings.split_lines_iterator(&iterable_string) {
		// parsing the file
		if line == "" {
			empty_lines += 1
		}
		for _ in line{
			char_count+=1
		}
		i += 1
	}
	fmt.println(args = {"characters in file: ", char_count})
	fmt.println(args = {"lines in file: ", i})
	fmt.println(args = {"empty lines in file: ", empty_lines})
	buf:=make([]u8, 256)
	defer delete(buf)
	end_time:=time.since(start_time)
	fmt.println("Sequential scan took: ", strconv.itoa(buf, int(i64((end_time)))))
}

read_line :: proc(r: ^bufio.Reader) -> (line: string, ok: bool) {
    line_bytes, err := bufio.reader_read_slice(r, '\n')
    if err != .None {
		fmt.println(err)
        return "", false
    }

    line = string(line_bytes)
    line = strings.trim(line, "\r\n")
    return line, true
}

load_file_streamed :: proc(filepath: string){
	start_time := time.now()
	char_count :u64 = 0
	empty_lines:u64 = 0
	lines:u64 = 0
	handle, err:=os.open(filepath)
	if err!=0{
		panic("BEEP")
	}

	stream:= os.stream_from_handle(handle)
	unbuffered_reader:=io.to_reader(stream)
	buffered_reader:bufio.Reader
	READER_BUFFER_SIZE := 2<<15
	bufio.reader_init(b = &buffered_reader, rd = unbuffered_reader, size = READER_BUFFER_SIZE)

	ok: bool = true
	line:string
	for ok{
		line,ok = read_line(&buffered_reader)
		lines+=1
		if len(line) == 0 {
			empty_lines+=1
			continue
		}
		for _ in line{
			char_count+=1
		}
	}

	fmt.println(args = {"characters in file: ", char_count})
	fmt.println(args = {"lines in file: ", lines})
	fmt.println(args = {"empty lines in file: ", empty_lines})
	end_time := time.since(start_time)
	buf := make([]u8, 256)
	defer delete(buf)
	fmt.println("Streamed scan took: ", strconv.itoa(buf, int(i64((end_time)))))
}

main2 :: proc() {
	fmt.println("Hello people.")
	wd_path := os.get_current_directory()
	path_chunks := []string{wd_path, "data", "ignored"}
	data_dir_path := strings.join(path_chunks, "\\")
	dir, err_dir_opening := os.open(data_dir_path)
	if err_dir_opening!=0{
		panic(strings.concatenate(a={"Error opening directory: ", data_dir_path}))
	}
	// Q: How to supply type annotations to the following line?
	files, err_files_listing := os.read_dir(dir, 0)
	if err_files_listing!=0{
		panic(strings.concatenate(a={"Error reading directory: ", data_dir_path}))
	}
	for file in files {
		fmt.println(file)
		name_splits := strings.split(file.name, ".")
		extension := name_splits[len(name_splits) - 1]
		if extension == "pgn"{
			load_file_streamed(file.fullpath)
		}
		if extension == "pgn" {
			fmt.println("Found file full of chess games!")
			// FIXME: produces an invalid handle for large files(observed with 9GB pgns)
			load_file_sequential(file.fullpath)
		} else {
			fmt.println(file.name, "is not a chess database file")
		}
		// Q: how does it know how to serialize the File struct?
	}

	// pgn_file = os.file
	// assert(,"No pgn file found")
}
