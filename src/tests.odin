package main
import bufio "core:bufio"
import io "core:io"
import strings "core:strings"
import fmt "core:fmt"
import "core:strconv"

/* reads a delimited move(without annotations) from the string, doesn't consume the delimiter, result is NULL terminated*/
consume_delimited_move :: proc(
	reader: ^bufio.Reader,
	move_string_backing_buffer: ^[5]byte,
) -> (
	[]byte,
	io.Error,
) {
	i := 0
	for i < 6 {
		c, err := bufio.reader_read_byte(reader)
		if err == .EOF {
			return move_string_backing_buffer[:i], .EOF
		}
		if err != .None {
			return move_string_backing_buffer[:0], err
		}
		switch c {
		case ' ', '\t', '\n', '#', '+', '-', '=':
			return move_string_backing_buffer[:i], .None
		}
		move_string_backing_buffer[i] = c
		i += 1
	}
	return move_string_backing_buffer[:0], .No_Progress
}

get_piece_type_from_pgn_character :: proc(
	character: byte,
) -> (
	piece_type: Piece_Type,
	success: bool = true,
) {
	switch character {
	case 'R':
		piece_type = .Rook
	case 'N':
		piece_type = .Knight
	case 'B':
		piece_type = .Bishop
	case 'K':
		piece_type = .King
	case 'Q':
		piece_type = .Queen
	case 'a' ..= 'h':
		piece_type = .Pawn
	case:
		success = false
	}
	return
}
parse_half_move_from_pgn :: proc(
	reader: ^bufio.Reader,
) -> (
	move: PGN_Half_Move = {},
	success: bool = false,
) {
	buf: [5]byte = {}
	move_string, err := consume_delimited_move(reader, &buf)
	assert(err == .None || err == .EOF, fmt.tprintln(err))
	// move parsing
	move.piece_type, success = get_piece_type_from_pgn_character(move_string[0])
	if success == false {
		return
	}
	if len(move_string) == 2 {
		fmt.eprintln("casual pawn move")
		if move.piece_type != .Pawn {
			return
		}
		move.dest_x = move_string[0]
		move.dest_y = move_string[1]
	} else if len(move_string) == 3 {
		fmt.eprintln("casual piece move")
		move.dest_x = move_string[1]
		move.dest_y = move_string[2]
	} else if len(move_string) == 4 {
		#partial switch move.piece_type {
		case .Pawn:
			if move_string[1] != 'x' {
				return
			}
			move.src_x = move_string[0]
			move.known_src_column = true
			move.dest_x = move_string[2]
			move.dest_y = move_string[3]
		case:
			switch move_string[1] {
			case 'a' ..= 'h':
				move.known_src_column = true
				move.src_y = move_string[1]
			case '1' ..= '8':
				move.known_src_row = true
				move.src_x = move_string[1]
			}
			move.dest_x = move_string[2]
			move.dest_y = move_string[3]
		}
		fmt.println(move.piece_type, "takes on", rune(move.dest_x), rune(move.dest_y))
		return
	} else if len(move_string) == 5 {
		if move_string[2] != 'x' {
			return
		}
		switch move_string[1] {
		case 'a' ..= 'h':
			move.known_src_column = true
		case '1' ..= '8':
			move.known_src_row = true
		case:
			return
		// panic("PGN syntax error")
		}
		move.dest_x = move_string[3]
		move.dest_y = move_string[4]
		fmt.println(move.piece_type, "takes on", rune(move.dest_x), rune(move.dest_y))
	} else {
		panic("This is impossible.")
	}
	return
}
reader_read_integer :: proc(reader: ^bufio.Reader) -> (result: i16 = 0, err: io.Error = .None) {
	buf: [dynamic]byte = make([dynamic]byte, 0, context.temp_allocator)
	reading: for {
		b, err_read := bufio.reader_read_byte(reader)
		if err_read != .None {
			err = err_read
			return
		}
		switch b {
		case '0' ..= '9':
			append(&buf, b)
		case:
			err = bufio.reader_unread_byte(reader)
			assert(err == .None)
			break reading
		}
	}
	if len(buf) == 0 {
		err = io.Error.Unknown
	} else {
		// fmt.eprintln(transmute(string)buf[:], len(buf))
		result = i16(strconv.atoi(transmute(string)buf[:]))
		// assert(result!=0)
	}
	return
}
parse_full_move_from_pgn :: proc(
	reader: ^bufio.Reader,
) -> (
	full_move: PGN_Full_Move = {},
	success: bool = true,
) {
	err: io.Error
	full_move.move_number, err = reader_read_integer(reader)
	success &= (err == .None)
	acceptable_delimiters := [?]u8{' ', '\n', '\t'}
	skip_characters_in_set(reader = reader, chars = acceptable_delimiters)
	parse_half_move_from_pgn(reader)
	// parse move descriptors(+ and #)
	// NOTE: move descriptors are currently being stripped completely
	if skip_characters_in_set(reader, [?]u8{'+', '#'}) {
		fmt.eprintln("skipping a move descriptor")
	}

	// game result string
	skipped_strings := [?]string{"1/2-1/2", "1-0", "0-1"}
	skip_characters_in_set_strings_variant(reader, skipped_strings[:])
	// panic("Oops, you forgot to finish your job.")

	// TODO: annotation parsing
	// TODO: variation parsing
	return
}
reader_init_from_string :: proc(
	sample_string: string,
	string_reader: ^strings.Reader,
	reader: ^bufio.Reader,
) {
	r := strings.to_reader(string_reader, sample_string)
	bufio.reader_destroy(reader)
	bufio.reader_init(reader, r)
}
run_tests :: proc() {
	fmt.println("RUNNING TESTS")
	r: bufio.Reader
	string_reader: strings.Reader
	{
		{
			reader_init_from_string(`e4`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			parse_half_move_from_pgn(&r)
		}
		// {
		// 	reader_init_from_string(`ed4`, &string_reader, &r)
		// 	defer bufio.reader_destroy(&r)
		// 	parse_half_move_from_pgn(&r)
		// 	fmt.eprintln("This should never happen")
		// }
		{
			reader_init_from_string(`Rd4`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			parse_half_move_from_pgn(&r)
		}
		{
			reader_init_from_string(`Rbe4`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			parse_half_move_from_pgn(&r)
		}
		{
			reader_init_from_string(`exd4`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			parse_half_move_from_pgn(&r)
		}
		{
			reader_init_from_string(`Rbxe4`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			parse_half_move_from_pgn(&r)
		}
		fmt.eprintln("TEST of pgn half move parsing successful")
	}
	{
		{
			reader_init_from_string(`1/2-1/2ok`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			skipped_strings := [?]string{"1/2-1/2", "1-0", "0-1"}
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 2)
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", "test failed")
		}
		{
			reader_init_from_string(`ok`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			skipped_strings := [?]string{"1/2-1/2", "1-0", "0-1"}
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 2)
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", fmt.tprintln("test failed", data))
			fmt.eprintln("Even this works")
		}
		{
			reader_init_from_string(`1/2-1/2ok1/2-1/2`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			skipped_strings := [?]string{"1/2-1/2", "1-0", "0-1"}
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 2)
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", "test failed")
			fmt.eprintln("Even this works")
		}
		{
			reader_init_from_string(`1-0ok   `, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			skipped_strings := [?]string{"1/2-1/2", "1-0", "0-1"}
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 1)
			assert(err==.None, fmt.tprintln(err))
			fmt.eprintln(data)
			data, err = bufio.reader_peek(&r, 2)
			assert(err==.None, fmt.tprintln(err))
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", fmt.tprintln("test failed", data))
		}
		{
			reader_init_from_string(`1/2-1/21/2-1/2ok`, &string_reader, &r)
			defer bufio.reader_destroy(&r)
			skipped_strings := [?]string{"1/2-1/2", "1-0", "0-1"}
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 2)
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", "test failed")
		}
		fmt.eprintln("TEST of skip_characters_in_set_strings_variant successful")
	}
	// pgn_test_1(`1. e4 d5`)
	// fmt.eprintln("test 2 successful")
	// pgn_test_1(`1. e4 d5 1-0`)
	// fmt.eprintln("test 3 successful")
	// pgn_test_1(`1. e4 d5 2. exd5 Qxd5 3. Nc3 Qd8 4. Bc4 Nf6 5. Nf3 Bg4 6. h3 Bxf3 7. Qxf3 e6 8.
	//     Qxb7 Nbd7 9. Nb5 Rc8 10. Nxa7 Nb6 11. Nxc8 Nxc8 12. d4 Nd6 13. Bb5+ Nxb5 14.
	//     Qxb5+ Nd7 15. d5 exd5 16. Be3 Bd6 17. Rd1 Qf6 18. Rxd5 Qg6 19. Bf4 Bxf4 20.
	//     Qxd7+ Kf8 21. Qd8# 1-0`)
}
