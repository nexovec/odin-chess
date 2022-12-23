package main

import "core:fmt"
import SDL "vendor:sdl2"
import mu "libs:microui"
import SDL_Image "vendor:sdl2/image"
import SDL_ttf "vendor:sdl2/ttf"
import os "core:os"
import io "core:io"
import mem "core:mem"
import bufio "core:bufio"
import win32 "core:sys/windows"
import strings "core:strings"

Vec2i :: distinct [2]i32

PGN_View :: struct{
	using game: ^PGN_Parsed_Game,
	starting_position: Chessboard_Info,
	current_position: Chessboard_Info,
	current_move: i32,
}
// NOTE(nexovec): expects the starting position to be the default chessboard
pgn_view_init :: proc(view: ^PGN_View, game: ^PGN_Parsed_Game) {
	assert(game.metadatas.allocator.procedure != nil)
	assert(game.moves.allocator.procedure != nil)
	view.game = game
	view.starting_position = default_chessboard_info()
	view.current_position = default_chessboard_info()
	view.current_move = 0
}
PGN_View_Error :: enum u8{
	None,
	No_More_Moves,
	Couldnt_Find_Move,
}
pgn_view_next_move :: proc(view: ^PGN_View, move_buffer: ^[dynamic] Chess_Move_Full) -> (advanced: bool, success: PGN_View_Error) {
	state_before_move := view.current_position
	state_after_move := view.current_position
	if cast(int)view.current_move >= len(view.moves)  || cast(int)view.current_move < 0{
		return false, .No_More_Moves
	}
	move := view.moves[view.current_move]
	traversing_squares: for contents, square_index in state_after_move.square_info {
		if contents.piece_type != move.piece_type {
			continue
		}
		square_info := Square_Info_Full{}
		square_info.piece = contents
		square_info.x = cast(u8)square_index % 8
		square_info.y = cast(u8)square_index / 8
		clear(move_buffer)
		moves_possible_from_square := get_unrestricted_moves_of_piece(square_info, move_buffer, &state_before_move)
		side_to_move := cast(Piece_Color)((view.current_move + 1) % 2)
		if square_info.piece_type != move.piece_type || square_info.piece_color != side_to_move {
			continue
		}
		for move_possible in moves_possible_from_square {
			if move_possible.dst == move.dst {
				dst_index := move.dst.x + move.dst.y * 8
				if move.known_src_column && move_possible.src.x != move.src_x {
					fmt.eprintln("uhh", move_possible.src.x, move.src_x)
					continue
				}
				else if move.known_src_row && move_possible.src.y != move.src_y {
					// fmt.eprintln("uhh")
					continue
				}
				else if move.piece_type == .Pawn && state_after_move.square_info[dst_index].piece_type == .None && move_possible.dst.x != square_info.x{
					// fmt.eprintln("uhh")
					continue
				}
				state_after_move.square_info[dst_index] = contents
				state_after_move.square_info[square_index] = Square_Info_Full{}
				view.current_position = state_after_move
				state_after_move = state_before_move
				advanced = true
			}
		}
	}
	if advanced {
		view.current_move += 1
		return true, .None
	}
	else{
		return false, .Couldnt_Find_Move
	}
}

UI_Context :: struct {
	held_piece:                   Piece_Info,
	piece_resolution:             i32,
	chessboard_resolution:        i32,
	hovered_square:               Vec2i,
	chessboard_square_mask_green: [64]bool,
	game_panel_contents:		  string,
}
default_ui_ctx := UI_Context{{.Pawn, .Black}, 64, 1024, {0, 0}, {}, ""}
state := struct {
	mu_ctx:          mu.Context,
	ui_ctx:          UI_Context,
	loaded_game:     PGN_View,
	log_buf:         [1 << 16]byte,
	log_buf_len:     int,
	log_buf_updated: bool,
	bg:              mu.Color,
	atlas_texture:   ^SDL.Texture,
	sdl_wsize:       Vec2i,
} {
	bg = {90, 95, 100, 255},
	sdl_wsize = Vec2i{960, 540},
	ui_ctx = default_ui_ctx,
}

MU_PROPERTIES := struct {
	STATUS_BAR_HEIGHT: i32,
	MENU_HEIGHT:       i32,
} {
	STATUS_BAR_HEIGHT = 25,
	MENU_HEIGHT       = 30,
}
cb_image: ^SDL.Surface
cb_texture: ^SDL.Texture

chess_font: ^SDL_ttf.Font

textures: map[string]^SDL.Texture

render_piece :: proc(renderer: ^SDL.Renderer, piece_info: Piece_Info, dst_rect: ^SDL.Rect) {
	piece_atlas := textures["PiecesAtlas"]
	assert(piece_atlas != nil)
	src_rect := SDL.Rect{
		state.ui_ctx.piece_resolution * i32(piece_info.piece_type),
		i32(piece_info.piece_color) * state.ui_ctx.piece_resolution,
		state.ui_ctx.piece_resolution,
		state.ui_ctx.piece_resolution,
	}
	SDL.RenderCopy(renderer, piece_atlas, &src_rect, dst_rect)
}

render_piece_at_tile :: proc(
	renderer: ^SDL.Renderer,
	piece_type: Piece_Type,
	color: Piece_Color,
	pos: Vec2i,
) {
	dst_tile_size := state.ui_ctx.chessboard_resolution / 8
	dst_rect := SDL.Rect{
		pos.x * dst_tile_size,
		pos.y * dst_tile_size,
		dst_tile_size,
		dst_tile_size,
	}
	render_piece(renderer, {piece_type, color}, &dst_rect)
}

// represent a chessboard
Piece_Info :: struct {
	piece_type:  Piece_Type,
	piece_color: Piece_Color,
}

Chessboard_Info :: struct {
	square_info: [64]Piece_Info,
}

Chessboard_location :: struct {
	x: u8,
	y: u8,
}

Square_Info_Full :: struct {
	using piece: Piece_Info,
	using coord: Chessboard_location,
}

Chess_Move :: struct {
	src: Chessboard_location,
	dst: Chessboard_location,
}

Chess_Move_Full :: struct {
	using move:  Chess_Move,
	piece_type:  Piece_Type,
	piece_color: Piece_Color,
}

@(private="file")
append_knight_moves :: proc(mv: Square_Info_Full, move_prefab: Chess_Move_Full, moves: ^[dynamic]Chess_Move_Full, cb: ^Chessboard_Info) -> (can_take: bool){
	c := []Chessboard_location{
		{mv.x + 1, mv.y + 2},
		{mv.x + 1, mv.y - 2},
		{mv.x - 1, mv.y + 2},
		{mv.x - 1, mv.y - 2},
		{mv.x + 2, mv.y + 1},
		{mv.x + 2, mv.y - 1},
		{mv.x - 2, mv.y + 1},
		{mv.x - 2, mv.y - 1},
	}
	move := move_prefab
	for p in c {
		piece_at_square := piece_at(p.x, p.y, cb)
		is_empty_square := piece_at_square.piece_type == .None
		is_same_color := piece_at_square.piece_color != move.piece_color
		if p.x < 8 && p.y < 8  && (is_empty_square || is_same_color){
			move.dst = p
			append(moves, move)
		}
		if p.x < 8 && p.y < 8  && !is_empty_square && is_same_color{
			can_take = true
		}
	}
	return
}

@(private="file")
append_bishop_moves :: proc(mv: Square_Info_Full, move_prefab: Chess_Move_Full, moves: ^[dynamic]Chess_Move_Full, cb: ^Chessboard_Info) -> (can_take: bool){
	// TODO: return the right value
	move := move_prefab
	for i: u8 = 1; mv.x + i < 8 && mv.y + i < 8; i += 1 {
		move.dst = {mv.x + i, mv.y + i}
		square_info := cb.square_info[move.dst.x + (move.dst.y) * 8]
		if square_info.piece_type == .None || square_info.piece_color != mv.piece_color{
			append(moves, move)
		}
		if square_info.piece_type != .None{
			break
		}
	}
	for i: u8 = 1; mv.x - i < 8 && mv.y + i < 8; i += 1 {
		move.dst = {mv.x - i, mv.y + i}
		square_info := cb.square_info[move.dst.x + (move.dst.y) * 8]
		if square_info.piece_type == .None || square_info.piece_color != mv.piece_color{
			append(moves, move)
		}
		if square_info.piece_type != .None{
			break
		}
	}
	for i: u8 = 1; mv.x + i < 8 && mv.y - i < 8; i += 1 {
		move.dst = {mv.x + i, mv.y - i}
		square_info := cb.square_info[move.dst.x + (move.dst.y) * 8]
		if square_info.piece_type == .None || square_info.piece_color != mv.piece_color{
			append(moves, move)
		}
		if square_info.piece_type != .None{
			break
		}
	}
	for i: u8 = 1; mv.x - i < 8 && mv.y - i < 8; i += 1 {
		move.dst = {mv.x - i, mv.y - i}
		square_info := cb.square_info[move.dst.x + (move.dst.y) * 8]
		if square_info.piece_type == .None || square_info.piece_color != mv.piece_color{
			append(moves, move)
		}
		if square_info.piece_type != .None{
			break
		}
	}
	return
}
@(private="file")
append_rook_moves :: proc(mv: Square_Info_Full, move_prefab: Chess_Move_Full, moves: ^[dynamic]Chess_Move_Full, cb: ^Chessboard_Info) -> (can_take: bool){
	// TODO: return the right value
	move := move_prefab
	for i: u8 = mv.x - 1; i < 8; i -= 1{
		move.dst = {i, mv.y}
		square_info := cb.square_info[move.dst.x + (move.dst.y) * 8]
		if square_info.piece_type == .None || square_info.piece_color != mv.piece_color{
			append(moves, move)
		}
		if square_info.piece_type != .None{
			break
		}
	}
	for i: u8 = mv.y - 1; i < 8; i -= 1{
		move.dst = {mv.x, i}
		square_info := cb.square_info[move.dst.x + (move.dst.y) * 8]
		if square_info.piece_type == .None || square_info.piece_color != mv.piece_color{
			append(moves, move)
		}
		if square_info.piece_type != .None{
			break
		}
	}
	for i: u8 = mv.x + 1; i < 8; i += 1 {
		move.dst = {i, mv.y}
		square_info := cb.square_info[move.dst.x + (move.dst.y) * 8]
		if square_info.piece_type == .None || square_info.piece_color != mv.piece_color{
			append(moves, move)
		}
		if square_info.piece_type != .None{
			break
		}
	}
	for i: u8 = mv.y + 1; i < 8; i += 1 {
		move.dst = {mv.x, i}
		square_info := cb.square_info[move.dst.x + (move.dst.y) * 8]
		if square_info.piece_type == .None || square_info.piece_color != mv.piece_color{
			append(moves, move)
		}
		if square_info.piece_type != .None{
			break
		}
	}
	return
}

piece_at :: #force_inline proc(x: u8, y: u8, cb: ^Chessboard_Info) -> Piece_Info {
	if x>7 || y>7 || x<0 || y<0 {
		return {}
	}
	return cb.square_info[x + y * 8]
}

get_unrestricted_moves_of_piece :: proc(mv: Square_Info_Full, moves: ^[dynamic]Chess_Move_Full, cb: ^Chessboard_Info) -> ^[dynamic]Chess_Move_Full {
	move := Chess_Move_Full{}
	move.piece_color = mv.piece_color
	move.piece_type = mv.piece_type
	move.src = mv.coord
	switch mv.piece_type {
	case .None:
	case .Pawn:
		is_b := mv.piece_color == .Black
		is_w := !is_b
		move.dst = {mv.x - 1, mv.y - u8(is_b) + u8(is_w)}
		piece_left_taking := piece_at(move.dst.x, move.dst.y, cb)
		if mv.x > 0 && piece_left_taking.piece_type != .None && piece_left_taking.piece_color != mv.piece_color {
			append(moves, move)
		}
		move.dst = {mv.x + 1, mv.y - u8(is_b) + u8(is_w)}
		piece_left_taking = piece_at(move.dst.x, move.dst.y, cb)
		if mv.y < 7  && piece_left_taking.piece_type != .None && piece_left_taking.piece_color != mv.piece_color{
			append(moves, move)
		}
		move.dst = {mv.x, mv.y - u8(is_b) + u8(is_w)}
		piece_left_taking = piece_at(move.dst.x, move.dst.y, cb)
		if piece_left_taking.piece_type == .None {
			append(moves, move)
		}
		// double move
		move.dst = {mv.x, mv.y + (-u8(is_b) + u8(is_w))*2}
		piece_left_taking = piece_at(move.dst.x, move.dst.y, cb)
		is_white_double_jump := move.dst.y == 3 && is_w
		is_black_double_jump := move.dst.y == 4 && is_b
		is_double_jump := is_white_double_jump || is_black_double_jump
		if piece_left_taking.piece_type == .None && is_double_jump {
			append(moves, move)
		}
		if is_b && mv.y == 1 {
			// TODO: unpack the existing moves
			unimplemented("Pawn promotions are not implemented yet")
		} else if is_w && mv.y == 6 {
			unimplemented("Pawn promotions are not implemented yet")
		}
	case .Rook:
		append_rook_moves(mv, move, moves, cb)
	case .Knight:
		append_knight_moves(mv, move, moves, cb)
	case .Bishop:
		append_bishop_moves(mv, move, moves, cb)
	case .King:
		c := []Chessboard_location{
			{mv.x - 1, mv.y + 1},
			{mv.x - 1, mv.y},
			{mv.x - 1, mv.y - 1},
			{mv.x, mv.y + 1},
			{mv.x, mv.y - 1},
			{mv.x + 1, mv.y + 1},
			{mv.x + 1, mv.y},
			{mv.x + 1, mv.y - 1},
		}
		is_square_endangered :: proc(mv: Square_Info_Full, move_prefab: Chess_Move_Full, moves: ^[dynamic]Chess_Move_Full, cb: ^Chessboard_Info) -> bool{
			move := move_prefab
			move_len_before_checks := len(moves)
			endangered_by_bishop := append_bishop_moves(mv, move, moves, cb)
			resize(moves, move_len_before_checks)
			endangered_by_rook := append_rook_moves(mv, move, moves, cb)
			resize(moves, move_len_before_checks)
			endangered_by_knight := append_knight_moves(mv, move, moves, cb)
			resize(moves, move_len_before_checks)
			return endangered_by_bishop || endangered_by_knight || endangered_by_rook
		}
		for p in c {
			// TODO: restrict from moving into checks
			piece_at_square := piece_at(p.x, p.y, cb)
			is_empty_square := piece_at_square.piece_type == .None
			is_same_color := piece_at_square.piece_color != move.piece_color
			if p.x < 8 && p.y < 8  && (is_empty_square || is_same_color){
				move.dst = p
				append(moves, move)
			}
		}

		// FIXME: assumes king hasn't lost its castling rights

		// king side castling
		move.dst = {7, mv.y}
		piece_at_rook_position := piece_at(move.dst.x, move.dst.y, cb)
		is_rook_there := piece_at_rook_position.piece_color == mv.piece_color && piece_at_rook_position.piece_type == .Rook
		move_len_before_checks := len(moves)
		move.dst = {mv.x + 1, mv.y}
		king_right_placement := (piece_at(4, 0, cb).piece_type == .King && mv.piece_color == .White) || (piece_at(4, 7, cb).piece_type == .King && mv.piece_color == .Black)
		square_f_endangered := is_square_endangered(mv, move, moves, cb)
		squares_occupied := piece_at(move.dst.x, move.dst.y, cb).piece_type != .None
		move.dst = {mv.x + 2, mv.y}
		square_g_endangered := is_square_endangered(mv, move, moves, cb)
		squares_occupied |= piece_at(move.dst.x, move.dst.y, cb).piece_type != .None
		if king_right_placement && !square_f_endangered && !square_g_endangered && !squares_occupied && is_rook_there{
			move.dst = {mv.x + 2, mv.y}
			append(moves, move)
		}
		// queen side castling
		move.dst = {7, mv.y}
		piece_at_rook_position = piece_at(move.dst.x, move.dst.y, cb)
		is_rook_there = piece_at_rook_position.piece_color == mv.piece_color && piece_at_rook_position.piece_type == .Rook
		move_len_before_checks = len(moves)
		move.dst = {mv.x - 2, mv.y}
		square_c_endangered := is_square_endangered(mv, move, moves, cb)
		squares_occupied = piece_at(move.dst.x, move.dst.y, cb).piece_type != .None
		move.dst = {mv.x - 3, mv.y}
		square_d_endangered := is_square_endangered(mv, move, moves, cb)
		squares_occupied |= piece_at(move.dst.x, move.dst.y, cb).piece_type != .None
		if king_right_placement && !square_d_endangered && !square_c_endangered && !squares_occupied && is_rook_there{
			move.dst = {mv.x + 2, mv.y}
			append(moves, move)
		}
	case .Queen:
		append_bishop_moves(mv, move, moves, cb)
		append_rook_moves(mv, move, moves, cb)
	}
	return moves
}

render_chessboard_position :: proc(renderer: ^SDL.Renderer, cb: Chessboard_Info) {
	for square, i in cb.square_info {
		index := 63 - i
		render_piece_at_tile(
			renderer,
			square.piece_type,
			square.piece_color,
			Vec2i{7 - cast(i32)index % 8, cast(i32)index / 8},
		)
	}
}

place_piece :: proc(cbinfo: ^Chessboard_Info, x: u8, y: u8, piece: Piece_Info) {
	cbinfo.square_info[x + 8 * y] = piece
}

default_chessboard_info :: proc() -> Chessboard_Info {
	cbinfo := Chessboard_Info{}
	place_piece(&cbinfo, 7, 7, {.Rook, .Black})
	place_piece(&cbinfo, 0, 7, {.Rook, .Black})
	place_piece(&cbinfo, 1, 7, {.Knight, .Black})
	place_piece(&cbinfo, 6, 7, {.Knight, .Black})
	place_piece(&cbinfo, 2, 7, {.Bishop, .Black})
	place_piece(&cbinfo, 5, 7, {.Bishop, .Black})
	place_piece(&cbinfo, 3, 7, {.Queen, .Black})
	place_piece(&cbinfo, 4, 7, {.King, .Black})
	place_piece(&cbinfo, 7, 0, {.Rook, .White})
	place_piece(&cbinfo, 0, 0, {.Rook, .White})
	place_piece(&cbinfo, 1, 0, {.Knight, .White})
	place_piece(&cbinfo, 6, 0, {.Knight, .White})
	place_piece(&cbinfo, 2, 0, {.Bishop, .White})
	place_piece(&cbinfo, 5, 0, {.Bishop, .White})
	place_piece(&cbinfo, 3, 0, {.Queen, .White})
	place_piece(&cbinfo, 4, 0, {.King, .White})
	for i: u8 = 0; i < 8; i += 1 {
		place_piece(&cbinfo, i, 6, {.Pawn, .Black})
	}
	for i: u8 = 0; i < 8; i += 1 {
		place_piece(&cbinfo, i, 1, {.Pawn, .White})
	}
	return cbinfo
}

main :: proc() {
	fmt.eprintln("STARTING PROGRAM!")
	if err := SDL.Init(SDL.INIT_EVERYTHING); err != 0 {
		fmt.eprintln(err)
		return
	}
	defer SDL.Quit()
	display_mode: SDL.DisplayMode
	SDL.GetCurrentDisplayMode(0, &display_mode)
	refresh_rate := display_mode.refresh_rate
	if refresh_rate <= 30 {
		refresh_rate = 30
	}
	time_per_tick: u32 = 1000 / cast(u32)refresh_rate
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

	renderer := SDL.CreateRenderer(
		window,
		backend_idx,
		{.ACCELERATED, .PRESENTVSYNC, .TARGETTEXTURE},
	)
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
	defer delete(pixels)
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

	if SDL_ttf.Init() < 0 {
		panic("Couldn't initialize SDL-ttf")
	}
	defer SDL_ttf.Quit()
	chess_font = SDL_ttf.OpenFont("assets/fonts/chess_font.ttf", state.ui_ctx.piece_resolution)
	if SDL_ttf.GetError() != "" {
		panic(fmt.tprintln(SDL_ttf.GetError()))
	}
	defer SDL_ttf.CloseFont(chess_font)

	// loading chessboard as image
	SDL_Image.Init(SDL_Image.InitFlags{.JPG, .PNG})
	defer SDL_Image.Quit()
	assert(os.is_file("assets/chessbcg.jpeg"), "Can't find assets")
	cb_image = SDL_Image.Load("assets/chessbcg.jpeg")

	if (cb_image == nil) {
		panic(fmt.tprint(SDL.GetError()))
	}
	defer SDL.FreeSurface(cb_image)

	textures = make(map[string]^SDL.Texture)
	defer delete(textures)

	cb_texture = SDL.CreateTextureFromSurface(renderer, cb_image)
	if cb_texture == nil {
		panic("Couldn't create textures from surface")
	}
	defer SDL.DestroyTexture(cb_texture)
	textures["Chessboard"] = cb_texture

	format: u32
	access: i32
	w, h: i32
	// constructing pieces atlas
	{
		white_pieces_surf := SDL_ttf.RenderText_Blended(
			chess_font,
			" otjnwl",
			{150, 150, 150, 255},
		)
		if white_pieces_surf == nil {
			panic("Couldn't render from font")
		}
		defer SDL.FreeSurface(white_pieces_surf)
		white_pieces_atlas := SDL.CreateTextureFromSurface(renderer, white_pieces_surf)
		if white_pieces_atlas == nil {
			panic("Couldn't create texture from white pieces surface")
		}
		defer SDL.DestroyTexture(white_pieces_atlas)
		SDL.QueryTexture(white_pieces_atlas, &format, &access, &w, &h)

		black_pieces_surf := SDL_ttf.RenderText_Blended(chess_font, " otjnwl", {50, 50, 50, 255})
		if black_pieces_surf == nil {
			panic("Couldn't render from font")
		}
		defer SDL.FreeSurface(black_pieces_surf)
		black_pieces_atlas := SDL.CreateTextureFromSurface(renderer, black_pieces_surf)
		if black_pieces_atlas == nil {
			panic("Couldn't create texture from black pieces surface")
		}
		defer SDL.DestroyTexture(black_pieces_atlas)
		piece_atlas := SDL.CreateTexture(
			renderer,
			u32(SDL.PixelFormatEnum.ARGB8888),
			SDL.TextureAccess.TARGET,
			w,
			h * 2,
		)
		textures["PiecesAtlas"] = piece_atlas
		SDL.SetRenderTarget(renderer, piece_atlas)
		SDL.RenderClear(renderer)
		SDL.RenderCopy(renderer, black_pieces_atlas, nil, &{0, 0, w, h})
		// //shouldn't change anything, I assume that never even happens
		// SDL.QueryTexture(black_pieces_atlas, &format, &access, &w, &h)
		SDL.RenderCopy(
			renderer,
			white_pieces_atlas,
			nil,
			&{0, state.ui_ctx.piece_resolution, w, h},
		)
		// SDL.SetRenderTarget(renderer, nil)
	}
	cb_pieces_overlay_size: i32 = state.ui_ctx.chessboard_resolution
	pieces_overlay_tex := SDL.CreateTexture(
		renderer,
		format,
		SDL.TextureAccess.TARGET,
		cb_pieces_overlay_size,
		cb_pieces_overlay_size,
	)
	if pieces_overlay_tex == nil {
		panic("Couldn't create textures from surface")
	}
	SDL.QueryTexture(pieces_overlay_tex, &format, &access, &w, &h)
	assert(cb_pieces_overlay_size % state.ui_ctx.piece_resolution == 0)
	defer SDL.DestroyTexture(pieces_overlay_tex)

	hovering_chess_piece_tex := SDL.CreateTexture(
		renderer,
		format,
		SDL.TextureAccess(access),
		state.ui_ctx.piece_resolution,
		state.ui_ctx.piece_resolution,
	)
	assert(hovering_chess_piece_tex != nil)
	defer SDL.DestroyTexture(hovering_chess_piece_tex)
	textures["MouseLabel"] = hovering_chess_piece_tex
	SDL.SetTextureBlendMode(hovering_chess_piece_tex, SDL.BlendMode.BLEND)
	SDL.SetRenderTarget(renderer, hovering_chess_piece_tex)
	SDL.SetRenderDrawColor(renderer, 255, 255, 255, 255)

	// draw hovered piece
	render_piece(
		renderer,
		state.ui_ctx.held_piece,
		&{0, 0, state.ui_ctx.piece_resolution, state.ui_ctx.piece_resolution},
	)

	chessboard_highlights_tex := SDL.CreateTexture(
		renderer,
		format,
		SDL.TextureAccess(access),
		w,
		h,
	)
	textures["ChessboardHighlights"] = chessboard_highlights_tex
	defer SDL.DestroyTexture(chessboard_highlights_tex)
	SDL.SetTextureBlendMode(chessboard_highlights_tex, .BLEND)

	// load an empty default game view
	{
		game_view := PGN_View{}
		game := new(PGN_Parsed_Game)
		pgn_parsed_game_init(game)
		pgn_view_init(&game_view, game)
		state.loaded_game = game_view
	}

	ctx := &state.mu_ctx
	mu.init(ctx)

	ctx.text_width = mu.default_atlas_text_width
	ctx.text_height = mu.default_atlas_text_height

	last_tick: u32 = 0
	main_loop: for {
		for e: SDL.Event; SDL.PollEvent(&e); {
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

		// redrawing pieces
		cb := state.loaded_game.current_position
		SDL.SetTextureBlendMode(pieces_overlay_tex, SDL.BlendMode.BLEND)
		textures["Pieces"] = pieces_overlay_tex
		SDL.SetRenderTarget(renderer, pieces_overlay_tex)
		SDL.SetRenderDrawColor(renderer, 255, 255, 255, 0)
		SDL.RenderClear(renderer)
		render_chessboard_position(renderer, cb)
		SDL.SetRenderTarget(renderer, nil)

		// drawing chessboard highlights
		{
			mx, my: i32
			SDL.GetMouseState(&mx, &my)
			SDL.RenderCopy(
				renderer,
				textures["MouseLabel"],
				nil,
				&{mx, my, state.ui_ctx.piece_resolution, state.ui_ctx.piece_resolution},
			)

			chessboard_highlights_tex := textures["ChessboardHighlights"]
			SDL.SetRenderTarget(renderer, chessboard_highlights_tex)
			SDL.RenderClear(renderer)
			tile_size := state.ui_ctx.chessboard_resolution / 8
			SDL.SetRenderDrawColor(renderer, 0, 0, 0, 0)
			SDL.RenderClear(renderer)
			render_rect :: proc(renderer: ^SDL.Renderer, coords: Vec2i, tile_size: i32) {
				SDL.RenderFillRect(
					renderer,
					&{coords.x * tile_size, (7 - coords.y) * (tile_size), tile_size, tile_size},
				)
			}
			render_rect_hole :: proc(renderer: ^SDL.Renderer, coords: Vec2i, tile_size: i32) {
				SDL.RenderFillRect(
					renderer,
					&{
						coords.x * tile_size + 8,
						(7 - coords.y) * tile_size + 8,
						tile_size - 16,
						tile_size - 16,
					},
				)
			}

			// set mask for all plausible moves
			moves := make([dynamic]Chess_Move_Full, 0, 32)
			// basic_position := default_chessboard_info()
			coord := state.ui_ctx.hovered_square
			square := Square_Info_Full{}
			square.coord = {cast(u8)coord.x, cast(u8)coord.y}
			square.piece = state.loaded_game.current_position.square_info[coord.y * 8 + coord.x]
			get_unrestricted_moves_of_piece(square, &moves, &state.loaded_game.current_position)
			state.ui_ctx.chessboard_square_mask_green = {}
			for move in moves {
				state.ui_ctx.chessboard_square_mask_green[move.dst.y * 8 + move.dst.x] = true
			}

			// render green chessboard highlights from mask
			SDL.SetRenderDrawColor(renderer, 100, 200, 100, 255)
			for square_active, index in state.ui_ctx.chessboard_square_mask_green {
				if square_active {
					render_rect(renderer, Vec2i{i32(index % 8), i32(index / 8)}, tile_size)
				}
			}
			SDL.SetRenderDrawColor(renderer, 0, 0, 0, 0)
			for square_active, index in state.ui_ctx.chessboard_square_mask_green {
				if square_active {
					render_rect_hole(renderer, Vec2i{i32(index % 8), i32(index / 8)}, tile_size)
				}
			}
			SDL.SetRenderDrawColor(renderer, 200, 100, 100, 255)
			render_rect(renderer, state.ui_ctx.hovered_square, tile_size)
			SDL.SetRenderDrawColor(renderer, 0, 0, 0, 0)
			render_rect_hole(renderer, state.ui_ctx.hovered_square, tile_size)

			SDL.SetRenderTarget(renderer, nil)
		}

		mu.begin(ctx)
		all_windows(ctx)
		mu.end(ctx)
		render(ctx, renderer)

		for SDL.GetTicks() - last_tick < time_per_tick {
			SDL.Delay(1)
		}
		// last_tick = SDL.GetTicks()
		last_tick += time_per_tick
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
		case ^mu.Command_Image:
			chosen_texture := textures[cmd.texture_name]
			if chosen_texture == nil {
				panic("Couldn't find texture")
			}
			rect := transmute(SDL.Rect)cmd.rect
			format: u32
			access: i32
			w, h: i32
			SDL.QueryTexture(chosen_texture, &format, &access, &w, &h)
			destination_rect := SDL.Rect{rect.x, rect.y, w, h}
			SDL.RenderCopyEx(renderer, chosen_texture, nil, &rect, 0, nil, SDL.RendererFlip.NONE)
		case ^mu.Command_Jump:
			unreachable()
		}
	}
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

skip_characters_in_set_strings_variant :: proc(
	reader: ^bufio.Reader,
	skipped_strings: []string,
) -> (
	did_consume: bool = false,
) {
	get_longest_of_strings :: proc(strings: []string) -> (s: string) {
		s = strings[0]
		for val, _ in strings {
			if len(val) > len(s) {
				s = val
			}
		}
		return
	}
	s := get_longest_of_strings(skipped_strings)
	data, _ := bufio.reader_peek(reader, len(s))
	longest_candidate: string = ""
	for str, str_index in skipped_strings {
		if len(data) < len(str) {
			continue
		}
		slice := data[:len(str)]
		if transmute(string)slice == str && len(str) > len(longest_candidate) {
			longest_candidate = str
		}
	}
	reader_consume_n_bytes :: proc(reader: ^bufio.Reader, n: int) -> io.Error {
		for _ in 0 ..< n {
			_, err := bufio.reader_read_byte(reader)
			if err != .None {
				return err
			}
		}
		return .None
	}
	if len(longest_candidate) > 0 {
		reader_consume_n_bytes(reader, len(longest_candidate))
		skip_characters_in_set_strings_variant(reader, skipped_strings)
	}
	return
}
skip_character_in_set :: proc(
	reader: ^bufio.Reader,
	chars: [$T]u8,
) -> (
	did_consume: bool = false,
) {
	r, s, err := bufio.reader_read_rune(reader)
	if err != .None && err != .EOF {
		panic("Error happened!")
	}
	if s != 1 {
		panic("unexpected character")
	}
	c := u8(r)
	for seeked_char in chars {
		if seeked_char == c {
			did_consume = true
			return
		}
	}
	bufio.reader_unread_rune(reader)
	return
}
skip_characters_in_set :: proc(
	reader: ^bufio.Reader,
	chars: [$T]u8,
) -> (
	did_consume: bool = false,
) {
	for skip_character_in_set(reader, chars) {
		did_consume = true
	}
	return
}

nav_menu_open_file :: proc(
	filepath: string = "data/small.pgn",
) -> (
	games: ^[dynamic]PGN_Parsed_Game,
) {
	games_dynarray := make([dynamic]PGN_Parsed_Game, 0, 32)
	games = &games_dynarray
	splits := strings.split(filepath, ".")
	extension := splits[len(splits) - 1]
	if extension != "pgn" {
		write_log(fmt.tprint(args = {"Extension", extension, "not supported!"}))
		return
	}

	handle, err := os.open(filepath)
	if err != os.ERROR_NONE {
		write_log(fmt.tprint(args = {"Couldn't open:", filepath}, sep = " "))
		when ODIN_OS == .Windows {
			thing := win32.GetLastError()
			write_log(fmt.tprint("error code: ", thing))
		}
		return
	}
	assert(handle != os.INVALID_HANDLE)
	defer os.close(handle)
	stream := os.stream_from_handle(handle)
	raw_reader, ok_reader := io.to_reader(stream)
	if ok_reader == false {
		write_log(fmt.tprint("Couldn't stream file: ", filepath))
		return
	}
	reader: bufio.Reader
	bufio.reader_init(&reader, raw_reader, 1 << 16)
	defer bufio.reader_destroy(&reader)
	{
		_, s, err_BOM := bufio.reader_read_rune(&reader)
		if err_BOM != .None {
			write_log(fmt.tprint("Error reading the first rune of: ", filepath))
			return
		}
		if s == 1 {
			// no BOM in the file -> reverting to first character
			bufio.reader_unread_rune(&reader)
		} else {
			fmt.println("skipping BOM in PGN file, BOM has length of ", s)
		}
	}
	reader_loop: for {
		game, success := parse_full_game_from_pgn(&reader)
		if !success {
			break
		}
		thing, _ := bufio.reader_peek(&reader, 15)
		fmt.eprintln("I have loaded a game, next bytes:", transmute(string)thing)
		append(games, game)
		token, token_success := parse_pgn_token(&reader)
		_, conversion_ok := token.(Empty_Line)
		if token_success != .None || !conversion_ok {
			break
		}
	}
	write_log(fmt.aprintln("Games loaded:", len(games)))
	return
}

view_pgn_game :: proc(pgn_game: ^PGN_Parsed_Game){
	new_game := PGN_View{}
	pgn_view_init(&new_game, pgn_game)
	state.loaded_game = new_game
	write_log("Viewing a game.")
}

Chess_Result :: enum u8 {
	Undecided,
	White_Won,
	Black_Won,
	Draw,
}

Piece_Color :: enum u8 {
	Black = 0,
	White,
}
Piece_Type :: enum u8 {
	None,
	Pawn,
	Rook,
	Knight,
	Bishop,
	Queen,
	King,
}
PGN_Half_Move :: struct {
	piece_type:       Piece_Type,
	known_src_row:    bool,
	known_src_column: bool,
	src_x:            u8,
	src_y:            u8,
	is_mate:          bool,
	is_check:         bool,
	is_takes:		  bool,
	is_prequalified:  bool, // TODO: remove this
	is_kside_castles: bool,
	is_qside_castles: bool,
	dst:              Chessboard_location,
}

reconstruct_pgn_view_description :: proc(builder: ^strings.Builder) -> string{
	for mv, mv_index in state.loaded_game.moves{
		if mv_index == cast(int)state.loaded_game.current_move{
			break
		}
		if mv_index % 2 == 0{
			strings.write_int(builder, mv_index / 2 + 1)
			strings.write_byte(builder, '.')
			strings.write_byte(builder, ' ')
		}
		// strings.write_string(builder, "dragons")
		piece_type_char := ""
		switch mv.piece_type{
			case .Rook:
				piece_type_char = "R"
			case .Knight:
				piece_type_char = "N"
			case .Bishop:
				piece_type_char = "B"
			case .King:
				piece_type_char = "K"
			case .Queen:
				piece_type_char = "Q"
			case .Pawn:
			case .None:
				panic("unreachable")
		}
		strings.write_string(builder, piece_type_char)
		if mv.piece_type == .Pawn && mv.is_takes{
			strings.write_byte(builder, 'a' + mv.src_x)
		}
		if mv.is_prequalified{
			if mv.known_src_column{
				strings.write_byte(builder, 'a' + mv.src_x)
			}
			else if mv.known_src_row{
				strings.write_byte(builder, '1' + mv.src_y)
			}
			else{
				panic("unreachable")
			}
		}
		if mv.is_takes{
			strings.write_byte(builder, 'x')
		}
		strings.write_byte(builder, 'a' + mv.dst.x)
		strings.write_byte(builder, '1' + mv.dst.y)
		strings.write_byte(builder, ' ')
	}
	return transmute(string)builder.buf[:]
}

all_windows :: proc(ctx: ^mu.Context) {
	@(static)
	opts := mu.Options{.NO_CLOSE}
	opts_navbar := mu.Options{.NO_CLOSE, .NO_RESIZE, .NO_TITLE}


	if mu.window(
		ctx,
		"Menu Bar",
		{0, 0, state.sdl_wsize.x, MU_PROPERTIES.MENU_HEIGHT},
		opts_navbar,
	) {
		w := mu.get_current_container(ctx)
		w.rect.w = state.sdl_wsize.x
		mu.layout_row(ctx, []i32{80, 60, 60}, 0)

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
			if .SUBMIT in mu.button(ctx, "Import") {
				games := nav_menu_open_file()
				if len(games) > 0 {
					// DEBUG: load all games into a database first
					view_pgn_game(&games[0])
				}
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

	if (mu.window(
			   ctx,
			   "Status bar",
			   mu.Rect{
				   0,
				   state.sdl_wsize.y - MU_PROPERTIES.STATUS_BAR_HEIGHT,
				   8500,
				   MU_PROPERTIES.STATUS_BAR_HEIGHT,
			   },
			   opts_navbar,
		   )) {
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
	if mu.window(ctx, "Chessboard view", {650, 20, 300, 500}) {
		mu.layout_row(ctx, {30, 200, 30})
		mu.layout_height(ctx, 200)
		mu.layout_next(ctx)
		rect := mu.layout_next(ctx)
		mu.draw_image(ctx, "Chessboard", rect)
		mu.draw_image(ctx, "ChessboardHighlights", rect)
		mu.draw_image(ctx, "Pieces", rect)
		if mu.mouse_over(ctx, rect) {
			mu.text(ctx, "Test text")
			mx, my: i32
			SDL.GetMouseState(&mx, &my)
			x, y := mx - rect.x, my - rect.y
			tile_size := rect.w / 8
			tile_x, tile_y: i32 = x / tile_size, 7 - y / tile_size
			state.ui_ctx.hovered_square = Vec2i{tile_x, tile_y}
		} else {
			mu.layout_next(ctx)
		}
		mu.layout_row(ctx, {30, 30, 30, 30, 20, -1})
		mu.layout_height(ctx, 20)
		first_mv_btn := mu.button(ctx, "<<")
		prev_mv_btn := mu.button(ctx, "<")
		next_mv_btn := mu.button(ctx, ">")
		last_mv_btn := mu.button(ctx, ">>")
		comment_btn := mu.button(ctx, "{}")
		if .ACTIVE in first_mv_btn {
			mu.text(ctx, "First move")
		}
		if .SUBMIT in first_mv_btn {
			state.loaded_game.current_move = 0
			state.loaded_game.current_position = state.loaded_game.starting_position
		}
		if .ACTIVE in prev_mv_btn {
			mu.text(ctx, "Previous move")
		}
		if .SUBMIT in prev_mv_btn{
			move_num := state.loaded_game.current_move
			state.loaded_game.current_move = 0
			state.loaded_game.current_position = state.loaded_game.starting_position
			move_buf := make([dynamic]Chess_Move_Full, 0)
			defer delete(move_buf)
			for i :i32= 0; i < move_num - 1; i+=1 {
				advanced, err := pgn_view_next_move(&state.loaded_game, &move_buf)
				if !advanced{
					write_log("No more moves")
				}
			}
		}
		if .ACTIVE in next_mv_btn {
			mu.text(ctx, "Next move")
		}
		if .SUBMIT in next_mv_btn {
			move_buf := make([dynamic]Chess_Move_Full, 0)
			defer delete(move_buf)
			advanced, err := pgn_view_next_move(&state.loaded_game, &move_buf)
			if !advanced{
				write_log("No more moves")
			}

			builder := strings.Builder{}
			delete(state.ui_ctx.game_panel_contents)
			strings.builder_init(&builder, 0, 8192)
			state.ui_ctx.game_panel_contents = reconstruct_pgn_view_description(&builder)
		}
		if .ACTIVE in last_mv_btn {
			mu.text(ctx, "Last move")
		}
		if .SUBMIT in last_mv_btn{
			move_buf := make([dynamic]Chess_Move_Full, 0)
			defer delete(move_buf)
			for{
				advanced, err := pgn_view_next_move(&state.loaded_game, &move_buf)
				if !advanced{
					break
				}
			}
		}
		if .ACTIVE in comment_btn {
			mu.text(ctx, "Comment")
		}
		mu.layout_row(ctx, {-1}, -5)
		mu.begin_panel(ctx, "Moves")
		mu.layout_row(ctx, {-1}, -1)
		mu.text(ctx, state.ui_ctx.game_panel_contents)
		mu.end_panel(ctx)
	}
	if mu.window(ctx, "Open file", {200, 50, 400, 400}) {
		mu.layout_row(ctx, {-1}, -28)
		mu.begin_panel(ctx, "File listings")
		mu.end_panel(ctx)
		mu.layout_row(ctx, {-50, -1})
		mu.begin_panel(ctx, "File name")
		mu.end_panel(ctx)
		if .SUBMIT in mu.button(ctx, "Import") {
			games := nav_menu_open_file()
			if len(games) > 0 {
				view_pgn_game(&games[0])
			}
		}
	}
}
