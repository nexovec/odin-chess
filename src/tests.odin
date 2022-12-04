package main
import bufio "core:bufio"
import c "core:c"
import "core:reflect"
import io "core:io"
import testing "core:testing"
import strings "core:strings"
import fmt "core:fmt"
import "core:runtime"
import "core:strconv"

reader_init_from_string :: proc(
	sample_string: string,
	string_reader: ^strings.Reader,
	reader: ^bufio.Reader,
) {
	r := strings.to_reader(string_reader, sample_string)
	bufio.reader_destroy(reader)
	bufio.reader_init(reader, r)
}
@(test)
run_tests :: proc(_: ^testing.T) {
	fmt.println("RUNNING TESTS")
	runtime.debug_trap()
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
			thing, success := parse_half_move_from_pgn(&r)
			assert(success)
			assert(thing.piece_type == .Rook)
		}
		{
			reader_init_from_string(`Rbe4`, &string_reader, &r)
			thing, success := parse_half_move_from_pgn(&r)
			assert(success)
			assert(thing.piece_type == .Rook)
		}
		{
			reader_init_from_string(`exd4`, &string_reader, &r)
			thing, success := parse_half_move_from_pgn(&r)
			assert(success)
			assert(thing.piece_type == .Pawn)
		}
		{
			reader_init_from_string(`Rbxe4`, &string_reader, &r)
			thing, success := parse_half_move_from_pgn(&r)
			assert(success)
			assert(thing.piece_type == .Rook)
		}
		{
			reader_init_from_string(`O-O-O`, &string_reader, &r)
			thing, success := parse_half_move_from_pgn(&r)
			assert(success)
			assert(thing.is_qside_castles)
		}
		{
			reader_init_from_string(`O-O`, &string_reader, &r)
			thing, success := parse_half_move_from_pgn(&r)
			assert(success)
			assert(thing.is_kside_castles)
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
			token, err := parse_pgn_token(reader)
			assert(err == .None, fmt.tprintln(token))
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
			token, err := parse_pgn_token(&r)
			assert(err == .None, fmt.tprintln(token))
			_=token.(Move_Number)
			token, err = parse_pgn_token(&r)
			assert(err == .None, fmt.tprintln(token))
			_=token.(PGN_Half_Move)
			token, err = parse_pgn_token(&r)
			assert(err == .None, fmt.tprintln(token))
			_=token.(PGN_Half_Move)
			token, err = parse_pgn_token(&r)
			assert(err == .None, fmt.tprintln(token))
			_=token.(Chess_Result)
			fmt.eprintln("TEST parsing multiple pgn tokens sequentially works")
		}
		{
			pgn_sample:=`[Event "Valencia Casual Games"]`
			reader_init_from_string(pgn_sample, &string_reader, &r)
			data, err:=parse_pgn_token(&r)
			assert(err==.None, fmt.tprintln(data))
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
			fmt.eprintln("TEST comments parsing successful")
		}
	}
	{
		{
			reader_init_from_string(`1. e4 d5 2. exd5 Qxd5 3. Nc3 Qd8 4. Bc4 Nf6 5. Nf3 Bg4 6. h3 Bxf3 7. Qxf3 e6 8.
Qxb7 Nbd7 9. Nb5 Rc8 10. Nxa7 Nb6 11. Nxc8 Nxc8 12. d4 Nd6 13. Bb5+ Nxb5 14.
Qxb5+ Nd7 15. d5 exd5 16. Be3 Bd6 17. Rd1 Qf6 18. Rxd5 Qg6 19. Bf4 Bxf4 20.
Qxd7+ Kf8 21. Qd8# 1-0`, &string_reader, &r)
			game, success:=parse_full_game_from_pgn(&r, true)
			assert(success==true, fmt.tprintln(game))
			fmt.eprintln("TEST full moves portion parsing successful")
		}
		inputs:=[]string{
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
Qxd7+ Kf8 21. Qd8# 1-0`
		}
		for pgn_sample in inputs{
			// fmt.eprintln(pgn_sample)
			reader_init_from_string(pgn_sample, &string_reader, &r)
			game, success:=parse_full_game_from_pgn(&r)
			assert(success==true, fmt.tprintln(game))
			fmt.eprintln(args={"Number of moves:", len(game.moves),"number of metadata entries:", len(game.metadatas)},sep="\t")
			// for i in game.metadatas{
			// 	fmt.println(i.key, i.value)
			// }
			// for i in game.moves{
			// 	fmt.println(i.piece_type)
			// }
			fmt.eprintln("TEST full pgn game parsing successful")
		}
	}
}
@(test)
getting_potential_moves :: proc(_: ^testing.T){
	input := Square_Info_Full{{.Pawn, .White}, {3,1}}
	moves := make([dynamic]Chess_Move_Full, 0, 6, context.temp_allocator)
	defer delete(moves)
	get_unrestricted_moves_of_piece(input, &moves)
	assert(len(moves) == 4, fmt.tprintf("moves:", &moves, len(moves)))
}
