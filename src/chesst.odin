package main

import "core:fmt"
// import "core:math"
// import "core:c/libc"
import SDL "vendor:sdl2"
import mu "vendor:microui"
import SDL_Image "vendor:sdl2/image"
import os "core:os"
import io "core:io"
import bufio "core:bufio"
import win32 "core:sys/windows"
import "core:strconv"
import strings "core:strings"
// import mem "core:mem"
// import runtime "core:runtime"
// import gl "vendor:OpenGL"

Vec2i :: distinct [2]i32

state := struct {
	// import stb_image "vendor:stb/image"
	mu_ctx:          mu.Context,
	log_buf:         [1 << 16]byte,
	log_buf_len:     int,
	log_buf_updated: bool,
	bg:              mu.Color,
	atlas_texture:   ^SDL.Texture,
	sdl_wsize: Vec2i
} {
	bg = {90, 95, 100, 255},
	sdl_wsize = Vec2i{960, 540}
}

MU_PROPERTIES:= struct{
	STATUS_BAR_HEIGHT:i32,
	MENU_HEIGHT:i32
} {
	STATUS_BAR_HEIGHT=25,
	MENU_HEIGHT = 30
}
cb_image: ^SDL.Surface
cb_texture: ^SDL.Texture

main :: proc() {
	fmt.eprintln("STARTING PROGRAM!")
	if err := SDL.Init({.VIDEO}); err != 0 {
		fmt.eprintln(err)
		return
	}
	defer SDL.Quit()
	display_mode:SDL.DisplayMode
	SDL.GetCurrentDisplayMode(0,&display_mode)
	refresh_rate:=display_mode.refresh_rate
	if refresh_rate == 0 {
		refresh_rate=60
	}
	time_per_tick:i32=1000/refresh_rate
	window := SDL.CreateWindow(
		"microui-odin",
		SDL.WINDOWPOS_UNDEFINED,
		SDL.WINDOWPOS_UNDEFINED,
		state.sdl_wsize.x,
		state.sdl_wsize.y,
		{.SHOWN, .RESIZABLE},
	)
	if window == nil {
		fmt.eprintln(SDL.GetError())
		return
	}
	defer SDL.DestroyWindow(window)
	backend_idx: i32 = -1
	if n := SDL.GetNumRenderDrivers(); n <= 0 {
		fmt.eprintln("No render drivers available")
		return
	} else {
		for i in 0 ..< n {
			info: SDL.RendererInfo
			if err := SDL.GetRenderDriverInfo(i, &info); err == 0 {
				// NOTE(bill): "direct3d" seems to not work correctly
				if info.name == "opengl" {
					backend_idx = i
					break
				}
			}
		}
	}

	renderer := SDL.CreateRenderer(window, backend_idx, {.ACCELERATED, .PRESENTVSYNC})
	if renderer == nil {
		fmt.eprintln("SDL.CreateRenderer:", SDL.GetError())
		return
	}
	defer SDL.DestroyRenderer(renderer)

	state.atlas_texture = SDL.CreateTexture(
		renderer,
		u32(SDL.PixelFormatEnum.RGBA32),
		.TARGET,
		mu.DEFAULT_ATLAS_WIDTH,
		mu.DEFAULT_ATLAS_HEIGHT,
	)
	assert(state.atlas_texture != nil)
	if err := SDL.SetTextureBlendMode(state.atlas_texture, .BLEND); err != 0 {
		fmt.eprintln("SDL.SetTextureBlendMode:", err)
		return
	}

	pixels := make([][4]u8, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT)
	for alpha, i in mu.default_atlas_alpha {
		pixels[i].rgb = 0xff
		pixels[i].a = alpha
	}

	if err := SDL.UpdateTexture(
		state.atlas_texture,
		nil,
		raw_data(pixels),
		4 * mu.DEFAULT_ATLAS_WIDTH,
	); err != 0 {
		fmt.eprintln("SDL.UpdateTexture:", err)
		return
	}

	// loading chessboard as image
	SDL_Image.Init(SDL_Image.INIT_PNG)
	defer SDL_Image.Quit()
	assert(os.is_file("assets/chessbcg.png"))
	// cb_image = SDL_Image.Load("assets/chessbcg.bmp")
	cb_image = SDL_Image.Load("assets/chessbcg.png")
	// assert(cb_image != nil)

	// cb_image = SDL.LoadBMP("assets/chessbcg.bmp")
	if(cb_image==nil){
		panic(fmt.tprint(SDL.GetError()))
	}
	defer SDL.FreeSurface(cb_image)

	cb_texture = SDL.CreateTextureFromSurface(renderer, cb_image)
	defer SDL.DestroyTexture(cb_texture)

	ctx := &state.mu_ctx
	mu.init(ctx)

	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

	lastTick:i32=0
	when RUN_TESTS{
		run_tests()
	}
	main_loop: for {
		for e: SDL.Event; SDL.PollEvent(&e);  /**/{
			#partial switch e.type {
			case .QUIT:
				break main_loop
			case .MOUSEMOTION:
				mu.input_mouse_move(ctx, e.motion.x, e.motion.y)
			case .MOUSEWHEEL:
				mu.input_scroll(ctx, e.wheel.x * 30, e.wheel.y * -30)
			case .TEXTINPUT:
				mu.input_text(ctx, string(cstring(&e.text.text[0])))

			case .MOUSEBUTTONDOWN, .MOUSEBUTTONUP:
				fn := mu.input_mouse_down if e.type == .MOUSEBUTTONDOWN else mu.input_mouse_up
				switch e.button.button {
				case SDL.BUTTON_LEFT:
					fn(ctx, e.button.x, e.button.y, .LEFT)
				case SDL.BUTTON_MIDDLE:
					fn(ctx, e.button.x, e.button.y, .MIDDLE)
				case SDL.BUTTON_RIGHT:
					fn(ctx, e.button.x, e.button.y, .RIGHT)
				}

			case .KEYDOWN, .KEYUP:
				if e.type == .KEYUP && e.key.keysym.sym == .ESCAPE {
					SDL.PushEvent(&SDL.Event{type = .QUIT})
				}

				fn := mu.input_key_down if e.type == .KEYDOWN else mu.input_key_up

				#partial switch e.key.keysym.sym {
				case .LSHIFT:
					fn(ctx, .SHIFT)
				case .RSHIFT:
					fn(ctx, .SHIFT)
				case .LCTRL:
					fn(ctx, .CTRL)
				case .RCTRL:
					fn(ctx, .CTRL)
				case .LALT:
					fn(ctx, .ALT)
				case .RALT:
					fn(ctx, .ALT)
				case .RETURN:
					fn(ctx, .RETURN)
				case .KP_ENTER:
					fn(ctx, .RETURN)
				case .BACKSPACE:
					fn(ctx, .BACKSPACE)
				}
			case .WINDOWEVENT:
				SDL.GetWindowSize(window, &state.sdl_wsize.x, &state.sdl_wsize.y)
			}
		}

		mu.begin(ctx)
		all_windows(ctx)
		mu.end(ctx)
		render(ctx, renderer)

		for i32(SDL.GetTicks())-lastTick < time_per_tick{
			SDL.Delay(1)
		}
		lastTick = i32(SDL.GetTicks())
	}
}

render :: proc(ctx: ^mu.Context, renderer: ^SDL.Renderer) {
	render_texture :: proc(
		renderer: ^SDL.Renderer,
		dst: ^SDL.Rect,
		src: mu.Rect,
		color: mu.Color,
	) {
		dst.w = src.w
		dst.h = src.h

		SDL.SetTextureAlphaMod(state.atlas_texture, color.a)
		SDL.SetTextureColorMod(state.atlas_texture, color.r, color.g, color.b)
		SDL.RenderCopy(renderer, state.atlas_texture, &SDL.Rect{src.x, src.y, src.w, src.h}, dst)
	}

	viewport_rect := &SDL.Rect{}
	SDL.GetRendererOutputSize(renderer, &viewport_rect.w, &viewport_rect.h)
	SDL.RenderSetViewport(renderer, viewport_rect)
	SDL.RenderSetClipRect(renderer, viewport_rect)
	SDL.SetRenderDrawColor(renderer, state.bg.r, state.bg.g, state.bg.b, state.bg.a)
	SDL.RenderClear(renderer)

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Text:
			dst := SDL.Rect{cmd.pos.x, cmd.pos.y, 0, 0}
			for ch in cmd.str do if ch & 0xc0 != 0x80 {
					r := min(int(ch), 127)
					src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + r]
					render_texture(renderer, &dst, src, cmd.color)
					dst.x += dst.w
				}
		case ^mu.Command_Rect:
			SDL.SetRenderDrawColor(renderer, cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
			SDL.RenderFillRect(renderer, &SDL.Rect{cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h})
		case ^mu.Command_Icon:
			src := mu.default_atlas[cmd.id]
			x := cmd.rect.x + (cmd.rect.w - src.w) / 2
			y := cmd.rect.y + (cmd.rect.h - src.h) / 2
			render_texture(renderer, &SDL.Rect{x, y, 0, 0}, src, cmd.color)
		case ^mu.Command_Clip:
			SDL.RenderSetClipRect(
				renderer,
				&SDL.Rect{cmd.rect.x, cmd.rect.y, cmd.rect.w, cmd.rect.h},
			)
		case ^mu.Command_Jump:
			unreachable()
		}
	}

	SDL.RenderCopyEx(
		renderer,
		cb_texture,
		nil,
		&SDL.Rect{500, 200, 100, 100},
		0,
		nil,
		SDL.RendererFlip.NONE,
	)

	SDL.RenderPresent(renderer)
}


u8_slider :: proc(ctx: ^mu.Context, val: ^u8, lo, hi: u8) -> (res: mu.Result_Set) {
	mu.push_id(ctx, uintptr(val))

	@(static)
	tmp: mu.Real
	tmp = mu.Real(val^)
	res = mu.slider(ctx, &tmp, mu.Real(lo), mu.Real(hi), 0, "%.0f", {.ALIGN_CENTER})
	val^ = u8(tmp)
	mu.pop_id(ctx)
	return
}

write_log :: proc(str: string) {
	state.log_buf_len += copy(state.log_buf[state.log_buf_len:], str)
	state.log_buf_len += copy(state.log_buf[state.log_buf_len:], "\n")
	state.log_buf_updated = true
}

read_log :: proc() -> string {
	return string(state.log_buf[:state.log_buf_len])
}
reset_log :: proc() {
	state.log_buf_updated = true
	state.log_buf_len = 0
}

skip_characters_in_set :: proc(reader:^bufio.Reader, chars:[$T]u8)->(did_consume:bool=false){
	skipping: for{
		r,s, err := bufio.reader_read_rune(reader)
		if err!=.None{
			panic("Error happened!")
		}
		if s!=1{
			panic("unexpected character")
		}
		c:=u8(r)
		for seeked_char in chars{
			if seeked_char == c{
				did_consume=true
				continue skipping
			}
		}
		bufio.reader_unread_rune(reader)
		return
	}
}

parse_metadata_row::proc(reader:^bufio.Reader)->(key:string, value:string){
	// assumes '[' has already been consumed
	line,e:=bufio.reader_read_slice(reader, '\n')
	if e!=.None{
		panic("something went wrong")
	}
	key_len:=0
	key_scan: for seeked_char in line{
		// FIXME: seeked_char could be utf-8 and produce weird behavior
		switch seeked_char{
			case '\"',' ':
				break key_scan
			case '[',']','\n','\t','\'', '\r':
				panic(fmt.tprint("disallowed character: ",seeked_char))
			case:
				key_len+=1
		}
	}
	assert(key_len>0)
	assert(line[key_len+1] == '\"')
	val_start:=key_len+2
	val_len:=0
	val_scan: for seeked_char in line[val_start:]{
		// FIXME: seeked_char could be utf-8 and produce weird behavior
		switch seeked_char{
			case '\"':
				break val_scan
			case '[',']','\n':
				panic("disallowed characters")
			case:
				val_len+=1
		}
	}
	assert(line[val_start+val_len]=='\"')
	assert(line[val_start+val_len+1]==']')
	key=transmute(string)line[:key_len]
	value=transmute(string)line[val_start:val_start+val_len]
	fmt.print("key:",key,"\t")
	fmt.println("value:",value)
	return key, value
}

open_file::proc(filepath:string="data/small.pgn"){
	splits := strings.split(filepath,".")
	extension:=splits[len(splits)-1]
	if extension != "pgn"{
		write_log(fmt.tprint(args={"Extension",extension,"not supported!"}))
		return
	}

	handle,err:=os.open(filepath)
	if err!=os.ERROR_NONE{
		write_log(fmt.tprint(args={"Couldn't open:", filepath}, sep = " "))
		when ODIN_OS == .Windows{
			thing:=win32.GetLastError()
			write_log(fmt.tprint("error code: ", thing))
		}
		return
	}
	assert(handle!=os.INVALID_HANDLE)
	defer os.close(handle)
	stream:=os.stream_from_handle(handle)
	raw_reader, ok_reader:=io.to_reader(stream)
	if ok_reader==false{
		write_log(fmt.tprint("Couldn't stream file: ", filepath))
		return
	}
	reader:bufio.Reader
	bufio.reader_init(&reader, raw_reader, 1<<16)
	defer bufio.reader_destroy(&reader)
	// FIXME: handle CRLF vs LF
	{
		_,s,err_BOM := bufio.reader_read_rune(&reader)
		if err_BOM != .None{
			write_log(fmt.tprint("Error reading the first rune of: ", filepath))
			return
		}
		if s == 1{
			// no BOM in the file -> reverting to first character
			bufio.reader_unread_rune(&reader)
		}else{
			fmt.println("skipping BOM in PGN file, BOM has length of ", s)
		}
	}
	Chess_Square :: distinct byte
	Chess_Move :: struct{
		src: Chess_Square,
		dest: Chess_Square
	}
	Metadata_Column :: struct{
		key:string,
		values: [dynamic]string
	}
	// FIXME: allocates
	metadata_table: [dynamic]Metadata_Column = make([dynamic]Metadata_Column, 18, 32)
	Parsing_Stage :: enum u8{
		None,
		Metadata,
		Moves
	}
	parsing_stage: Parsing_Stage=.None

	line_count:=1
	reader_loop: for {
		whitespace_runes:=[?]u8{' ', '\n', '\t'}
		switch parsing_stage{
			case .None:
				//skip whitespace
				skip_characters_in_set(&reader, whitespace_runes)
				r,s, err_rune := bufio.reader_read_rune(&reader)
				if err_rune == io.Error.EOF{
					break
				}else if err_rune != .None{
					panic("Error reading file")
				}
				if s!=1{
					panic(fmt.tprintf("PGN syntax error, unexpected multi-byte character at %s:%d", filepath, line_count))
				}
				c := u8(r)
				//decide if moves or metadata

				// TODO: test without conversion
				// switch r{
				switch c{
					case '[':
						bufio.reader_unread_rune(&reader)
						parsing_stage=.Metadata
						continue reader_loop
					case 'a'..='h', 'R','N','B','K','Q':
						bufio.reader_unread_rune(&reader)
						parsing_stage=.Moves
					case:
						panic(fmt.tprintf("PGN syntax error at %s:%d", filepath, line_count))
				}
			case .Metadata:
				fmt.println("parsing metadata:")
				metadata_parsing: for{
					r,s, err := bufio.reader_read_rune(&reader)
					if s!=1{
						panic("unexpected multi-byte character")
					}
					switch r{
						case '[':
							fmt.println("parsing metadata row")
							key, value:=parse_metadata_row(&reader)
						case '1'..='9':
							bufio.reader_unread_rune(&reader)
							parsing_stage=.Moves
							break metadata_parsing
						case ' ', '\t', '\n', '\r':
						case:
							panic(fmt.tprint(u8(r)))
					}
				}
			case .Moves:
				fmt.println("parsing moves")
				//reading full-moves
				moves_buffer:=make([dynamic]PGN_Half_Move)
				move:PGN_Half_Move
				fmt.println(len(moves_buffer))
				panic("This is not yet implemented")
			}
		}
	}
	reader_read_integer_1 :: proc(reader:^bufio.Reader, peek_size:int=3)->(result: int, err:io.Error){
		// TODO: test
		bytes, err_peek:=bufio.reader_peek(reader, peek_size+1)
		result=0
		if err_peek!=.None{
			err=err_peek
			return
		}
		len:=0
		counter: for b in bytes{
			switch b{
				case '0'..='9':
					len+=1
				case:
					break counter
			}
		}
		if len==0{
			err=io.Error.Unknown
		}else if len==peek_size+1{
			err=io.Error.Short_Buffer
		}else{
			err=.None
			result = strconv.atoi(transmute(string)bytes[:len])
		}
		for _ in 0..<len{
			bufio.reader_read_byte(reader)
		}
		return
	}
	reader_read_integer_2 :: proc(reader:^bufio.Reader)->(result: int = 0, err:io.Error = .None){
		buf:[dynamic]byte=make([dynamic]byte,0,context.temp_allocator)
		reading: for {
			b, err_read:=bufio.reader_read_byte(reader)
			if err_read!=.None{
				err = err_read
				return
			}
			switch b{
				case '0'..='9':
					append(&buf, b)
				case:
					err = bufio.reader_unread_byte(reader)
					assert(err==.None)
					break reading
			}
		}
		if len(buf)==0{
			err=io.Error.Unknown
		}else{
			// fmt.eprintln(transmute(string)buf[:], len(buf))
			result = strconv.atoi(transmute(string)buf[:])
			// assert(result!=0)
		}
		return
	}
	pgn_read_moves :: proc(reader: ^bufio.Reader, moves:[dynamic]PGN_Half_Move){
		moves:=moves
		for {
			skip_characters_in_set(reader, [?]u8{' ', '\t', '\n'})
			//reading move number
			seeked_char: rune
			size: int
			num, err:=reader_read_integer_2(reader)
			assert(err==.None, fmt.tprint(err,num))
			fmt.eprintln("move number",num)
			consume_char(reader,'.')

			consume_char(reader, ' ')
			move:=parse_half_move(reader)
			fmt.eprintln(move)
			append(&moves, move)

			consume_char(reader, ' ')
			result, has_result:=try_parse_result(reader)
			if has_result{
				break
			}

			move=parse_half_move(reader)
			fmt.eprintln(move)

			consume_char(reader, ' ')
			result, has_result=try_parse_result(reader)
			if has_result{
				break
			}
			panic("This is just a breakpoint")
		}
	}
	consume_char :: proc(reader: ^bufio.Reader, seeked_char:byte, error_if_not_found:bool=true)->(found:bool){
		c, err:=bufio.reader_read_byte(reader)
	if error_if_not_found==true{
		assert(err==.None)
		assert(c==seeked_char)
	}
	if c!=seeked_char{
		bufio.reader_unread_byte(reader)
		return false
	}
	return true
}

Chess_Result :: enum u8{
	White_Won,
	Black_Won,
	Draw
}
try_parse_result :: proc(reader: ^bufio.Reader)-> (result:Chess_Result, read:bool=false){
	buf, err:=bufio.reader_read_slice(reader, '\n')
	buffer:=transmute(string)buf
	assert(err==nil, fmt.tprintln(err))
	switch buffer{
		case "1-0":
			result=.White_Won
			read = true
		case "0-1":
			result=.Black_Won
			read = true
		case "1/2-1/2":
			read = true
			result=.Draw
	}
	return
}

Piece_Type :: enum u8{
	Pawn,
	Rook,
	Knight,
	Bishop,
	Queen,
	King,
}
PGN_Half_Move :: struct{
	piece_type:Piece_Type,
	known_src_row:bool,
	known_src_column:bool,
	src_x:u8,
	src_y:u8,
	dest_x:u8,
	dest_y:u8,
	is_mate:bool,
	is_check:bool,
	is_prequalified:bool,
	is_kside_castles:bool,
	is_qside_castles:bool
}

parse_half_move_no_postfix :: proc(reader:^bufio.Reader)->(hm:PGN_Half_Move={}){
	seeked_char, size, err:=bufio.reader_read_rune(reader)
	assert(size==1)
	switch seeked_char{
		case 'a'..='h':
			// this means it's a pawn move
			hm.piece_type=.Pawn
			// hm.dest_x=u8(seeked_char)-'a'
			bufio.reader_unread_rune(reader)
		case 'K':
			hm.piece_type=.King
		case 'N':
			hm.piece_type=.Knight
		case 'R':
			hm.piece_type=.Rook
		case 'B':
			hm.piece_type=.Bishop
		case 'Q':
			hm.piece_type=.Queen
		case 'O':
			unimplemented("No errors, but I don't know how to parse castling yet")
		case:
			panic("pgn syntax error reading half-moves")
	}
	// TODO: castles
	// TODO: annotations
	/*2 scenarios this solves
	1. Long form (i.e. exf3, Rbe7)
	2. short form (i.e. f3, Re7)
	and additionally it parses captures
	I assume it's the long-form, then I reshuffle the data if it's the short form
	*/
	parse_takes :: proc(reader:^bufio.Reader, hm:^PGN_Half_Move){
		x, err_x:=bufio.reader_read_byte(reader)
		assert(err_x==.None)
		y, err_y:=bufio.reader_read_byte(reader)
		assert(err_y==.None)
		switch x{
			case 'a'..='h':
				hm.dest_x=x
			case:
				panic("PGN syntax error")
		}
		switch y{
			case '1'..='8':
				hm.dest_y=y
			case:
				panic(fmt.tprint("PGN syntax error, unexpeted characters:", rune(x), rune(y)))
		}
	}
	seeked_char, size, err=bufio.reader_read_rune(reader)
	assert(size==1)
	switch seeked_char{
		case 'x':
			// means the move is short-form
			parse_takes(reader, &hm)
			return
		case 'a'..='h':
			hm.src_x=u8(seeked_char)
			hm.known_src_column=true
		case '1'..='8':
			// means the move is long form
			hm.src_y=u8(seeked_char)
			hm.known_src_row=true
		case:
			panic("Syntax error reading PGN file")
	}

	seeked_char, size, err=bufio.reader_read_rune(reader)
	assert(size==1)
	switch seeked_char{
		case 'x':
			// means the move is long-form
			parse_takes(reader, &hm)
			return
		case 'a'..='h':
			// means the move is long-form
			hm.dest_x=u8(seeked_char)
			seeked_char, size, err=bufio.reader_read_rune(reader)
			assert(size==1)
			switch seeked_char{
				case '1'..='8':
					hm.dest_x=u8(seeked_char)
				case:
					panic("PGN loading syntax error")
			}
			parse_move_annotation(reader, &hm)
			return
		case '1'..='8':
			// means this move is short-form
			hm.dest_x=hm.src_x
			hm.known_src_column=false
			hm.dest_y=u8(seeked_char)
			parse_move_annotation(reader, &hm)
			return
		case:
			panic("PGN loading syntax error")
	}
	}

parse_half_move :: proc(reader: ^bufio.Reader)->(hm:PGN_Half_Move){
	//read half-move
	hm=parse_half_move_no_postfix(reader)
	//read post-fix
	parse_move_annotation(reader, &hm)
	return
}

parse_move_annotation :: proc(reader: ^bufio.Reader, move: ^PGN_Half_Move){
	// strip tags (+, #)
	move.is_check=consume_char(reader,'+',false)
	move.is_mate=consume_char(reader,'#',false)
	// TODO: strip labels(+-, =, ...)

	// strip annotations
	// TODO: nested variations and nested comments
	if consume_char(reader, '(', false){
		_, err:=bufio.reader_read_slice(reader,')')
		assert(err==.None)
	}

	// strip comments
	if consume_char(reader, '{', false){
		_, err:=bufio.reader_read_slice(reader,'}')
		assert(err==.None)
	}
}


all_windows :: proc(ctx: ^mu.Context) {
	@(static)
	opts := mu.Options{.NO_CLOSE}
	opts_navbar := mu.Options{.NO_CLOSE, .NO_RESIZE, .NO_TITLE}

	if mu.window(ctx, "Menu Bar", {0, 0, state.sdl_wsize.x, MU_PROPERTIES.MENU_HEIGHT}, opts_navbar) {
		w := mu.get_current_container(ctx)
		w.rect.w = state.sdl_wsize.x
		mu.layout_row(ctx, []i32{60, 60, 60}, 0)

		if .SUBMIT in mu.button(ctx, "File") {
			mu.open_popup(ctx, "popup")
			fmt.println("click")
		}

		if mu.begin_popup(ctx, "popup") {
			mu.label(ctx, "Hello")
			if .SUBMIT in mu.button(ctx, "New...") {
				mu.open_popup(ctx, "new_suboptions")
			}
			if mu.begin_popup(ctx, "new_suboptions") {
				mu.button(ctx, "Game")
				mu.button(ctx, "Database")
				mu.end_popup(ctx)
			}
			if .SUBMIT in mu.button(ctx, "Import"){
				open_file()
			}
			mu.button(ctx, "Export")
			mu.button(ctx, "Chesst files")
			mu.button(ctx, "Quit")
			mu.end_popup(ctx)
		}

		if .SUBMIT in mu.button(ctx, "Project") {
			mu.open_popup(ctx, "view_suboptions")
		}

		if mu.begin_popup(ctx, "view_suboptions") {
			mu.button(ctx, "Save as template")
			mu.button(ctx, "Update template")
			mu.button(ctx, "Open template")
			if .SUBMIT in mu.button(ctx, "Recent...") {
				mu.label(ctx, "last open editors")
			}
			mu.end_popup(ctx)
		}

		if .SUBMIT in mu.button(ctx, "Help") {
			mu.open_popup(ctx, "help_suboptions")
		}

		if mu.begin_popup(ctx, "help_suboptions") {
			mu.button(ctx, "Documentation")
			mu.button(ctx, "Give feedback")
			mu.button(ctx, "Preferences")
			mu.end_popup(ctx)
		}
	}

	if(mu.window(ctx, "Status bar", mu.Rect{0, state.sdl_wsize.y-MU_PROPERTIES.STATUS_BAR_HEIGHT, 8500, MU_PROPERTIES.STATUS_BAR_HEIGHT}, opts_navbar)){
		// changes size of status BAR
		status_bar := mu.get_current_container(ctx)
		status_bar.rect.y = state.sdl_wsize.y - MU_PROPERTIES.STATUS_BAR_HEIGHT
		mu.label(ctx, "Status: Idle")
	}

	if mu.window(ctx, "Demo Window", {40, 40, 300, 450}, opts) {
		if .ACTIVE in mu.header(ctx, "Window Info") {
			win := mu.get_current_container(ctx)
			mu.layout_row(ctx, {54, -1}, 0)
			mu.label(ctx, "Position:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.x, win.rect.y))
			mu.label(ctx, "Size:")
			mu.label(ctx, fmt.tprintf("%d, %d", win.rect.w, win.rect.h))
		}

		if .ACTIVE in mu.header(ctx, "Window Options") {
			mu.layout_row(ctx, {120, 120, 120}, 0)
			for opt in mu.Opt {
				state := opt in opts
				if .CHANGE in mu.checkbox(ctx, fmt.tprintf("%v", opt), &state) {
					if state {
						opts += {opt}
					} else {
						opts -= {opt}
					}
				}
			}
		}

		if .ACTIVE in mu.header(ctx, "Test Buttons", {.EXPANDED}) {
			mu.layout_row(ctx, {86, -110, -1})
			mu.label(ctx, "Test buttons 1:")
			if .SUBMIT in mu.button(ctx, "Button 1") {write_log("Pressed button 1")}
			if .SUBMIT in mu.button(ctx, "Button 2") {write_log("Pressed button 2")}
			mu.label(ctx, "Test buttons 2:")
			if .SUBMIT in mu.button(ctx, "Button 3") {write_log("Pressed button 3")}
			if .SUBMIT in mu.button(ctx, "Button 4") {write_log("Pressed button 4")}
		}

		if .ACTIVE in mu.header(ctx, "Tree and Text", {.EXPANDED}) {
			mu.layout_row(ctx, {140, -1})
			mu.layout_begin_column(ctx)
			if .ACTIVE in mu.treenode(ctx, "Test 1") {
				if .ACTIVE in mu.treenode(ctx, "Test 1a") {
					mu.label(ctx, "Hello")
					mu.label(ctx, "world")
				}
				if .ACTIVE in mu.treenode(ctx, "Test 1b") {
					if .SUBMIT in mu.button(ctx, "Button 1") {write_log("Pressed button 1")}
					if .SUBMIT in mu.button(ctx, "Button 2") {write_log("Pressed button 2")}
				}
			}
			if .ACTIVE in mu.treenode(ctx, "Test 2") {
				mu.layout_row(ctx, {53, 53})
				if .SUBMIT in mu.button(ctx, "Button 3") {write_log("Pressed button 3")}
				if .SUBMIT in mu.button(ctx, "Button 4") {write_log("Pressed button 4")}
				if .SUBMIT in mu.button(ctx, "Button 5") {write_log("Pressed button 5")}
				if .SUBMIT in mu.button(ctx, "Button 6") {write_log("Pressed button 6")}
			}
			if .ACTIVE in mu.treenode(ctx, "Test 3") {
				@(static)
				checks := [3]bool{true, false, true}
				mu.checkbox(ctx, "Checkbox 1", &checks[0])
				mu.checkbox(ctx, "Checkbox 2", &checks[1])
				mu.checkbox(ctx, "Checkbox 3", &checks[2])

			}
			mu.layout_end_column(ctx)

			mu.layout_begin_column(ctx)
			mu.layout_row(ctx, {-1})
			mu.text(
				ctx,
				"Lorem ipsum dolor sit amet, consectetur adipiscing " +
				"elit. Maecenas lacinia, sem eu lacinia molestie, mi risus faucibus " +
				"ipsum, eu varius magna felis a nulla.",
			)
			mu.layout_end_column(ctx)
		}

		if .ACTIVE in mu.header(ctx, "Background Colour", {.EXPANDED}) {
			mu.layout_row(ctx, {-78, -1}, 68)
			mu.layout_begin_column(ctx)
			{
				mu.layout_row(ctx, {46, -1}, 0)
				mu.label(ctx, "Red:");u8_slider(ctx, &state.bg.r, 0, 255)
				mu.label(ctx, "Green:");u8_slider(ctx, &state.bg.g, 0, 255)
				mu.label(ctx, "Blue:");u8_slider(ctx, &state.bg.b, 0, 255)
			}
			mu.layout_end_column(ctx)

			r := mu.layout_next(ctx)
			mu.draw_rect(ctx, r, state.bg)
			mu.draw_box(ctx, mu.expand_rect(r, 1), ctx.style.colors[.BORDER])
			mu.draw_control_text(
				ctx,
				fmt.tprintf("#%02x%02x%02x", state.bg.r, state.bg.g, state.bg.b),
				r,
				.TEXT,
				{.ALIGN_CENTER},
			)
		}
	}

	if mu.window(ctx, "Log Window", {350, 40, 300, 200}, opts) {
		mu.layout_row(ctx, {-1}, -28)
		mu.begin_panel(ctx, "Log")
		mu.layout_row(ctx, {-1}, -1)
		mu.text(ctx, read_log())
		if state.log_buf_updated {
			panel := mu.get_current_container(ctx)
			panel.scroll.y = panel.content_size.y
			state.log_buf_updated = false
		}
		mu.end_panel(ctx)

		@(static)
		buf: [128]byte
		@(static)
		buf_len: int
		submitted := false
		mu.layout_row(ctx, {-70, -1})
		if .SUBMIT in mu.textbox(ctx, buf[:], &buf_len) {
			mu.set_focus(ctx, ctx.last_id)
			submitted = true
		}
		if .SUBMIT in mu.button(ctx, "Submit") {
			submitted = true
		}
		if submitted {
			write_log(string(buf[:buf_len]))
			buf_len = 0
		}
	}

	if mu.window(ctx, "Style Window", {350, 250, 300, 240}) {
		@(static)
		colors := [mu.Color_Type]string {
			.TEXT         = "text",
			.BORDER       = "border",
			.WINDOW_BG    = "window bg",
			.TITLE_BG     = "title bg",
			.TITLE_TEXT   = "title text",
			.PANEL_BG     = "panel bg",
			.BUTTON       = "button",
			.BUTTON_HOVER = "button hover",
			.BUTTON_FOCUS = "button focus",
			.BASE         = "base",
			.BASE_HOVER   = "base hover",
			.BASE_FOCUS   = "base focus",
			.SCROLL_BASE  = "scroll base",
			.SCROLL_THUMB = "scroll thumb",
		}

		sw := i32(f32(mu.get_current_container(ctx).body.w) * 0.14)
		mu.layout_row(ctx, {80, sw, sw, sw, sw, -1})
		for label, col in colors {
			mu.label(ctx, label)
			u8_slider(ctx, &ctx.style.colors[col].r, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].g, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].b, 0, 255)
			u8_slider(ctx, &ctx.style.colors[col].a, 0, 255)
			mu.draw_rect(ctx, mu.layout_next(ctx), ctx.style.colors[col])
		}
	}

}