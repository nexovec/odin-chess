package main
import bufio "core:bufio"
import io "core:io"
import strings "core:strings"
import fmt "core:fmt"

pgn_test_1 :: proc(sample_string: string){
    string_reader:strings.Reader
    r:=strings.to_reader(&string_reader, sample_string)
    reader:bufio.Reader
    bufio.reader_init(&reader, r)
    defer bufio.reader_destroy(&reader)
    moves:=make([dynamic]PGN_Half_Move,0)
    defer delete(moves)
    pgn_read_moves(&reader, moves)
}
run_tests :: proc(){
    fmt.println("RUNNING TESTS")
    pgn_test_1(`1. e4`)
    fmt.eprintln("test 1 successful")
    // pgn_test_1(`1. e4 d5`)
    // fmt.eprintln("test 2 successful")
    // pgn_test_1(`1. e4 d5 1-0`)
    // fmt.eprintln("test 3 successful")
    // pgn_test_1(`1. e4 d5 2. exd5 Qxd5 3. Nc3 Qd8 4. Bc4 Nf6 5. Nf3 Bg4 6. h3 Bxf3 7. Qxf3 e6 8.
    //     Qxb7 Nbd7 9. Nb5 Rc8 10. Nxa7 Nb6 11. Nxc8 Nxc8 12. d4 Nd6 13. Bb5+ Nxb5 14.
    //     Qxb5+ Nd7 15. d5 exd5 16. Be3 Bd6 17. Rd1 Qf6 18. Rxd5 Qg6 19. Bf4 Bxf4 20.
    //     Qxd7+ Kf8 21. Qd8# 1-0`)
}