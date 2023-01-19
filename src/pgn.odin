package main
import bufio "core:bufio"
import fmt "core:fmt"
import strconv "core:strconv"
import io "core:io"
import reflect "core:reflect"

/* reads a delimited move(without annotations) from the string, doesn't consume the delimiter, result is NULL terminated*/
consume_delimited_move :: proc(reader: ^bufio.Reader, move_string_backing_buffer: ^[5]byte) -> ([]byte, bool) {
	i := 0
	for i < 6 {
		c, err := bufio.reader_read_byte(reader)
		if err == .EOF {
			return move_string_backing_buffer[:i], true
		}
		if err != .None {
			return move_string_backing_buffer[:0], false
		}
		switch c {
		case '[':
			bufio.reader_unread_byte(reader)
			return move_string_backing_buffer[:], false
		case ' ', '\t', '\r', '\n', '#', '+', '{', '(':
			if i == 0 {
				break
			}
			bufio.reader_unread_byte(reader)
			return move_string_backing_buffer[:i], true
		}
		if i == 5 {
			fmt.eprintln(err, rune(c))
			panic("This isn't supposed to happen")
		}
		move_string_backing_buffer[i] = c
		i += 1
	}
	return move_string_backing_buffer[:0], false
}

get_piece_type_from_pgn_character :: proc(character: byte) -> (piece_type: Piece_Type, success: bool = true) {
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
parse_half_move_from_pgn :: proc(reader: ^bufio.Reader) -> (move: PGN_Half_Move = {}, success: bool = false) {
	buf: [5]byte = {}
	move_bytes, consume_success := consume_delimited_move(reader, &buf)
	// assert(consume_success, transmute(string)move_bytes)
	if !consume_success {
		return
	}
	move_string := cast(string)move_bytes

	// castling
	if move_string == "O-O-O" {
		move.is_qside_castles = true
	} else if move_string == "O-O" {
		move.is_kside_castles = true
	}
	if move.is_kside_castles || move.is_qside_castles {
		success = true
		return
	}

	// move parsing
	s: bool
	move.piece_type, s = get_piece_type_from_pgn_character(move_bytes[0])
	if s == false {
		return
	}
	if len(move_string) == 2 {
		if move.piece_type != .Pawn {
			return
		}
		move.dst = Chessboard_location{move_string[0] - 'a', move_string[1] - '1'}
	} else if len(move_string) == 3 {
		if move.piece_type == .Pawn {
			return
		}
		move.dst = Chessboard_location{move_string[1] - 'a', move_string[2] - '1'}
	} else if len(move_string) == 4 {
		#partial switch move.piece_type {
		case .Pawn:
			if move_string[1] != 'x' {
				return
			}
			move.src_x = move_string[0] - 'a'
			move.is_takes = true
			move.known_src_column = true
			move.dst = Chessboard_location{move_string[2] - 'a', move_string[3] - '1'}
		case:
			switch move_string[1] {
			case 'a' ..= 'h':
				move.known_src_column = true
				move.src_x = move_string[1] - 'a'
			case '1' ..= '8':
				move.known_src_row = true
				move.src_y = move_string[2] - '1'
			case 'x':
				move.is_takes = true
			case:
				return
			}
			move.dst = Chessboard_location{move_string[2] - 'a', move_string[3] - '1'}
		}
		// fmt.println(move.piece_type, "takes on", rune(move.dest_x), rune(move.dest_y))
	} else if len(move_string) == 5 {
		if move_string[2] != 'x' {
			return
		}
		move.is_takes = true
		switch move_string[1] {
		case 'a' ..= 'h':
			move.known_src_column = true
		case '1' ..= '8':
			move.known_src_row = true
		case:
			return
		}
		move.dst = Chessboard_location{move_string[3] - 'a', move_string[4] - '1'}
		// fmt.println(move.piece_type, " long form takes on", rune(move.dest_x), rune(move.dest_y))
	} else {
		panic("This is impossible.")
	}
	success = true
	return
}
reader_read_integer :: proc(reader: ^bufio.Reader) -> (result: u16 = 0, success: bool = false) {
	// TODO: test for `000x` kind of strings
	buf: [dynamic]byte = make([dynamic]byte, 0, context.temp_allocator)
	reading: for {
		b, err_read := bufio.reader_read_byte(reader)
		if err_read == .EOF {
			break reading
		} else if err_read != .None {
			return
		}
		switch b {
		case '0' ..= '9':
			append(&buf, b)
		case:
			err := bufio.reader_unread_byte(reader)
			assert(err == .None)
			break reading
		}
	}
	if len(buf) == 0 {
		return
	} else {
		success = true
		s := transmute(string)buf[:]
		result = u16(strconv.atoi(s))
		// NOTE: it should be able to be 0, but this function is currently only used in places where it 0 must never occur.
		assert(result != 0)
	}
	return
}
Move_Number :: distinct u16
PGN_Move_Descriptor :: distinct u16
PGN_Metadata :: struct {
	key:   string,
	value: string,
}
Empty_Line :: distinct struct {}

// VITAL NOTE: the following union and enum are coupled together, MAKE SURE they go in the same respective order.
PGN_Parser_Token :: union {
	Move_Number,
	PGN_Half_Move,
	Chess_Result,
	PGN_Metadata,
	Empty_Line,
	PGN_Move_Descriptor,
}
PGN_Parser_Token_Type :: enum u16 {
	None,
	Move_Number,
	PGN_Half_Move,
	Chess_Result,
	PGN_Metadata,
	Empty_Line,
	PGN_Move_Descriptor,
}

PGN_Parsing_Error :: enum {
	Unspecified,
	None,
	Couldnt_Read,
	Syntax_Error,
}

// NOTE: it consumes the thing if it contains the thing. It returns the first match.
reader_startswith :: proc(reader: ^bufio.Reader, compared_strings: []string) -> (index_of_match: int, success: bool) {

	// detect results
	for result_string, index_of_result_string in compared_strings {
		bytes, err := bufio.reader_peek(reader, len(result_string))
		text := transmute(string)bytes
		if text == result_string {
			for i := 0; i < len(text); i += 1 {
				bufio.reader_read_byte(reader)
			}
			success = true
			index_of_match = index_of_result_string
			return
		}
		if err == .EOF {
			continue
		} else if err != .None {
			return
		}
	}
	return
}

strip_variations :: proc(reader: ^bufio.Reader) -> (did_consume: bool, did_err: bool) {
	nested_count := 0
	for {
		t, err := bufio.reader_read_byte(reader)
		disp := [?]byte{t}
		if err == .EOF {
			if nested_count != 0 {
				did_err = true
			}
			return did_consume, did_err
		}
		if err != .None {
			return did_consume, true
		}
		if t == '{' {
			did_consume = true
			for t != '}' {
				err_c: io.Error
				t, err_c = bufio.reader_read_byte(reader)
				if err_c != .None {
					return did_consume, true
				}
			}
			continue
		}
		if nested_count == 0 {
			if t != '(' {
				bufio.reader_unread_byte(reader)
				return did_consume, false
			}
		}
		if t == ')' {
			nested_count -= 1
		} else if t == '(' {
			nested_count += 1
			did_consume = true
		}
	}
}

parse_pgn_token :: proc(reader: ^bufio.Reader) -> (result: PGN_Parser_Token, e: PGN_Parsing_Error) {
	// skip an optional space, return Empty_Line if there's an empty line
	{
		bytes, err := bufio.reader_peek(reader, 1)
		if err != .None {
			e = .Couldnt_Read
			return
		}
		c := bytes[0]
		if c == '\r' {
			bufio.reader_read_byte(reader)
			result, e = parse_pgn_token(reader)
			return
		}
		switch c {
		case ' ':
			bufio.reader_read_byte(reader)
		case '\n':
			bufio.reader_read_byte(reader)
			l, err := bufio.reader_peek(reader, 1)
			if err == .None {
				counter := 0
				if l[counter] == '\r' {
					l, err = bufio.reader_peek(reader, 2)
					if err != .None {
						return
					}
					counter += 1
				}
				if l[counter] == '\n' {
					counter += 1
					for ; counter != 0; counter -= 1 {
						bufio.reader_read_byte(reader)
					}
					result = Empty_Line{}
					e = .None
					return
				}
			}
		}
	}

	// strip move descriptors
	{
		bytes, err := bufio.reader_peek(reader, 1)
		if err != .None {
			e = .Couldnt_Read
			return
		}
		c := bytes[0]
		if c == '$' {
			result = PGN_Move_Descriptor{}
			for c != ' ' && c != '\r' && c != '\n' && c != '\t' {
				c, err = bufio.reader_read_byte(reader)
				slice := []byte{c}
				if err != .None && err != .EOF {
					e = PGN_Parsing_Error.Couldnt_Read
					return
				} else if err == .EOF {
					e = PGN_Parsing_Error.Couldnt_Read
					return
				}
			}
			err = bufio.reader_unread_byte(reader)
			if err != .None {
				panic("This should be impossible")
			}
			result = PGN_Move_Descriptor{}
			e = .None
			return
		}
	}

	// strip variations(and comments, for now)
	did_consume, did_err := strip_variations(reader)
	if did_err {
		e = PGN_Parsing_Error.Syntax_Error
		return
	}
	if did_consume {
		return parse_pgn_token(reader)
	}

	// detect result
	result_strings := []string{"*", "1-0", "0-1", "1/2-1/2"}
	corresponding_val := []Chess_Result{.Undecided, .White_Won, .Black_Won, .Draw}

	i, s := reader_startswith(reader, result_strings)
	if s {
		e = .None
		result = corresponding_val[i]
		return
	}

	// detect move number
	move_number, read_success := reader_read_integer(reader)
	if read_success {
		c, err := bufio.reader_read_byte(reader)
		e = .None
		if err != .None || c != '.' {
			e = .Syntax_Error
		}
		result = cast(Move_Number)move_number

		// check for continuation sequence
		/* There are sometimes characters to exclaim which move a second half move falls into, especially after a long
		variation or comment. It looks something like this: `variant ends here) 9... Nxe5`*/
		// HACK
		// We currently just strip this. I hope I will not have to have a separate token type for this thing
		bytes: []byte
		bytes, err = bufio.reader_peek(reader, 2)
		if transmute(string)bytes == ".." {
			// this is a continuation sequence, skipping
			bufio.reader_read_byte(reader)
			bufio.reader_read_byte(reader)
			return parse_pgn_token(reader)
		}
		return
	}

	// detect half moves
	move, read := parse_half_move_from_pgn(reader)
	if read {
		opt_move_postfix, err_postfix := bufio.reader_read_byte(reader)
		result = move
		e = .None
		if err_postfix == .EOF {
			return
		} else if err_postfix != .None {
			e = .Couldnt_Read
			return
		}
		switch opt_move_postfix {
		case '\r':
			// fmt.eprintln("There it goes")
			fallthrough
		case ' ', '\n', '\t':
			bufio.reader_unread_byte(reader)
		case '{', '(':
			panic("Found a variant/commentary")
		case '+':
			move.is_check = true
		// fmt.eprintln("Found a check/mate")
		case '#':
			move.is_mate = true
		case:
			// fmt.eprintln("unknown postfix", opt_move_postfix)
			e = .Syntax_Error
			return
		}
		return
	}

	// parse metadata
	b, _ := bufio.reader_read_byte(reader)
	if b != '[' {
		bufio.reader_unread_byte(reader)
		return
	}
	// fmt.eprintln("parsing metadata")
	key_bytes := make([dynamic]byte, 0)
	for {
		c, c_err := bufio.reader_read_byte(reader)
		if c_err != .None {
			e = .Couldnt_Read
			return
		}
		if c == ' ' {
			break
		}
		append(&key_bytes, c)
	}
	{
		c, c_err := bufio.reader_read_byte(reader)
		if c_err != .None {
			e = .Couldnt_Read
			return
		}
		if c != '\"' {
			e = .Syntax_Error
			return
		}
	}
	val_bytes := make([dynamic]byte, 0)
	for {
		c, c_err := bufio.reader_read_byte(reader)
		if c_err != .None {
			e = .Couldnt_Read
			return
		}
		if c == '"' {
			break
		}
		append(&val_bytes, c)
	}
	{
		val_c, val_c_err := bufio.reader_read_byte(reader)
		if val_c_err != .None {
			e = .Couldnt_Read
			return
		}
		if val_c != ']' {
			e = .Syntax_Error
			return
		}
		result = PGN_Metadata {
			key   = transmute(string)key_bytes[:],
			value = transmute(string)val_bytes[:],
		}
		e = .None
	}
	return
}

PGN_Parsed_Game :: struct {
	// metadatas: [dynamic]PGN_Metadata,
	moves:     [dynamic]PGN_Half_Move,
	result:    Chess_Result,
}
pgn_parsed_game_init :: proc(game: ^PGN_Parsed_Game) {
	// game.metadatas = make([dynamic]PGN_Metadata, 0)
	// assert(game.metadatas.allocator.procedure != nil)
	game.moves = make([dynamic]PGN_Half_Move, 0)
	assert(game.moves.allocator.procedure != nil)
	game.result = Chess_Result.Undecided
}
parse_full_game_from_pgn :: proc(reader: ^bufio.Reader, md: ^Metadata_Table = nil) -> (
	game: PGN_Parsed_Game = {},
	success: bool,
) {
	token_types :: bit_set[PGN_Parser_Token_Type]
	expected := token_types{.PGN_Metadata}
	if md == nil {
		expected = token_types{.Move_Number}
	}
	pgn_parsed_game_init(&game)
	second_half_move: bool
	for {
		token, token_read := parse_pgn_token(reader)
		if token_read != .None {
			fmt.eprintln("Couldn't read token,", token_read)
			break
		}
		raw_tag := reflect.get_union_variant_raw_tag(token)
		tag := transmute(PGN_Parser_Token_Type)cast(u16)raw_tag
		if tag == PGN_Parser_Token_Type.None {
			panic("This is a bug, report to developer!")
		}
		if tag not_in expected {
			fmt.eprintln(
				args = {"Unexpected token type: <actual, expected>", tag, expected},
				sep = ", ",
			)
			success = false
			break
		}
		switch t in token {
		case Move_Number:
			expected = token_types{.PGN_Half_Move}
		case PGN_Half_Move:
			append(&game.moves, t)
			if second_half_move {
				expected = token_types{.Chess_Result, .Move_Number, .PGN_Move_Descriptor}
				second_half_move = false
			} else {
				expected = token_types{.Chess_Result, .PGN_Half_Move, .PGN_Move_Descriptor}
				second_half_move = true
			}
		case Chess_Result:
			// assumes there can be no move descriptor, annotation or comment following the game result
			game.result = t
			success = true
			return
		case PGN_Metadata:
			_, ok := md[t.key]
			if !ok{
				// FIXME: move this initialization elsewhere
				md[t.key] = make([dynamic]string, 0)
				t:=0
				for _, val in md{
					t=len(val)
				}
				// FIXME: fill all preceding rows
			}
			append(&md[t.key], t.value)
			// append(&game.metadatas, t)
			expected = token_types{.Empty_Line, .PGN_Metadata}
		case PGN_Move_Descriptor:
			if second_half_move {
				expected = token_types{.PGN_Half_Move, .Chess_Result, .PGN_Move_Descriptor}
			} else {
				expected = token_types{.Move_Number, .Chess_Result, .PGN_Move_Descriptor}
			}
			fmt.eprintln("found a move descriptor")
		case Empty_Line:
			expected = token_types{.Move_Number}
		}
	}
	return
}
