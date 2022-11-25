package main
import bufio "core:bufio"
import "core:reflect"
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
	bool,
) {
	i := 0
	// {
	// 	data,err:=bufio.reader_peek(reader, 7)
	// 	fmt.eprintln(transmute(string)data, err)
	// }
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
		case ' ', '\t', '\n', '#', '+', '-', '=':
			if i==0{
				break
			}
			bufio.reader_unread_byte(reader)
			return move_string_backing_buffer[:i], true
		}
		if i==5{
			fmt.eprintln(err, rune(c))
			panic("This isn't supposed to happen")
		}
		move_string_backing_buffer[i] = c
		i += 1
	}
	// next, _:=bufio.reader_peek(reader, 10)
	// fmt.eprintln(transmute(string)move_string_backing_buffer[:],"|",transmute(string)next)
	return move_string_backing_buffer[:0], false
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
	move_bytes, consume_success := consume_delimited_move(reader, &buf)
	// assert(consume_success, transmute(string)move_bytes)
	if !consume_success{
		return
	}
	move_string := cast(string)move_bytes
	// move parsing
	s: bool
	move.piece_type, s = get_piece_type_from_pgn_character(move_bytes[0])
	if s == false {
		return
	}
	if len(move_string) == 2 {
		// fmt.eprintln("casual pawn move")
		if move.piece_type != .Pawn {
			return
		}
		move.dest_x = move_string[0]
		move.dest_y = move_string[1]
	} else if len(move_string) == 3 {
		if move.piece_type == .Pawn {
			return
		}
		// fmt.eprintln("casual piece move")
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
			case 'x':
			case:
				return
			}
			move.dest_x = move_string[2]
			move.dest_y = move_string[3]
		}
		fmt.println(move.piece_type, "takes on", rune(move.dest_x), rune(move.dest_y))
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
		fmt.println(move.piece_type, " long form takes on", rune(move.dest_x), rune(move.dest_y))
	} else {
		panic("This is impossible.")
	}
	success = true
	return
}
reader_read_integer :: proc(reader: ^bufio.Reader) -> (result: u16 = 0, success:bool=false) {
	// TODO: test for `000x` kind of strings
	buf: [dynamic]byte = make([dynamic]byte, 0, context.temp_allocator)
	reading: for {
		b, err_read := bufio.reader_read_byte(reader)
		if err_read == .EOF{
			break reading
		}
		else if err_read != .None{
			// err = err_read
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
		// fmt.eprintln(transmute(string)buf[:], len(buf))
		success = true
		s:=transmute(string)buf[:]
		// fmt.eprintln("This is a number:", s)
		result = u16(strconv.atoi(s))
		assert(result!=0) // TODO: it should work with zero, but not where I'm using it.
	}
	return
}
// parse_full_move_from_pgn :: proc(
// 	reader: ^bufio.Reader,
// ) -> (
// 	full_move: PGN_Full_Move = {},
// 	success: bool = true,
// ) {
// 	// TODO: this is broken, use parse_pgn_token instead
// 	full_move.move_number, success = reader_read_integer(reader)
// 	success &= success
// 	dot, err := bufio.reader_read_byte(reader)
// 	success &= (err == .None)
// 	acceptable_delimiters := [?]u8{' ', '\n', '\t'}
// 	skip_characters_in_set(reader = reader, chars = acceptable_delimiters)
// 	half_move, s := parse_half_move_from_pgn(reader)
// 	success &= s
// 	// parse move descriptors(+ and #)
// 	// NOTE: move descriptors are currently being stripped completely
// 	if skip_characters_in_set(reader, [?]u8{'+', '#'}) {
// 		fmt.eprintln("skipping a move descriptor")
// 	}
// 	half_move, s = parse_half_move_from_pgn(reader)
// 	success &= s
// 	if skip_characters_in_set(reader, [?]u8{'+', '#'}) {
// 		fmt.eprintln("skipping a move descriptor")
// 	}
// 	skip_characters_in_set(reader = reader, chars = acceptable_delimiters)

// 	// game result string
// 	skipped_strings := [?]string{"1/2-1/2", "1-0", "0-1"}
// 	if skip_characters_in_set_strings_variant(reader, skipped_strings[:]) {
// 		fmt.eprintln("Got a game result")
// 	}
// 	// panic("Oops, you forgot to finish your job.")

// 	// TODO: annotation parsing
// 	// TODO: variation parsing
// 	return
// }
PGN_Game :: struct{
	moves:[]PGN_Half_Move,
	result:Chess_Result
}
Move_Number :: distinct u16
PGN_Metadata :: distinct struct{
	key:string,
	value:string
}
Empty_Line :: distinct struct{}

// VITAL NOTE: the following is coupled together, MAKE SURE they go in the same order.
PGN_Parser_Token :: union{
	Move_Number,
	PGN_Half_Move,
	Chess_Result,
	PGN_Metadata,
	Empty_Line
}
PGN_Parser_Token_Type :: enum u16{
	None,
	Move_Number,
	PGN_Half_Move,
	Chess_Result,
	PGN_Metadata,
	Empty_Line
}

parse_pgn_token :: proc(reader:^bufio.Reader) -> (result: PGN_Parser_Token, success:bool){
	// skip an optional space, return Empty_Line if there's an empty line
	bytes, err := bufio.reader_peek(reader, 1)
	if err != .None{
		return
	}
	c := bytes[0]
	switch c{
		case ' ':
			bufio.reader_read_byte(reader)
		case '\n':
			bufio.reader_read_byte(reader)
			c, err := bufio.reader_peek(reader,1)
			if err==.None && c[0]=='\n'{
				bufio.reader_read_byte(reader)
				result = Empty_Line{}
				success = true
				return
			}
	}
	result_strings := []string{"1-0", "0-1", "1/2-1/2"}
	corresponding_val := []Chess_Result{.White_Won, .Black_Won, .Draw}
	// detect results
	for result_string, index_of_result_string in result_strings{
		bytes, err := bufio.reader_peek(reader, len(result_string))
		text := transmute(string)bytes
		if text == result_string{
			for i:=0; i<len(text); i+=1{
				bufio.reader_read_byte(reader)
			}
			success = true
			result = corresponding_val[index_of_result_string]
			return
		}
		if err==.EOF{
			continue
		}
		else if err != .None{
			return
		}
	}

	// detect move number
	move_number, read_success := reader_read_integer(reader)
	if read_success{
		c, err = bufio.reader_read_byte(reader)
		success = true
		if err !=.None || c!='.'{
			success = false
		}
		result = cast(Move_Number)move_number
		return
	}

	// detect half moves
	move, read := parse_half_move_from_pgn(reader)
	if read{
		opt_move_postfix, err_postfix:=bufio.reader_read_byte(reader)
		result = move
		success = true
		if err_postfix == .EOF{
			return
		}
		else if err_postfix!=.None{
			success = false
			return
		}
		switch opt_move_postfix{
			case ' ', '\n', '\t':
				bufio.reader_unread_byte(reader)
			case '{', '(':
				panic("Found a variant/commentary")
			case '+', '#':
				fmt.eprintln("Found a check/mate")
			case:
				fmt.eprintln("unknown postfix", opt_move_postfix)
				success = false
				return
		}
		return
	}
	// // detect metadata
	// mdata_reader: strings.Reader
	// FIXME: I'm pretty sure this can cause buffer overflow
	// FIXME: this allocates, use bufio.reader_read_slice and store in a dataframe elsewhere
	// metadata_str, metadata_err := bufio.reader_read_string(reader, '\n')
	// if metadata_err == .None{
	// 	{
	// 		d,_:=bufio.reader_peek(reader,15)
	// 		fmt.eprintln("Metadata maybe:", transmute(string)d)
	// 	}

	// 	fmt.eprintln("I am not metadata")
	// 	// TODO: support utf-8
	// 	if metadata_str[0]!='['{
	// 		return
	// 	}

	// 	index:i64=386
	// 	for c, inner in metadata_str[1:]{
	// 		index = i64(inner)
	// 		if c == ' '{
	// 			break
	// 		}
	// 	}

	// 	// if end of string, then there was no value
	// 	fmt.eprintln(index)
	// 	if index == i64(len(metadata_str))-1{
	// 		return
	// 	}
	// 	key_str := metadata_str[1:index]
	// 	index+=1
	// 	if index == i64(len(metadata_str))-1{
	// 		return
	// 	}
	// 	if metadata_str[index] != '\"'{
	// 		return
	// 	}
	// 	index+=1
	// 	if index == i64(len(metadata_str))-1{
	// 		return
	// 	}
	// 	fmt.eprintln("I am metadata")
	// 	start_val:=index
	// 	for c, inner in metadata_str[index:]{
	// 		index=i64(inner)
	// 		if c == '\"'{
	// 			break
	// 		}
	// 	}
	// 	if index == i64(len(metadata_str))-1{
	// 		return
	// 	}
	// 	val_str := metadata_str[start_val:index]
	// 	if metadata_str[len(metadata_str)-1]!=']'{
	// 		return
	// 	}
	// 	return PGN_Metadata{key_str, val_str}, true
	// }

	// parse metadata
	b, b_err:=bufio.reader_read_byte(reader)
	if b!='['{
		bufio.reader_unread_byte(reader)
		return
	}
	for {
		key, key_err:=bufio.reader_read_byte(reader)
		if key_err!=.None{
			return
		}
		if key == ' '{
			break
		}
	}
	{
		key, key_err:=bufio.reader_read_byte(reader)
		if key_err!=.None{
			return
		}
		if key != '\"'{
			return
		}
	}
	for {
		key, key_err:=bufio.reader_read_byte(reader)
		if key_err!=.None{
			return
		}
		if key == '"'{
			break
		}
	}
	{
		key, key_err:=bufio.reader_read_byte(reader)
		if key_err!=.None{
			return
		}
		if key != ']'{
			return
		}
		result = PGN_Metadata{}
		success = true
	}


	return
}

// parse_metadata_row::proc(reader:^bufio.Reader)->(key:string, value:string, success: bool){
// 	// assumes '[' has already been consumed
// 	line,e:=bufio.reader_read_slice(reader, '\n')
// 	if e!=.None{
// 		return
// 	}
// 	key_len:=0
// 	key_scan: for seeked_char in line{
// 		// FIXME: seeked_char could be utf-8 and produce weird behavior
// 		switch seeked_char{
// 			case '\"',' ':
// 				break key_scan
// 			case '[',']','\n','\t','\'', '\r':
// 				return
// 			case:
// 				key_len+=1
// 		}
// 	}
// 	assert(key_len>0)
// 	assert(line[key_len+1] == '\"')
// 	val_start:=key_len+2
// 	val_len:=0
// 	val_scan: for seeked_char in line[val_start:]{
// 		// FIXME: seeked_char could be utf-8 and produce weird behavior
// 		switch seeked_char{
// 			case '\"':
// 				break val_scan
// 			case '[',']','\n':
// 				panic("disallowed characters")
// 			case:
// 				val_len+=1
// 		}
// 	}
// 	assert(line[val_start+val_len]=='\"')
// 	assert(line[val_start+val_len+1]==']')
// 	key=transmute(string)line[:key_len]
// 	value=transmute(string)line[val_start:val_start+val_len]
// 	fmt.print("key:",key,"\t")
// 	fmt.println("value:",value)
// 	return key, value
// }

parse_full_game_from_pgn :: proc(reader:^bufio.Reader, no_metadata:bool=false) -> (game: PGN_Game, success: bool){
	token_types::bit_set[PGN_Parser_Token_Type]
	expected:=token_types{.PGN_Metadata}
	if no_metadata{
		expected=token_types{.Move_Number}
	}
	second_half_move:bool
	for{
		token, token_read:=parse_pgn_token(reader)
		if token_read == false{
			return
		}
		raw_tag:=reflect.get_union_variant_raw_tag(token)
		tag:=transmute(PGN_Parser_Token_Type)cast(u16)raw_tag
		if tag == PGN_Parser_Token_Type.None{
			panic("This is a bug, report to developer!")
		}
		if tag not_in expected{
			fmt.eprintln("It was this.", tag, expected)
			success = false
			return
		}
		switch t in token{
			case Move_Number:
				fmt.eprintln("got a move number")
				expected=token_types{.PGN_Half_Move}
			case PGN_Half_Move:
				fmt.eprintln("got a half move")
				if second_half_move{
					expected=token_types{.Chess_Result, .Move_Number}
					second_half_move=false
				}else{
					expected=token_types{.Chess_Result, .PGN_Half_Move}
					second_half_move=true
				}
			case Chess_Result:
				fmt.eprintln("got a chess result")
				success = true
				break
			case PGN_Metadata:
				fmt.eprintln("got metadata")
				// unimplemented()
				expected=token_types{.Empty_Line, .PGN_Metadata}
			case Empty_Line:
				fmt.eprintln("got a move number")
				// unimplemented("Currently only a single game of moves with no metadata can be parsed, so this is redundant for now")
				expected=token_types{.Move_Number}
		}
	}
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
	// {
	// 	backing_buf:=[17]u8{}
	// 	test_buf:=backing_buf[:]
	// 	// test_transmuted:=transmute([]u64)test_buf
	// 	thing:=transmute([2]u64)test_buf
	// 	test_transmuted:=thing[0]
	// 	fmt.eprintln(test_buf, test_transmuted)
	// }
	fmt.println("RUNNING TESTS")
	r: bufio.Reader
	defer bufio.reader_destroy(&r)
	string_reader: strings.Reader
	{
		{
			reader_init_from_string(`e4`, &string_reader, &r)
			parse_half_move_from_pgn(&r)
		}
		{
			reader_init_from_string(`ed4`, &string_reader, &r)
			thing, success := parse_half_move_from_pgn(&r)
			assert(success == false, fmt.tprintln("test failed", thing)) // this should be unsuccessful, because `ed4` is not a valid half move
		}
		{
			reader_init_from_string(`Rd4`, &string_reader, &r)
			parse_half_move_from_pgn(&r)
		}
		{
			reader_init_from_string(`Rbe4`, &string_reader, &r)
			parse_half_move_from_pgn(&r)
		}
		{
			reader_init_from_string(`exd4`, &string_reader, &r)
			parse_half_move_from_pgn(&r)
		}
		{
			reader_init_from_string(`Rbxe4`, &string_reader, &r)
			parse_half_move_from_pgn(&r)
		}
		fmt.eprintln("TEST of pgn half move parsing successful")
	}
	{
		{
			reader_init_from_string(`1`, &string_reader, &r)
			thing, s := reader_read_integer(&r)
			assert(thing == 1 && s == true, fmt.tprintln(thing, s))
		}
		{
			reader_init_from_string(`37.`, &string_reader, &r)
			thing, s := reader_read_integer(&r)
			assert(thing == 37 && s == true, fmt.tprintln(thing, s))
			dot, err := bufio.reader_read_byte(&r)
			assert(err==.None)
			assert(dot=='.')
		}
		fmt.eprintln("TEST of reading integers from a reader successful")
	}
	{
		fmt.eprintln("Running the string skipping test")
		skipped_strings := [?]string{"1/2-1/2", "1-0", "0-1"}
		{
			reader_init_from_string(`1/2-1/2ok`, &string_reader, &r)
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 2)
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", "test failed")
			fmt.eprintln("trivial test successful")
		}
		{
			reader_init_from_string(`ok`, &string_reader, &r)
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 2)
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", fmt.tprintln("test failed", data))
			fmt.eprintln("Works with no delimiter")
		}
		{
			reader_init_from_string(`1/2-1/2ok1/2-1/2`, &string_reader, &r)
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 2)
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", "test failed")
			fmt.eprintln("Works when there are delimiters after when it should return")
		}
		{
			reader_init_from_string(`1-0ok`, &string_reader, &r)
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 1)
			assert(err == .None, fmt.tprintln(err))
			data, err = bufio.reader_peek(&r, 2)
			assert(err == .None, fmt.tprintln(err))
			ok_maybe := transmute(string)data
			assert(
				ok_maybe == "ok",
				fmt.tprintln("It doesn't work for the second delimiter:", data),
			)
			fmt.eprintln("Works when you find the second delimiter")
		}
		{
			reader_init_from_string(`1/2-1/21-0ok`, &string_reader, &r)
			skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			data, err := bufio.reader_peek(&r, 2)
			ok_maybe := transmute(string)data
			assert(ok_maybe == "ok", "test failed")
			fmt.eprintln("Works when you use multiple different delimiters")
		}
		fmt.eprintln("TEST of skip_characters_in_set_strings_variant successful")
	}
	{
		parse_token_from_string_test::proc(reader:^bufio.Reader, string_reader: ^strings.Reader, thing:string)->PGN_Parser_Token{
			reader_init_from_string(thing, string_reader, reader)
			// skip_characters_in_set_strings_variant(&r, skipped_strings[:])
			token, success := parse_pgn_token(reader)
			assert(success == true, fmt.tprintln(token))
			fmt.eprintln("Parsing full moves works")
			return token
		}
		_=parse_token_from_string_test(&r, &string_reader, `1.`).(Move_Number)
		fmt.eprintln("TEST parsing move numbers as tokens successful")
		_=parse_token_from_string_test(&r, &string_reader, `1-0`).(Chess_Result)
		fmt.eprintln("TEST parsing chess results as tokens successful")
		parse_token_from_string_test(&r, &string_reader, `e4`)
		fmt.eprintln("TEST parsing chess moves as tokens successful")
		{
			reader_init_from_string(`1. e4 d5 1/2-1/2ok`, &string_reader, &r)
			token, success := parse_pgn_token(&r)
			assert(success == true, fmt.tprintln(token))
			_=token.(Move_Number)
			token, success = parse_pgn_token(&r)
			assert(success == true, fmt.tprintln(token))
			_=token.(PGN_Half_Move)
			token, success = parse_pgn_token(&r)
			assert(success == true, fmt.tprintln(token))
			_=token.(PGN_Half_Move)
			token, success = parse_pgn_token(&r)
			assert(success == true, fmt.tprintln(token))
			_=token.(Chess_Result)
		}
		fmt.eprintln("TEST parsing multiple pgn tokens sequentially works")
		{
			reader_init_from_string(`1. e4 d5 2. exd5 Qxd5 3. Nc3 Qd8 4. Bc4 Nf6 5. Nf3 Bg4 6. h3 Bxf3 7. Qxf3 e6 8.
Qxb7 Nbd7 9. Nb5 Rc8 10. Nxa7 Nb6 11. Nxc8 Nxc8 12. d4 Nd6 13. Bb5+ Nxb5 14.
Qxb5+ Nd7 15. d5 exd5 16. Be3 Bd6 17. Rd1 Qf6 18. Rxd5 Qg6 19. Bf4 Bxf4 20.
Qxd7+ Kf8 21. Qd8# 1-0`, &string_reader, &r)
			game, success:=parse_full_game_from_pgn(&r, true)
			assert(success==true, fmt.tprintln(game))
		}
		fmt.eprintln("TEST full moves portion parsing successful")

		{
			pgn_sample_full:=`[Event "Valencia Casual Games"]
[Site "Valencia"]
[Date "1475.??.??"]
[Round "?"]
[White "De Castellvi, Francisco"]
[Black "Vinoles, Narcisco"]
[Result "1-0"]
[ECO "B01"]
[PlyCount "41"]
[EventDate "1475.??.??"]
[EventType "game"]
[EventCountry "ESP"]
[SourceTitle "EXT 2008"]
[Source "ChessBase"]
[SourceDate "2007.11.25"]
[SourceVersion "1"]
[SourceVersionDate "2007.11.25"]
[SourceQuality "1"]

1. e4 d5 2. exd5 Qxd5 3. Nc3 Qd8 4. Bc4 Nf6 5. Nf3 Bg4 6. h3 Bxf3 7. Qxf3 e6 8.
Qxb7 Nbd7 9. Nb5 Rc8 10. Nxa7 Nb6 11. Nxc8 Nxc8 12. d4 Nd6 13. Bb5+ Nxb5 14.
Qxb5+ Nd7 15. d5 exd5 16. Be3 Bd6 17. Rd1 Qf6 18. Rxd5 Qg6 19. Bf4 Bxf4 20.
Qxd7+ Kf8 21. Qd8# 1-0`
			pgn_sample:=`[Event "Valencia Casual Games"]`
			fmt.eprintln(pgn_sample)
			reader_init_from_string(pgn_sample, &string_reader, &r)
			game, success:=parse_full_game_from_pgn(&r)
			assert(success==true, fmt.tprintln(game))
		}
		fmt.eprintln("TEST full moves portion parsing successful")
		// {
		// 	reader_init_from_string(`1. e4 d5 1/2-1/2ok`, &string_reader, &r)
		// 	// skip_characters_in_set_strings_variant(&r, skipped_strings[:])
		// 	// full_move, success:=parse_full_move_from_pgn(&r)
		// 	full_game, success := parse_full_game_from_pgn(&r)
		// 	assert(success == true, fmt.tprintln(full_game))
		// 	data, err := bufio.reader_peek(&r, 2)
		// 	ok_maybe := transmute(string)data
		// 	assert(ok_maybe == "ok", "test failed")
		// 	fmt.eprintln("Parsing full moves works")
		// }
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
