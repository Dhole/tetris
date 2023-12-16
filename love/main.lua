BOARD_WIDTH = 10
BOARD_HEIGHT = 20
SQUARE_SIZE = 7
GAP_SIZE = 1
SCALE = 3
KEY_DELAY = 0.4
KEY_INTER = 0.03

REPEAT_NONE = 0
REPEAT_DELAY = 1
REPEAT_INTER = 2

GAME_PLAY = 0
GAME_OVER = 1
GAME_PAUSE = 2

tetro_i = {{0, -2}, {0, -1}, {0, 0}, {0, 1}}
tetro_l = {{0, -1}, {0, 0}, {0, 1}, {1, 1}}
tetro_j = {{0, -1}, {0, 0}, {0, 1}, {-1, 1}}
tetro_t = {{-1, 0}, {0, 0}, {0, 1}, {1, 0}}
tetro_o = {{-1, 0}, {0, 0}, {-1, 1}, {0, 1}}
tetro_s = {{0, 0}, {1, 0}, {-1, 1}, {0, 1}}
tetro_z = {{-1, 0}, {0, 0}, {0, 1}, {1, 1}}

TET_I = 1
TET_L = 2
TET_J = 3
TET_T = 4
TET_O = 5
TET_S = 6
TET_Z = 7

--              I L J T O S Z
tetro_probs = { 1,2,2,3,3,4,4 }
tetro_probs_acc = {}
tetro_probs_sum = 0

state = {}
ui = {}
function love.load()
	love.graphics.setFont(love.graphics.newFont(20))
	local width, height = love.graphics.getDimensions()
	local board = {}
	board.width = (GAP_SIZE + BOARD_WIDTH * (SQUARE_SIZE + GAP_SIZE)) * SCALE
	board.height = (GAP_SIZE + BOARD_HEIGHT * (SQUARE_SIZE + GAP_SIZE)) * SCALE
	board.x = width/2 - board.width/2
	board.y = height/2 - board.height/2
	ui.board = board

	board = {}
	board.cells = {}
	for x=0, BOARD_WIDTH-1 do
		local column = {}
		for y=0, BOARD_HEIGHT-1 do
			column[y] = 0
		end
		board.cells[x] = column
	end
	state.board = board

	local score = {}
	score.width = width / 5
	score.height = height / 9
	score.x = width/6 - score.width/2
	score.y = height/2 - score.height/2
	ui.score = score
	state.score = 0

	state.t = 0
	state.speed = 1
	state.cur_tetro = { kind = TET_L, x = BOARD_WIDTH/2 - 1, y = 2, rot = 0 }
	state.floor = false
	state.floor_wait_time = 0
	state.repeat_key_time = 0
	state.repeat_key_state = REPEAT_NONE
	state.remain_tick = 1/state.speed

	tetro_probs_sum = 0
	for i=1, 7 do
		local prob = tetro_probs[i]
		tetro_probs_sum = tetro_probs_sum + prob
	end
	tetro_probs_acc[1] = 0
	for i=1, 7 do
		local prob = tetro_probs[i]
		tetro_probs_acc[i+1] =  tetro_probs_acc[i] + tetro_probs[i] / tetro_probs_sum
	end

	local next = {}
	next.width = width / 6
	next.height = width / 6
	next.x = 5 * width/6 - next.width/2
	next.y = height/2 - next.height/2
	ui.next = next
	state.next_kind = rand_kind()

	state.game = GAME_PLAY
	state.keys = 0
	-- love.keyboard.setKeyRepeat(true)
end

function speed_by_score(score)
	if score < 20 then
		return 1
	elseif score < 40 then
		return 2
	elseif score < 60 then
		return 4
	elseif score < 80 then
		return 8
	elseif score < 100 then
		return 10
	else
		return 20
	end
end

function draw_square(board, x, y)
	local square_x = (GAP_SIZE + x * (SQUARE_SIZE + GAP_SIZE)) * SCALE
	local square_y = (GAP_SIZE + y * (SQUARE_SIZE + GAP_SIZE)) * SCALE
	love.graphics.rectangle("fill", board.x + square_x, board.y + square_y,
		SQUARE_SIZE * SCALE, SQUARE_SIZE * SCALE)
end

function draw_squares(board, x, y, dxys)
	for _, dxy in ipairs(dxys) do
		local dx, dy = dxy[1], dxy[2]
		draw_square(board, x + dx, y + dy)
	end
end

function draw_tetro(board, tetro)
	love.graphics.setColor(tetro_color(tetro.kind))
	draw_squares(board, tetro.x, tetro.y, tetro_dxys(tetro.kind, tetro.rot))
end

function draw_board()
	love.graphics.setColor(1, 1, 1)
	love.graphics.rectangle("line", ui.board.x, ui.board.y, ui.board.width, ui.board.height)
	for x=0, BOARD_WIDTH-1 do
		for y=0, BOARD_HEIGHT-1 do
			love.graphics.setColor(tetro_color(state.board.cells[x][y]))
			draw_square(ui.board, x, y)
		end
	end
end

COLLIDE_NO = 0
COLLIDE_FLOOR = 1
COLLIDE_BORDER = 2
function has_collision(x, y, dxys)
	for _, dxy in ipairs(dxys) do
		local dx, dy = dxy[1], dxy[2]
		x1, y1 = x + dx, y + dy
		if x1 < 0 or x1 >= BOARD_WIDTH then
			return COLLIDE_BORDER
		end
		if y1 < 0 then
			return COLLIDE_BORDER
		end
		if y1 >= BOARD_HEIGHT then
			return COLLIDE_FLOOR
		end
		if state.board.cells[x1][y1] ~= 0 then
			return COLLIDE_FLOOR
		end
	end
	return COLLIDE_NO
end

function has_collision_tetro(tetro, dx, dy, drot)
	return has_collision(tetro.x + dx, tetro.y + dy, tetro_dxys(tetro.kind, (tetro.rot + drot) % 4))
end

function rotate(dxys, rot)
	local cos, sin = 1, 0
	if rot == 1 then
		cos, sin = 0, 1
	elseif rot == 2 then
		cos, sin = -1, 0
	elseif rot == 3  then
		cos, sin = 0, -1
	end
	local res = {}
	for i, dxy in ipairs(dxys) do
		local dx, dy = dxy[1], dxy[2]
		res[i] = {dx * cos - dy * sin, dx * sin + dy * cos}
	end
	return res
end

function tetro_dxys(tetro, rot)
	local dxys = {}
	if tetro == TET_I then
		dxys = rotate(tetro_i, rot)
	elseif tetro == TET_L then
		dxys = rotate(tetro_l, rot)
	elseif tetro == TET_J then
		dxys = rotate(tetro_j, rot)
	elseif tetro == TET_T then
		dxys = rotate(tetro_t, rot)
	elseif tetro == TET_O then
		dxys = tetro_o
	elseif tetro == TET_S then
		dxys = rotate(tetro_s, rot)
	elseif tetro == TET_Z then
		dxys = rotate(tetro_z, rot)
	end
	return dxys
end

function tetro_color(tetro)
	if tetro == 0 then
		return 0/255, 0/255, 0/255
	elseif tetro == TET_I then
		return 201/255, 230/255, 241/255
	elseif tetro == TET_L then
		return 130/255, 199/255, 237/255
	elseif tetro == TET_J then
		return 141/255, 161/255, 232/255
	elseif tetro == TET_T then
		return 255/255, 196/255, 128/255
	elseif tetro == TET_O then
		return 247/255, 116/255, 183/255
	elseif tetro == TET_S then
		return 244/255, 168/255, 219/255
	elseif tetro == TET_Z then
		return 255/255, 202/255, 191/255
	end
	-- 255/255, 148/255, 128/255
end

KEY_LEFT = 1
KEY_RIGHT = 2
KEY_UP = 4
KEY_DOWN = 8
KEY_ROTL = 16
KEY_ROTR = 32
function love.keypressed(key)
	if key == 'right' then
		state.keys = bit.bor(state.keys, KEY_RIGHT)
	elseif key == 'left' then
		state.keys = bit.bor(state.keys, KEY_LEFT)
	elseif key == 'down' then
		state.keys = bit.bor(state.keys, KEY_DOWN)
	elseif key == 'up' then
		state.keys = bit.bor(state.keys, KEY_UP)
	elseif key == 'z' then
		state.keys = bit.bor(state.keys, KEY_ROTL)
	elseif key == 'x' then
		state.keys = bit.bor(state.keys, KEY_ROTR)
	end
end

function love.keyreleased(key)
	if key == 'right' then
		state.keys = bit.band(state.keys, bit.bnot(KEY_RIGHT))
	elseif key == 'left' then
		state.keys = bit.band(state.keys, bit.bnot(KEY_LEFT))
	elseif key == 'down' then
		state.keys = bit.band(state.keys, bit.bnot(KEY_DOWN))
	elseif key == 'up' then
		state.keys = bit.band(state.keys, bit.bnot(KEY_UP))
	elseif key == 'z' then
		state.keys = bit.band(state.keys, bit.bnot(KEY_ROTL))
	elseif key == 'x' then
		state.keys = bit.band(state.keys, bit.bnot(KEY_ROTR))
	end
end

function rand_kind()
	local kind = 0
	local rand = love.math.random()
	if rand < tetro_probs_acc[TET_I+1] then
		kind = TET_I
	elseif rand < tetro_probs_acc[TET_L+1] then
		kind = TET_L
	elseif rand < tetro_probs_acc[TET_J+1] then
		kind = TET_J
	elseif rand < tetro_probs_acc[TET_T+1] then
		kind = TET_T
	elseif rand < tetro_probs_acc[TET_O+1] then
		kind = TET_O
	elseif rand < tetro_probs_acc[TET_S+1] then
		kind = TET_S
	elseif rand < tetro_probs_acc[TET_Z+1] then
		kind = TET_Z
	end
	return kind
end

function settle_tetro(tetro)
	local x, y = tetro.x, tetro.y
	local dxys = tetro_dxys(tetro.kind, tetro.rot)
	for _, dxy in ipairs(dxys) do
		local dx, dy = dxy[1], dxy[2]
		state.board.cells[x + dx][y + dy] = tetro.kind
	end
end

function new_tetro()
	local kind = state.next_kind
	state.next_kind = rand_kind()
	return { kind = kind, x = BOARD_WIDTH/2 - 1, y = 2, rot = 0 }
end

points_by_cleared_count = {0,1,3,5,10}

function check_floor(tetro)
	local dxys = tetro_dxys(tetro.kind, tetro.rot)
	local x, y = tetro.x, tetro.y
	local min_y, max_y = BOARD_HEIGHT-1, 0
	for _, dxy in ipairs(dxys) do
		local dy = dxy[2]
		if y+dy < min_y then
			min_y = y+dy
		end
		if y+dy > max_y then
			max_y = y+dy
		end
	end
	-- print(min_y, max_y)
	local cells = state.board.cells
	local cleared_rows = {}
	for y = max_y, min_y, -1 do
		local cleared = true
		for x = 0, BOARD_WIDTH-1 do
			if cells[x][y] == 0 then
				cleared = false
				break
			end
		end
		if cleared then
			table.insert(cleared_rows, y)
		end
	end
	-- print(cleared_rows[1], cleared_rows[2], cleared_rows[3], cleared_rows[4])
	local cleared_count = 0
	for _, row in ipairs(cleared_rows) do
		for y = row+cleared_count, cleared_count, -1 do
			for x = 0, BOARD_WIDTH-1 do
				cells[x][y] = cells[x][y-1]
			end
		end
		cleared_count = cleared_count + 1
	end
	for y = 0, cleared_count-1 do
		for x = 0, BOARD_WIDTH-1 do
			cells[x][y] = 0
		end
	end
	return points_by_cleared_count[cleared_count+1]
end

function game_over()
	state.game = GAME_OVER
end

function love.update(dt)
	state.t = state.t + dt
	state.remain_tick = state.remain_tick - dt
	if state.game == GAME_OVER then
		if bit.band(state.keys, KEY_ROTL) ~= 0 then
			love.load()
		end
		return
	end
	local cur_tetro = state.cur_tetro
	-- local revert = false
	-- local new_tetro = {x = cur_tetro.x, y = cur_tetro.y, rot = cur_tetro.rot }
	local dx, dy, drot = 0, 0, 0
	if state.floor then
		state.floor_wait_time = state.floor_wait_time + dt
	end
	local key_dir_ok = false
	if state.repeat_key_state == REPEAT_DELAY then
		state.repeat_key_time = state.repeat_key_time + dt
		if state.repeat_key_time >= KEY_DELAY then
			key_dir_ok = true
		end
	elseif state.repeat_key_state == REPEAT_INTER then
		state.repeat_key_time = state.repeat_key_time + dt
		if state.repeat_key_time >= KEY_INTER then
			key_dir_ok = true
		end
	else
		key_dir_ok = true
	end
	if state.remain_tick <= 0 then
		state.remain_tick = state.remain_tick + 1/state.speed
		dy = dy + 1
		if has_collision_tetro(cur_tetro, dx, dy, drot) == COLLIDE_FLOOR then
			state.floor = true
			dy = dy - 1
		end
	end

	local key_dir = false
	if bit.band(state.keys, KEY_DOWN) ~= 0 then
		key_dir = true
		if key_dir_ok then
			dy = dy + 1
			if has_collision_tetro(cur_tetro, dx, dy, drot) == COLLIDE_FLOOR then
				state.floor = true
				dy = dy - 1
			end
		end
	elseif bit.band(state.keys, KEY_UP) ~= 0 then
		while (true) do
			dy = dy + 1
			if has_collision_tetro(cur_tetro, dx, dy, drot) > COLLIDE_NO then
				dy = dy - 1
				break
			end
		end
		state.floor = true
		state.floor_wait_time = 999
	end
	if bit.band(state.keys, KEY_RIGHT) ~= 0 then
		key_dir = true
		if key_dir_ok then
			dx = dx + 1
			if has_collision_tetro(cur_tetro, dx, dy, drot) > COLLIDE_NO then
				dx = dx - 1
			end
		end
	elseif bit.band(state.keys, KEY_LEFT) ~= 0 then
		key_dir = true
		if key_dir_ok then
			dx = dx - 1
			if has_collision_tetro(cur_tetro, dx, dy, drot) > COLLIDE_NO then
				dx = dx + 1
			end
		end
	end
	local key_rot = false
	if bit.band(state.keys, KEY_ROTR) ~= 0 then
		key_rot = true
		state.keys = bit.band(state.keys, bit.bnot(KEY_ROTR))
		drot = 1
	elseif bit.band(state.keys, KEY_ROTL) ~= 0 then
		key_rot = true
		state.keys = bit.band(state.keys, bit.bnot(KEY_ROTL))
		drot = -1
	end
	if key_rot and has_collision_tetro(cur_tetro, dx, dy, drot) > COLLIDE_NO then
		if state.floor then
			-- If already touched the floor and colliding with the floor,
			-- move up one block if that removes the collision
			dy = dy - 1
			if has_collision_tetro(cur_tetro, dx, dy, drot) == COLLIDE_NO then
			else
				dy = dy + 1
				drot = 0
			end
		else
			drot = 0
		end
	end
	-- If after a rotation the tetro is not touching the floor, make sure
	-- it does if we're already on the floor
	if state.floor then
		dy = dy + 1
		if has_collision_tetro(cur_tetro, dx, dy, drot) == COLLIDE_FLOOR then
			dy = dy - 1
		end
	end
	if key_dir then
		if state.repeat_key_state == REPEAT_NONE then
			state.repeat_key_state = REPEAT_DELAY
			state.repeat_key_time = 0
		elseif key_dir_ok then
			state.repeat_key_state = REPEAT_INTER
			state.repeat_key_time = 0
		end
	else
		state.repeat_key_time = 0
		state.repeat_key_state = REPEAT_NONE
	end
	-- If not updated tetro position
	if dx == 0 and dy == 0 and drot == 0 then
		-- After some time not moving and on the floor, settle the tetro
		if state.floor and state.floor_wait_time > 1/2 then
			-- print(state.floor_wait_time)
			state.floor = false
			settle_tetro(cur_tetro)
			score = check_floor(cur_tetro)
			state.cur_tetro = new_tetro(cur_tetro)
			state.keys = bit.band(state.keys, bit.bnot(KEY_UP))
			state.keys = bit.band(state.keys, bit.bnot(KEY_DOWN))
			state.keys = bit.band(state.keys, bit.bnot(KEY_LEFT))
			state.keys = bit.band(state.keys, bit.bnot(KEY_RIGHT))
			state.floor_wait_time = 0
			if has_collision_tetro(state.cur_tetro, 0, 0, 0) > COLLIDE_NO then
				game_over()
			else
				state.score = state.score + score
				state.speed = speed_by_score(state.score)
			end
		end
	else
		state.cur_tetro.x = state.cur_tetro.x + dx
		state.cur_tetro.y = state.cur_tetro.y + dy
		state.cur_tetro.rot = (state.cur_tetro.rot + drot) % 4
		-- Reset floor_wait_time if we've moved the tetro
		if state.floor then
			state.floor_wait_time = 0
		end
	end
end

function love.draw()
	local width, height = love.graphics.getDimensions()
	draw_board()
	draw_tetro(ui.board, state.cur_tetro)

	-- Score board
	local score = ui.score
	love.graphics.setColor(1, 1, 1)
	love.graphics.rectangle("line", score.x, score.y, score.width, score.height)
	love.graphics.print(state.score, score.x + 10, score.y + score.height/2 - 10)
	love.graphics.print("score", score.x + 50, score.y + score.height + 10)

	-- Next tetro
	local next = ui.next
	love.graphics.setColor(1, 1, 1)
	love.graphics.rectangle("line", next.x, next.y, next.width, next.height)
	draw_tetro({x = next.x + 55, y = next.y + 40}, {x = 0, y = 0, rot = 0, kind = state.next_kind})
	love.graphics.setColor(1, 1, 1)
	love.graphics.print("next", next.x + 40, next.y + next.height + 10)

	if state.game == GAME_OVER then
		love.graphics.setColor(0, 0, 0)
		love.graphics.rectangle("fill", width/2 - 90, height/2 - 60, 180, 120)
		love.graphics.setColor(1, 1, 1)
		love.graphics.rectangle("line", width/2 - 90, height/2 - 60, 180, 120)
		love.graphics.print("Game Over", width/2 - 60, height/2 - 50)
		love.graphics.print("Press Z to start", width/2 - 75, height/2)
		love.graphics.print("a new game", width/2 - 60, height/2 + 20)
	end
end
