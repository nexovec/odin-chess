package main
import bufio "core:bufio"
import io "core:io"
import testing "core:testing"
import strings "core:strings"
import fmt "core:fmt"

// import c "core:c"
// import "core:reflect"
// import "core:runtime"
// import "core:strconv"


@(private = "file")
r: bufio.Reader
@(private = "file")
string_reader: strings.Reader

@(private = "file")
sample_pgn_strings := []string{
	`[Event "Valencia Casual Games"]
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
Qxd7+ Kf8 21. Qd8# 1-0

`,
	`[Event "Valencia Casual Games"]
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
Qxd7+ Kf8 21. Qd8# 1-0`,
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
// this tests for a bug where you get .No_Progress from a bufio.Reader in the test file.
@(test)
try_import_small_pgn_db :: proc(_: ^testing.T){
	// trying to parse the suspect game
	{
		suspect_game := `1. e4 d6 2. d4 Nf6 3. Nc3 g6 4. f4 Bg7 5. Nf3 O-O 6. Bd3 Nbd7 7. O-O c5 8. d5
		Qb6 9. Kh1 Ng4 10. h3 Nh6 11. Qe2 f5 12. e5 Qc7 13. Re1 a6 14. Ng5 Nb6 15. exd6
		exd6 16. Qe7 Qxe7 17. Rxe7 Nf7 18. Ne6 Bxe6 19. dxe6 Nd8 20. Rxg7+ Kxg7 21. e7
		Re8 22. exd8=Q Raxd8 23. Bd2 d5 24. Re1 Rxe1+ 25. Bxe1 c4 26. Bf1 d4 27. Nb1 d3
		28. cxd3 cxd3 29. Ba5 Rd6 30. Bxb6 Rxb6 31. b3 Rd6 32. Nd2 1/2-1/2`
		reader_init_from_string(suspect_game, &string_reader, &r)
		parse_full_game_from_pgn(&r)
		fmt.eprintln("TEST of the suspect game passed")
	}
	// trying to parse the entire test file
	games := make([dynamic]PGN_Parsed_Game, 0)
	nav_menu_open_file(&games, "data/carlsen_eng_notation.pgn")
}

@(test)
reading_integers_from_bufio_reader :: proc(_: ^testing.T) {
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
		assert(err == .None)
		assert(dot == '.')
	}
}

@(test)
string_skipping :: proc(_: ^testing.T) {
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
		assert(ok_maybe == "ok", fmt.tprintln("It doesn't work for the second delimiter:", data))
		fmt.eprintln("Works when you find the second delimiter")
	}
	{
		reader_init_from_string(`1/2-1/21-0ok`, &string_reader, &r)
		skip_characters_in_set_strings_variant(&r, skipped_strings[:])
		data, err := bufio.reader_peek(&r, 2)
		if err != .None {
			panic("Got an error")
		}
		ok_maybe := transmute(string)data
		assert(ok_maybe == "ok", "test failed")
		fmt.eprintln("Works when you use multiple different delimiters")
	}
	fmt.eprintln("TEST of skip_characters_in_set_strings_variant successful")
}

@(test)
pgn_half_move_parsing :: proc(_: ^testing.T) {
	{
		reader_init_from_string(`e4`, &string_reader, &r)
		parse_half_move_from_pgn(&r)
	}
	{
		reader_init_from_string(`ed4`, &string_reader, &r)
		thing, success, e := parse_half_move_from_pgn(&r)
		assert(success == false, fmt.tprintln("test failed", thing)) // this should be unsuccessful, because `ed4` is not a valid half move
	}
	{
		reader_init_from_string(`Rd4`, &string_reader, &r)
		thing, success, e := parse_half_move_from_pgn(&r)
		assert(success)
		assert(thing.piece_type == .Rook)
	}
	{
		reader_init_from_string(`Rbe4`, &string_reader, &r)
		thing, success, e := parse_half_move_from_pgn(&r)
		assert(success)
		assert(thing.piece_type == .Rook)
	}
	{
		reader_init_from_string(`exd4`, &string_reader, &r)
		thing, success, e := parse_half_move_from_pgn(&r)
		assert(success)
		assert(thing.piece_type == .Pawn)
	}
	{
		reader_init_from_string(`Rbxe4`, &string_reader, &r)
		thing, success, e := parse_half_move_from_pgn(&r)
		assert(success)
		assert(thing.piece_type == .Rook)
	}
	{
		reader_init_from_string(`O-O-O`, &string_reader, &r)
		thing, success, e := parse_half_move_from_pgn(&r)
		assert(success)
		assert(thing.is_qside_castles)
	}
	{
		reader_init_from_string(`O-O`, &string_reader, &r)
		thing, success, e := parse_half_move_from_pgn(&r)
		assert(success)
		assert(thing.is_kside_castles)
	}
	{
		reader_init_from_string(`e1=Q`, &string_reader, &r)
		thing, success, e := parse_half_move_from_pgn(&r)
		assert(success)
		assert(thing.piece_type == .Pawn)
	}
}

@(test)
parsing_pgn_tokens :: proc(_: ^testing.T) {
	parse_token_from_string_test :: proc(
		reader: ^bufio.Reader,
		string_reader: ^strings.Reader,
		thing: string,
		expected_err: io.Error = .None,
	) -> PGN_Parser_Token {
		reader_init_from_string(thing, string_reader, reader)
		// skip_characters_in_set_strings_variant(&r, skipped_strings[:])
		token, err := parse_pgn_token(reader)
		assert(err == expected_err, fmt.tprintln("token:", token, "error:", err))
		fmt.eprintln("Parsing full moves works")
		return token
	}
	_ = parse_token_from_string_test(&r, &string_reader, `1.`).(Move_Number)
	fmt.eprintln("TEST parsing .pgn move numbers as tokens successful")
	_ = parse_token_from_string_test(&r, &string_reader, `1-0`).(Chess_Result)
	fmt.eprintln("TEST parsing .pgn chess results as tokens successful")
	parse_token_from_string_test(&r, &string_reader, `e4`, .EOF)
	fmt.eprintln("TEST parsing .pgn chess moves as tokens successful")
	parse_token_from_string_test(&r, &string_reader, `$32 `, .None)
	fmt.eprintln("TEST parsing pgn chess move descriptor as tokens successful")
	parse_token_from_string_test(&r, &string_reader, `$32`, .EOF)
	fmt.eprintln("TEST parsing pgn chess move descriptor as tokens successful")
	parse_token_from_string_test(&r, &string_reader, `e1=Q`, .EOF)
	fmt.eprintln("TEST parsing pgn chess move pawn promotion")
	parse_token_from_string_test(&r, &string_reader, `e1=Q `, .None)
	fmt.eprintln("TEST parsing pgn chess move pawn promotion non-terminated")

	{
		reader_init_from_string(`1. e4 d5 1/2-1/2ok`, &string_reader, &r)
		token, err := parse_pgn_token(&r)
		assert(err == .None, fmt.tprintln(token))
		_ = token.(Move_Number)
		token, err = parse_pgn_token(&r)
		assert(err == .None, fmt.tprintln(token))
		_ = token.(PGN_Half_Move)
		token, err = parse_pgn_token(&r)
		assert(err == .None, fmt.tprintln(token))
		_ = token.(PGN_Half_Move)
		token, err = parse_pgn_token(&r)
		assert(err == .None, fmt.tprintln(token))
		_ = token.(Chess_Result)
		fmt.eprintln("TEST parsing multiple pgn tokens sequentially works")
	}
	{
		pgn_sample := `[Event "Valencia Casual Games"]`
		reader_init_from_string(pgn_sample, &string_reader, &r)
		data, err := parse_pgn_token(&r)
		assert(err == .None, fmt.tprintln(data))
		fmt.eprintln("TEST metadata parsing successful")
	}
	{
		test_name := "Variant parsing"
		reader_init_from_string("(something)", &string_reader, &r)
		did_consume, did_err := strip_variations(&r)
		assert(!did_err, fmt.tprintln(test_name, "encountered a reading error"))
		assert(did_consume, fmt.tprintln(test_name, "failed"))
		fmt.eprintln("TEST variants parsing successful")
	}
	{
		test_name := "Comment parsing"
		reader_init_from_string("{something}", &string_reader, &r)
		did_consume, did_err := strip_variations(&r)
		assert(!did_err, fmt.tprintln(test_name, "encountered a reading error"))
		assert(did_consume, fmt.tprintln(test_name, "failed"))
		fmt.eprintln("TEST comments parsing successful")
	}
	{
		test_name := "Comment in variant parsing"
		reader_init_from_string("(something{something})", &string_reader, &r)
		did_consume, did_err := strip_variations(&r)
		assert(!did_err, fmt.tprintln(test_name, "encountered a reading error"))
		assert(did_consume, fmt.tprintln(test_name, "failed"))
		fmt.eprintln("TEST coments in variants parsing successful")
	}
	{
		test_name := "Nested variants parsing"
		reader_init_from_string("(something(something{something}))", &string_reader, &r)
		did_consume, did_err := strip_variations(&r)
		assert(!did_err, fmt.tprintln(test_name, "encountered a reading error"))
		assert(did_consume, fmt.tprintln(test_name, "failed"))
		fmt.eprintln("TEST coments in variants parsing successful")
	}
}

@(test)
parsing_pgn_games :: proc(_: ^testing.T) {
	{
		reader_init_from_string(
			`1. e4 d5 2. exd5 Qxd5 3. Nc3 Qd8 4. Bc4 Nf6 5. Nf3 Bg4 6. h3 Bxf3 7. Qxf3 e6 8.
Qxb7 Nbd7 9. Nb5 Rc8 10. Nxa7 Nb6 11. Nxc8 Nxc8 12. d4 Nd6 13. Bb5+ Nxb5 14.
Qxb5+ Nd7 15. d5 exd5 16. Be3 Bd6 17. Rd1 Qf6 18. Rxd5 Qg6 19. Bf4 Bxf4 20.
Qxd7+ Kf8 21. Qd8# 1-0`,
			&string_reader,
			&r,
		)
		game, success := parse_full_game_from_pgn(&r)
		assert(success == true, fmt.tprintln(game))
		fmt.eprintln("TEST full moves portion parsing successful")
	}
	md := make(Metadata_Table)
	for pgn_sample in sample_pgn_strings {
		// fmt.eprintln(pgn_sample)
		reader_init_from_string(pgn_sample, &string_reader, &r)
		game, success := parse_full_game_from_pgn(&r, &md)
		assert(success == true, fmt.tprintln(game))
		fmt.eprintln(
			args = {
				"Number of moves:",
				len(game.moves),
				"number of metadata entries:",
				// len(game.metadatas),
			},
			sep = "\t",
		)
		fmt.eprintln("TEST full pgn game parsing successful")
	}
}

@(test)
getting_potential_moves :: proc(_: ^testing.T) {
	input := Square_Info_Full{{.Pawn, .White}, {1, 1}}
	moves := make([dynamic]Chess_Move_Full, 0, 6)
	defer delete(moves)
	// game_moves := make([dynamic]PGN_Half_Move, 0, 6, context.temp_allocator)
	// game := PGN_Parsed_Game{
	// 	moves = game_moves,
	// }
	// view: PGN_View
	// pgn_view_init(&view, &game)
	cb := default_chessboard_info()
	get_unrestricted_moves_of_piece(input, &moves, &cb)
	assert(len(moves) == 2, fmt.tprintf("moves:", &moves, len(moves)))
}

@(test)
/* Creates a list of chessboard states after performing each moves from a pgn */
create_chess_positions :: proc(t: ^testing.T) {
	sample_game_str := sample_pgn_strings[0]
	reader_init_from_string(sample_game_str, &string_reader, &r)
	md := make(Metadata_Table)
	sample_game, success := parse_full_game_from_pgn(&r, &md)
	assert(len(sample_game.moves) > 0)
	assert(len(sample_game.moves) == 41)

	// chessboard_states := make([dynamic]Chessboard_Info, 0)
	// append(&chessboard_states, default_chessboard_info())

	move_buffer := make([dynamic]Chess_Move_Full, 0)
	view := PGN_View{}
	pgn_view_init(&view, &sample_game)
	for move, index in sample_game.moves {
		// fmt.println(index)
		advanced, err := pgn_view_next_move(&view, &move_buffer)
		assert(advanced)
		assert(err == .None)
	}
}
