-- ChronoClash: The Arena of Echoes - AO Game Logic
-- Implements 1v1 PvP card game with wagering, using AO process state
-- Modified to support JSON or human-readable responses based on filetype tag

-- Require JSON library for encoding responses
local json = require("json")

-- ANSI Color Codes (from word-wars.lua)
Colors = {
  gray = "\27[90m",
  blue = "\27[34m",
  green = "\27[32m",
  red = "\27[31m",
  reset = "\27[0m"
}

-- Game State (stored in AO process memory)
Matches = Matches or {}
Players = Players or {}
Leaderboard = Leaderboard or {}

-- Card Data (simplified, metadata IDs as placeholders)
Cards = {
  { Name = "Time Knight", CardID = "ar://timeknight", HP = 50, Attack = 10, SpecialAttack = 20, Type = "Chrono" },
  { Name = "Rift Sorcerer", CardID = "ar://riftsorcerer", HP = 40, Attack = 8, SpecialAttack = 15, Type = "Rift" },
  { Name = "Future Sage", CardID = "ar://futuresage", HP = 45, Attack = 7, SpecialAttack = 12, Type = "Future" },
  { Name = "Past Healer", CardID = "ar://pasthealer", HP = 60, Attack = 5, SpecialAttack = 10, Type = "Past" }
}

-- Utility: Format CLI Panel (for human-readable output)
function formatPanel(title, lines)
  local dashCount = math.max(20, #title + 10)
  local panel = Colors.gray .. string.rep("-", dashCount) .. "\n"
  panel = panel .. Colors.blue .. title .. Colors.gray .. "\n"
  for _, line in ipairs(lines) do
    panel = panel .. line .. "\n"
  end
  panel = panel .. string.rep("-", dashCount) .. Colors.reset
  return panel
end

-- Utility: Get Display Address
function getDisplayAddress(address)
  return address or "None"
end

-- Utility: Get Table Keys
function table.keys(tbl)
  local keys = {}
  for k in pairs(tbl) do keys[#keys + 1] = k end
  return keys
end

-- Utility: Generate Room Code
function generateRoomCode()
  local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  local code = ""
  for i = 1, 6 do
    local idx = math.random(1, #chars)
    code = code .. string.sub(chars, idx, idx)
  end
  return code
end

-- Utility: Generate Message ID
function generateMessageID()
  return tostring(os.time()) .. "-" .. math.random(1000, 9999)
end

-- Utility: Validate Card Play
function isValidCardPlay(match, player, card_idx, move_type)
  if match.State ~= "Active" then return false, "Match not active" end
  local player_key = match.Players.A == player and "A" or (match.Players.B == player and "B" or nil)
  if not player_key then return false, "Player not in match" end
  if match.Turn ~= player_key then return false, "Not your turn" end
  local card = match.Cards[player_key][card_idx]
  if not card or card.HP <= 0 then return false, "Invalid or defeated card" end
  if move_type == "Special" and card.PlayCount < 3 then return false, "Special attack not unlocked" end
  return true, ""
end

-- Utility: Find Match by RoomCode
function findMatchByRoomCode(room_code)
  for id, match in pairs(Matches) do
    if match.RoomCode == room_code and (match.State == "Pending" or match.State == "Active") then
      return id
    end
  end
  return nil
end

-- Handler: Join Game (Register Player)
Handlers.add("JoinGame", Handlers.utils.hasMatchingTag("Action", "JoinGame"), function(msg)
  local wallet_address = msg.Tags.Address
  local filetype = msg.Tags.filetype or "humantext"
  local process_id = msg.From
  local message_id = generateMessageID()

  print("JoinGame: From " .. process_id .. ", Address: " .. tostring(wallet_address) .. ", Filetype: " .. filetype .. ", MsgID: " .. message_id)

  if not wallet_address then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Wallet address required (Address=<wallet_address>)", message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Wallet address required (Address=<wallet_address>)" .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "JoinGameResponse", MessageID = message_id },
      Data = response
    })
    return
  end

  if Players[wallet_address] then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Wallet address already registered: " .. getDisplayAddress(wallet_address), message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Wallet address already registered: " .. getDisplayAddress(wallet_address) .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "JoinGameResponse", MessageID = message_id },
      Data = response
    })
    return
  end

  Players[wallet_address] = { ProcessID = process_id, Tokens = 10 }
  ao.send({
    Target = ao.env.Process.Id,
    Tags = { Action = "Player-Joined", MessageID = message_id },
    Data = Colors.gray .. "Player " .. Colors.blue .. getDisplayAddress(wallet_address) .. Colors.gray .. " joined ChronoClash" .. Colors.reset
  })

  local human_lines = {
    Colors.green .. "Welcome to ChronoClash!" .. Colors.reset,
    Colors.gray .. "Wallet Address: " .. Colors.blue .. getDisplayAddress(wallet_address) .. Colors.reset,
    Colors.gray .. "Tokens: " .. Colors.green .. Players[wallet_address].Tokens .. Colors.gray .. " (10 minted!)" .. Colors.reset,
    Colors.gray .. "Commands:" .. Colors.reset,
    Colors.gray .. "  CoordinateRoom (Address=<wallet_address>, WagerAmount=<number>)" .. Colors.reset,
    Colors.gray .. "  CoordinateRoom (Address=<wallet_address>, RoomCode=<code>)" .. Colors.reset,
    Colors.gray .. "  ProcessTurn (Address=<wallet_address>, MatchID=<id>|RoomCode=<code>, CardIdx=<1-4>, MoveType=Normal|Special, TargetIdx=<1-4>)" .. Colors.reset,
    Colors.gray .. "  GetLeaderboard, GetMatchState" .. Colors.reset
  }
  local json_data = {
    status = "success",
    message = "Welcome to ChronoClash!",
    wallet_address = getDisplayAddress(wallet_address),
    tokens = Players[wallet_address].Tokens,
    commands = {
      "CoordinateRoom (Address=<wallet_address>, WagerAmount=<number>)",
      "CoordinateRoom (Address=<wallet_address>, RoomCode=<code>)",
      "ProcessTurn (Address=<wallet_address>, MatchID=<id>|RoomCode=<code>, CardIdx=<1-4>, MoveType=Normal|Special, TargetIdx=<1-4>)",
      "GetLeaderboard, GetMatchState"
    },
    message_id = message_id
  }
  local response = filetype == "json" and json.encode(json_data) or formatPanel("Welcome", human_lines)
  ao.send({
    Target = process_id,
    Tags = { Action = "JoinGameResponse", MessageID = message_id },
    Data = response
  })
end)

-- Handler: Coordinate Room (Create/Join Match)
Handlers.add("CoordinateRoom", Handlers.utils.hasMatchingTag("Action", "CoordinateRoom"), function(msg)
  local wallet_address = msg.Tags.Address
  local wager_amount = tonumber(msg.Tags.WagerAmount)
  local room_code = msg.Tags.RoomCode
  local filetype = msg.Tags.filetype or "humantext"
  local process_id = msg.From
  local message_id = generateMessageID()

  print("CoordinateRoom: From " .. process_id .. ", Address: " .. tostring(wallet_address) .. ", RoomCode: " .. tostring(room_code) .. ", Wager: " .. tostring(wager_amount) .. ", Filetype: " .. filetype .. ", MsgID: " .. message_id)

  if not wallet_address or not Players[wallet_address] then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Invalid or missing wallet address", message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Invalid or missing wallet address" .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
      Data = response
    })
    return
  end

  if not room_code then
    -- Create Room
    if not wager_amount or wager_amount <= 0 then
      local response = filetype == "json" and
        json.encode({ status = "error", message = "Invalid wager amount", message_id = message_id }) or
        formatPanel("Error", { Colors.red .. "Invalid wager amount" .. Colors.reset })
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = response
      })
      return
    end

    if Players[wallet_address].Tokens < wager_amount then
      local response = filetype == "json" and
        json.encode({ status = "error", message = "Not enough tokens (need " .. wager_amount .. ")", message_id = message_id }) or
        formatPanel("Error", { Colors.red .. "Not enough tokens (need " .. wager_amount .. ")" .. Colors.reset })
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = response
      })
      return
    end

    local match_id = tostring(os.time()) .. "-" .. wallet_address
    local new_room_code = generateRoomCode()
    Players[wallet_address].Tokens = Players[wallet_address].Tokens - wager_amount
    Matches[match_id] = {
      Players = { A = wallet_address, B = nil },
      Wager = wager_amount,
      RoomCode = new_room_code,
      State = "Pending",
      Turn = "A",
      Cards = { A = {}, B = {} }
    }
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "RoomCreated", MessageID = message_id },
      Data = Colors.gray .. "Room created by " .. Colors.blue .. getDisplayAddress(wallet_address) .. Colors.gray .. ": " .. new_room_code .. Colors.reset
    })
    local human_lines = {
      Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
      Colors.gray .. "Room Code: " .. Colors.blue .. new_room_code .. Colors.reset,
      Colors.gray .. "Wager: " .. Colors.green .. wager_amount .. Colors.gray .. " tokens" .. Colors.reset,
      Colors.gray .. "Opponent: " .. Colors.blue .. "Waiting for opponent" .. Colors.reset,
      Colors.gray .. "Tokens Remaining: " .. Colors.green .. Players[wallet_address].Tokens .. Colors.reset
    }
    local json_data = {
      status = "success",
      message = "Room Created",
      match_id = match_id,
      room_code = new_room_code,
      wager = wager_amount,
      opponent = "Waiting for opponent",
      tokens_remaining = Players[wallet_address].Tokens,
      message_id = message_id
    }
    local response = filetype == "json" and json.encode(json_data) or formatPanel("Room Created", human_lines)
    ao.send({
      Target = process_id,
      Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
      Data = response
    })
  else
    -- Join Room
    local match_id = findMatchByRoomCode(room_code)
    if not match_id then
      local response = filetype == "json" and
        json.encode({ status = "error", message = "Invalid or expired room code", message_id = message_id }) or
        formatPanel("Error", { Colors.red .. "Invalid or expired room code" .. Colors.reset })
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = response
      })
      return
    end

    if Matches[match_id].Players.A == wallet_address then
      local response = filetype == "json" and
        json.encode({ status = "error", message = "Cannot join your own room (use a different wallet address)", message_id = message_id }) or
        formatPanel("Error", { Colors.red .. "Cannot join your own room (use a different wallet address)" .. Colors.reset })
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = response
      })
      return
    end

    if Matches[match_id].Players.B and Matches[match_id].Players.B == wallet_address then
      local response = filetype == "json" and
        json.encode({ status = "error", message = "You have already joined this room", message_id = message_id }) or
        formatPanel("Error", { Colors.red .. "You have already joined this room" .. Colors.reset })
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = response
      })
      return
    end

    if Players[wallet_address].Tokens < Matches[match_id].Wager then
      local response = filetype == "json" and
        json.encode({ status = "error", message = "Not enough tokens (need " .. Matches[match_id].Wager .. ")", message_id = message_id }) or
        formatPanel("Error", { Colors.red .. "Not enough tokens (need " .. Matches[match_id].Wager .. ")" .. Colors.reset })
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = response
      })
      return
    end

    Players[wallet_address].Tokens = Players[wallet_address].Tokens - Matches[match_id].Wager
    Matches[match_id].Players.B = wallet_address
    Matches[match_id].State = "Active"
    Matches[match_id].Wager = Matches[match_id].Wager * 2

    -- Assign Cards
    for i, card in ipairs(Cards) do
      Matches[match_id].Cards.A[i] = { HP = card.HP, PlayCount = 0 }
      Matches[match_id].Cards.B[i] = { HP = card.HP, PlayCount = 0 }
    end

    local card_names = {}
    for _, card in ipairs(Cards) do
      card_names[#card_names + 1] = card.Name
    end

    local human_lines = {
      Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
      Colors.gray .. "Opponent: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.A) .. Colors.reset,
      Colors.gray .. "Wager: " .. Colors.green .. Matches[match_id].Wager .. Colors.gray .. " tokens" .. Colors.reset,
      Colors.gray .. "Cards: " .. Colors.blue .. table.concat(card_names, ", ") .. Colors.reset,
      Colors.gray .. "Current Turn: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.A) .. Colors.gray .. " (Player A)" .. Colors.reset
    }
    local json_data = {
      status = "success",
      message = "Match Started",
      match_id = match_id,
      opponent = getDisplayAddress(Matches[match_id].Players.A),
      wager = Matches[match_id].Wager,
      cards = card_names,
      current_turn = getDisplayAddress(Matches[match_id].Players.A) .. " (Player A)",
      message_id = message_id
    }
    local response = filetype == "json" and json.encode(json_data) or formatPanel("Match Started", human_lines)
    ao.send({
      Target = process_id,
      Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
      Data = response
    })

    local opponent_lines = {
      Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
      Colors.gray .. "Opponent: " .. Colors.blue .. getDisplayAddress(wallet_address) .. Colors.reset,
      Colors.gray .. "Wager: " .. Colors.green .. Matches[match_id].Wager .. Colors.gray .. " tokens" .. Colors.reset,
      Colors.gray .. "Cards: " .. Colors.blue .. table.concat(card_names, ", ") .. Colors.reset,
      Colors.gray .. "Your Turn: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.A) .. Colors.gray .. " (Player A)" .. Colors.reset
    }
    local opponent_json = {
      status = "success",
      message = "Match Started",
      match_id = match_id,
      opponent = getDisplayAddress(wallet_address),
      wager = Matches[match_id].Wager,
      cards = card_names,
      current_turn = getDisplayAddress(Matches[match_id].Players.A) .. " (Player A)",
      message_id = message_id
    }
    local opponent_response = filetype == "json" and json.encode(opponent_json) or formatPanel("Match Started", opponent_lines)
    ao.send({
      Target = Players[Matches[match_id].Players.A].ProcessID,
      Tags = { Action = "MatchStarted", MessageID = message_id },
      Data = opponent_response
    })
  end
end)

-- Handler: Sync Match State
Handlers.add("SyncMatchState", Handlers.utils.hasMatchingTag("Action", "SyncMatchState"), function(msg)
  local match_id = msg.Tags.MatchID
  local wallet_address = msg.Tags.Address
  local move_data = msg.Tags.MoveData
  local filetype = msg.Tags.filetype or "humantext"
  local process_id = msg.From
  local message_id = generateMessageID()

  print("SyncMatchState: From " .. process_id .. ", MatchID: " .. tostring(match_id) .. ", Address: " .. tostring(wallet_address) .. ", Filetype: " .. filetype .. ", MsgID: " .. message_id)

  if not match_id or not Matches[match_id] then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Invalid match ID", message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Invalid match ID" .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "SyncMatchStateResponse", MessageID = message_id },
      Data = response
    })
    return
  end

  if not wallet_address or (Matches[match_id].Players.A ~= wallet_address and Matches[match_id].Players.B ~= wallet_address) then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Invalid or unauthorized wallet address", message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Invalid or unauthorized wallet address" .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "SyncMatchStateResponse", MessageID = message_id },
      Data = response
    })
    return
  end

  if move_data then
    local success, data = pcall(json.decode, move_data)
    if not success then
      local response = filetype == "json" and
        json.encode({ status = "error", message = "Invalid move data format", message_id = message_id }) or
        formatPanel("Error", { Colors.red .. "Invalid move data format" .. Colors.reset })
      ao.send({
        Target = process_id,
        Tags = { Action = "SyncMatchStateResponse", MessageID = message_id },
        Data = response
      })
      return
    end
    local player_key = Matches[match_id].Players.A == wallet_address and "A" or "B"
    local opponent_key = player_key == "A" and "B" or "A"
    if data.Damage and data.TargetIdx and Matches[match_id].Cards[opponent_key][data.TargetIdx] then
      Matches[match_id].Cards[opponent_key][data.TargetIdx].HP = math.max(0, Matches[match_id].Cards[opponent_key][data.TargetIdx].HP - data.Damage)
      Matches[match_id].Cards[player_key][data.CardIdx].PlayCount = Matches[match_id].Cards[player_key][data.CardIdx].PlayCount + 1
    end
  end

  local card_names = {}
  for _, card in ipairs(Cards) do
    card_names[#card_names + 1] = card.Name
  end

  local human_lines = {
    Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
    Colors.gray .. "Turn: " .. Colors.blue .. Matches[match_id].Turn .. Colors.reset,
    Colors.gray .. "Player A Cards: " .. Colors.blue .. table.concat(card_names, ", ") .. Colors.reset,
    Colors.gray .. "Player B Cards: " .. Colors.blue .. table.concat(card_names, ", ") .. Colors.reset
  }
  local json_data = {
    status = "success",
    message = "Match State",
    match_id = match_id,
    turn = Matches[match_id].Turn,
    player_a_cards = card_names,
    player_b_cards = card_names,
    message_id = message_id
  }
  local response = filetype == "json" and json.encode(json_data) or formatPanel("Match State", human_lines)
  ao.send({
    Target = process_id,
    Tags = { Action = "SyncMatchStateResponse", MessageID = message_id },
    Data = response
  })
end)

-- Handler: Process Turn
Handlers.add("ProcessTurn", Handlers.utils.hasMatchingTag("Action", "ProcessTurn"), function(msg)
  local match_id = msg.Tags.MatchID
  local room_code = msg.Tags.RoomCode
  local wallet_address = msg.Tags.Address
  local card_idx = tonumber(msg.Tags.CardIdx)
  local move_type = msg.Tags.MoveType
  local target_idx = tonumber(msg.Tags.TargetIdx)
  local filetype = msg.Tags.filetype or "humantext"
  local process_id = msg.From
  local message_id = generateMessageID()

  print("ProcessTurn: From " .. process_id .. ", MsgID: " .. message_id .. ", Address: " .. tostring(wallet_address) .. ", MatchID: " .. tostring(match_id) .. ", RoomCode: " .. tostring(room_code) .. ", CardIdx: " .. tostring(card_idx) .. ", MoveType: " .. tostring(move_type) .. ", TargetIdx: " .. tostring(target_idx) .. ", Filetype: " .. filetype)

  local function sendError(target, message)
    local response = filetype == "json" and
      json.encode({ status = "error", message = message, message_id = message_id }) or
      formatPanel("Error", { Colors.red .. message .. Colors.reset })
    ao.send({
      Target = target,
      Tags = { Action = "ProcessTurnResponse", MessageID = message_id },
      Data = response
    })
  end

  local function validateTurn()
    if room_code then
      match_id = findMatchByRoomCode(room_code)
      if not match_id then
        return false, "Invalid or expired room code"
      end
    end

    if not match_id or not Matches[match_id] then
      return false, "Invalid match ID"
    end

    if not wallet_address or (Matches[match_id].Players.A ~= wallet_address and Matches[match_id].Players.B ~= wallet_address) then
      return false, "Invalid or unauthorized wallet address"
    end

    if not Matches[match_id].Players.B then
      return false, "No opponent has joined the match"
    end

    if Matches[match_id].Players.A == Matches[match_id].Players.B then
      return false, "Invalid match: Player A and Player B cannot be the same address"
    end

    if not card_idx or card_idx < 1 or card_idx > #Cards then
      return false, "Invalid card index (must be 1-4)"
    end

    if not Cards[card_idx] then
      return false, "Card data not found"
    end

    if not target_idx or target_idx < 1 or target_idx > #Cards then
      return false, "Invalid target card index (must be 1-4)"
    end

    if not Cards[target_idx] then
      return false, "Target card data not found"
    end

    if not move_type or (move_type ~= "Normal" and move_type ~= "Special") then
      return false, "Invalid move type (must be Normal or Special)"
    end

    local is_valid, error_msg = isValidCardPlay(Matches[match_id], wallet_address, card_idx, move_type)
    if not is_valid then
      return false, error_msg
    end

    local player_key = Matches[match_id].Players.A == wallet_address and "A" or "B"
    local opponent_key = player_key == "A" and "B" or "A"
    if not Matches[match_id].Cards[player_key] or not Matches[match_id].Cards[opponent_key] then
      return false, "Card state not initialized"
    end

    if not Matches[match_id].Cards[opponent_key][target_idx] then
      return false, "Invalid target card"
    end

    return true, { player_key = player_key, opponent_key = opponent_key }
  end

  local function applyTurn(player_key, opponent_key)
    local damage = move_type == "Special" and Cards[card_idx].SpecialAttack or Cards[card_idx].Attack
    local target_hp = Matches[match_id].Cards[opponent_key][target_idx].HP
    Matches[match_id].Cards[opponent_key][target_idx].HP = math.max(0, target_hp - damage)
    Matches[match_id].Cards[player_key][card_idx].PlayCount = Matches[match_id].Cards[player_key][card_idx].PlayCount + 1
    Matches[match_id].Turn = opponent_key
    return damage
  end

  local function notifyPlayers(player_key, opponent_key, damage)
    local response_lines = {
      Colors.gray .. "Card: " .. Colors.blue .. Cards[card_idx].Name .. Colors.reset,
      Colors.gray .. "Move: " .. Colors.blue .. move_type .. Colors.reset,
      Colors.gray .. "Target: " .. Colors.blue .. Cards[target_idx].Name .. Colors.reset,
      Colors.gray .. "Damage: " .. Colors.green .. damage .. Colors.reset,
      Colors.gray .. "Next Turn: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players[opponent_key]) .. Colors.reset
    }
    local json_data = {
      status = "success",
      message = "Turn Processed",
      card = Cards[card_idx].Name,
      move = move_type,
      target = Cards[target_idx].Name,
      damage = damage,
      next_turn = getDisplayAddress(Matches[match_id].Players[opponent_key]),
      message_id = message_id
    }
    local response = filetype == "json" and json.encode(json_data) or formatPanel("Turn Processed", response_lines)
    ao.send({
      Target = process_id,
      Tags = { Action = "ProcessTurnResponse", MessageID = message_id },
      Data = response
    })

    local opponent_lines = {
      Colors.gray .. "Opponent played: " .. Colors.blue .. Cards[card_idx].Name .. Colors.gray .. " (" .. move_type .. ")" .. Colors.reset,
      Colors.gray .. "Target: " .. Colors.blue .. Cards[target_idx].Name .. Colors.reset,
      Colors.gray .. "Damage: " .. Colors.green .. damage .. Colors.reset,
      Colors.gray .. "Your Turn" .. Colors.reset
    }
    local opponent_json = {
      status = "success",
      message = "Your Turn",
      opponent_card = Cards[card_idx].Name,
      move_type = move_type,
      target = Cards[target_idx].Name,
      damage = damage,
      message_id = message_id
    }
    local opponent_response = filetype == "json" and json.encode(opponent_json) or formatPanel("Your Turn", opponent_lines)
    local opponent_process_id = Players[Matches[match_id].Players[opponent_key]].ProcessID
    ao.send({
      Target = opponent_process_id,
      Tags = { Action = "YourTurn", MessageID = message_id },
      Data = opponent_response
    })
  end

  local function checkDefeat(opponent_key)
    local opponent_cards = Matches[match_id].Cards[opponent_key]
    local defeated = true
    for _, card in pairs(opponent_cards) do
      if card.HP > 0 then defeated = false break end
    end
    if defeated then
      ao.send({
        Target = ao.env.Process.Id,
        Tags = { Action = "EndGame", MatchID = match_id, MessageID = message_id }
      })
    end
    return defeated
  end

  local success, result = pcall(function()
    local is_valid, validation_result = validateTurn()
    if not is_valid then
      sendError(process_id, validation_result)
      return false
    end

    local player_key = validation_result.player_key
    local opponent_key = validation_result.opponent_key
    local damage = applyTurn(player_key, opponent_key)
    notifyPlayers(player_key, opponent_key, damage)
    checkDefeat(opponent_key)
    return true
  end)

  if not success then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Internal error: " .. tostring(result), message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Internal error: " .. tostring(result) .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "ProcessTurnResponse", MessageID = message_id },
      Data = response
    })
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "ProcessTurnError", MessageID = message_id },
      Data = "ProcessTurn failed: " .. tostring(result)
    })
  end
end)

-- Handler: End Game
Handlers.add("EndGame", Handlers.utils.hasMatchingTag("Action", "EndGame"), function(msg)
  local match_id = msg.Tags.MatchID
  local filetype = msg.Tags.filetype or "humantext"
  local process_id = msg.From
  local message_id = generateMessageID()

  print("EndGame: From " .. process_id .. ", MatchID: " .. tostring(match_id) .. ", Filetype: " .. filetype .. ", MsgID: " .. message_id)

  if not match_id or not Matches[match_id] or Matches[match_id].State ~= "Active" then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Invalid or inactive match", message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Invalid or inactive match" .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "EndGameResponse", MessageID = message_id },
      Data = response
    })
    return
  end

  local winner = nil
  local a_defeated = true
  local b_defeated = true
  for _, card in pairs(Matches[match_id].Cards.A) do
    if card.HP > 0 then a_defeated = false break end
  end
  for _, card in pairs(Matches[match_id].Cards.B) do
    if card.HP > 0 then b_defeated = false break end
  end

  if a_defeated and b_defeated then
    Matches[match_id].State = "Ended"
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "DistributeWinnings", MatchID = match_id, WinnerID = "Draw", MessageID = message_id }
    })
  elseif a_defeated then
    winner = Matches[match_id].Players.B
    Matches[match_id].State = "Ended"
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "DistributeWinnings", MatchID = match_id, WinnerID = winner, MessageID = message_id }
    })
  elseif b_defeated then
    winner = Matches[match_id].Players.A
    Matches[match_id].State = "Ended"
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "DistributeWinnings", MatchID = match_id, WinnerID = winner, MessageID = message_id }
    })
  end

  if winner then
    Leaderboard[winner] = (Leaderboard[winner] or 0) + 1
    local human_lines = {
      Colors.gray .. "Winner: " .. Colors.blue .. getDisplayAddress(winner) .. Colors.reset
    }
    local json_data = {
      status = "success",
      message = "Match Ended",
      winner = getDisplayAddress(winner),
      message_id = message_id
    }
    local response = filetype == "json" and json.encode(json_data) or formatPanel("Match Ended", human_lines)
    ao.send({
      Target = Players[Matches[match_id].Players.A].ProcessID,
      Tags = { Action = "MatchEnded", MessageID = message_id },
      Data = response
    })
    ao.send({
      Target = Players[Matches[match_id].Players.B].ProcessID,
      Tags = { Action = "MatchEnded", MessageID = message_id },
      Data = response
    })
  end
end)

-- Handler: Distribute Winnings
Handlers.add("DistributeWinnings", Handlers.utils.hasMatchingTag("Action", "DistributeWinnings"), function(msg)
  local match_id = msg.Tags.MatchID
  local winner_id = msg.Tags.WinnerID
  local filetype = msg.Tags.filetype or "humantext"
  local process_id = msg.From
  local message_id = generateMessageID()

  print("DistributeWinnings: From " .. process_id .. ", MatchID: " .. tostring(match_id) .. ", WinnerID: " .. tostring(winner_id) .. ", Filetype: " .. filetype .. ", MsgID: " .. message_id)

  if not match_id or not Matches[match_id] or Matches[match_id].State ~= "Ended" then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Invalid or not ended match", message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Invalid or not ended match" .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "DistributeWinningsResponse", MessageID = message_id },
      Data = response
    })
    return
  end

  local token_process = "TOKEN_PROCESS_ID"
  if winner_id == "Draw" then
    local refund = Matches[match_id].Wager / 2
    Players[Matches[match_id].Players.A].Tokens = Players[Matches[match_id].Players.A].Tokens + refund
    Players[Matches[match_id].Players.B].Tokens = Players[Matches[match_id].Players.B].Tokens + refund
    local human_lines = {
      Colors.gray .. "Refunded: " .. Colors.green .. refund .. Colors.gray .. " tokens" .. Colors.reset,
      Colors.gray .. "New Balance: " .. Colors.green .. Players[Matches[match_id].Players.A].Tokens .. Colors.reset
    }
    local json_data = {
      status = "success",
      message = "Draw",
      refunded = refund,
      new_balance = Players[Matches[match_id].Players.A].Tokens,
      message_id = message_id
    }
    local response = filetype == "json" and json.encode(json_data) or formatPanel("Draw", human_lines)
    ao.send({
      Target = Players[Matches[match_id].Players.A].ProcessID,
      Tags = { Action = "WinningsDistributed", MessageID = message_id },
      Data = response
    })
    ao.send({
      Target = Players[Matches[match_id].Players.B].ProcessID,
      Tags = { Action = "WinningsDistributed", MessageID = message_id },
      Data = response
    })
  else
    Players[winner_id].Tokens = Players[winner_id].Tokens + Matches[match_id].Wager
    local winner_lines = {
      Colors.gray .. "Won: " .. Colors.green .. Matches[match_id].Wager .. Colors.gray .. " tokens" .. Colors.reset,
      Colors.gray .. "New Balance: " .. Colors.green .. Players[winner_id].Tokens .. Colors.reset
    }
    local winner_json = {
      status = "success",
      message = "Victory",
      won = Matches[match_id].Wager,
      new_balance = Players[winner_id].Tokens,
      message_id = message_id
    }
    local winner_response = filetype == "json" and json.encode(winner_json) or formatPanel("Victory", winner_lines)
    ao.send({
      Target = Players[winner_id].ProcessID,
      Tags = { Action = "WinningsDistributed", MessageID = message_id },
      Data = winner_response
    })

    local loser_id = Matches[match_id].Players.A == winner_id and Matches[match_id].Players.B or Matches[match_id].Players.A
    local loser_lines = {
      Colors.gray .. "Winner: " .. Colors.blue .. getDisplayAddress(winner_id) .. Colors.reset
    }
    local loser_json = {
      status = "success",
      message = "Defeat",
      winner = getDisplayAddress(winner_id),
      message_id = message_id
    }
    local loser_response = filetype == "json" and json.encode(loser_json) or formatPanel("Defeat", loser_lines)
    ao.send({
      Target = Players[loser_id].ProcessID,
      Tags = { Action = "WinningsDistributed", MessageID = message_id },
      Data = loser_response
    })
    ao.send({
      Target = token_process,
      Tags = { Action = "Transfer", From = ao.env.Process.Id, To = winner_id, Amount = tostring(Matches[match_id].Wager), MessageID = message_id }
    })
  end

  ao.send({
    Target = "IRYS_PROCESS_ID",
    Tags = { Action = "StoreMatch", MatchID = match_id, WinnerID = winner_id or "Draw", Wager = tostring(Matches[match_id].Wager), MessageID = message_id },
    Data = Colors.gray .. "Match " .. match_id .. " ended: " .. (winner_id and getDisplayAddress(winner_id) or "Draw") .. Colors.reset
  })

  Matches[match_id] = nil
end)

-- Handler: Get Match State
Handlers.add("GetMatchState", Handlers.utils.hasMatchingTag("Action", "GetMatchState"), function(msg)
  local match_id = msg.Tags.MatchID
  local room_code = msg.Tags.RoomCode
  local filetype = msg.Tags.filetype or "humantext"
  local process_id = msg.From
  local message_id = generateMessageID()

  print("GetMatchState: From " .. process_id .. ", MatchID: " .. tostring(match_id) .. ", RoomCode: " .. tostring(room_code) .. ", Filetype: " .. filetype .. ", MsgID: " .. message_id)

  if room_code then
    match_id = findMatchByRoomCode(room_code)
  end

  if not match_id or not Matches[match_id] then
    local response = filetype == "json" and
      json.encode({ status = "error", message = "Invalid match ID or room code", message_id = message_id }) or
      formatPanel("Error", { Colors.red .. "Invalid match ID or room code" .. Colors.reset })
    ao.send({
      Target = process_id,
      Tags = { Action = "MatchStateResponse", MessageID = message_id },
      Data = response
    })
    return
  end

  local human_lines = {
    Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
    Colors.gray .. "Room Code: " .. Colors.blue .. Matches[match_id].RoomCode .. Colors.reset,
    Colors.gray .. "State: " .. Colors.blue .. Matches[match_id].State .. Colors.reset,
    Colors.gray .. "Wager: " .. Colors.green .. Matches[match_id].Wager .. Colors.gray .. " tokens" .. Colors.reset,
    Colors.gray .. "Turn: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players[Matches[match_id].Turn]) .. Colors.reset,
    Colors.gray .. "Player A: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.A) .. Colors.reset,
    Colors.gray .. "Player B: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.B) .. Colors.reset
  }
  local json_data = {
    status = "success",
    message = "Match State",
    match_id = match_id,
    room_code = Matches[match_id].RoomCode,
    state = Matches[match_id].State,
    wager = Matches[match_id].Wager,
    turn = getDisplayAddress(Matches[match_id].Players[Matches[match_id].Turn]),
    player_a = getDisplayAddress(Matches[match_id].Players.A),
    player_b = getDisplayAddress(Matches[match_id].Players.B),
    cards = {}
  }
  for player_key, cards in pairs(Matches[match_id].Cards) do
    local player_address = Matches[match_id].Players[player_key]
    local card_lines = {}
    local card_data = {}
    for i, card in ipairs(cards) do
      card_lines[#card_lines + 1] = Colors.gray .. Cards[i].Name .. ": " .. Colors.green .. card.HP .. Colors.gray .. " HP, " .. card.PlayCount .. "/3 plays" .. Colors.reset
      card_data[#card_data + 1] = { name = Cards[i].Name, hp = card.HP, play_count = card.PlayCount }
    end
    human_lines[#human_lines + 1] = Colors.gray .. "Player " .. player_key .. " (" .. Colors.blue .. getDisplayAddress(player_address) .. Colors.gray .. "):" .. Colors.reset
    for _, line in ipairs(card_lines) do human_lines[#human_lines + 1] = line end
    json_data.cards[player_key] = { address = getDisplayAddress(player_address), cards = card_data }
  end

  local response = filetype == "json" and json.encode(json_data) or formatPanel("Match State", human_lines)
  ao.send({
    Target = process_id,
    Tags = { Action = "MatchStateResponse", MessageID = message_id },
    Data = response
  })
end)

-- Handler: Get Leaderboard
Handlers.add("GetLeaderboard", Handlers.utils.hasMatchingTag("Action", "GetLeaderboard"), function(msg)
  local filetype = msg.Tags.filetype or "humantext"
  local process_id = msg.From
  local message_id = generateMessageID()

  print("GetLeaderboard: From " .. process_id .. ", Filetype: " .. filetype .. ", MsgID: " .. message_id)

  local sorted = {}
  for addr, wins in pairs(Leaderboard) do
    sorted[#sorted + 1] = { address = addr, wins = wins, tokens = Players[addr] and Players[addr].Tokens or 0 }
  end
  table.sort(sorted, function(a, b) return a.wins > b.wins end)
  local human_lines = {}
  local json_leaderboard = {}
  for i = 1, math.min(5, #sorted) do
    local address = getDisplayAddress(sorted[i].address)
    human_lines[#human_lines + 1] = Colors.gray .. i .. ". " .. Colors.blue .. address .. Colors.gray .. ": " .. Colors.green .. sorted[i].wins .. Colors.gray .. " wins, " .. Colors.green .. sorted[i].tokens .. Colors.gray .. " tokens" .. Colors.reset
    json_leaderboard[#json_leaderboard + 1] = {
      rank = i,
      address = address,
      wins = sorted[i].wins,
      tokens = sorted[i].tokens
    }
  end
  local response = filetype == "json" and
    json.encode({ status = "success", message = "Leaderboard", leaderboard = json_leaderboard, message_id = message_id }) or
    formatPanel("Leaderboard", human_lines)
  ao.send({
    Target = process_id,
    Tags = { Action = "LeaderboardResponse", MessageID = message_id },
    Data = response
  })
end)

-- Notes:
-- Modified to support JSON or human-readable responses via filetype="json" or filetype="humantext".
-- Match state stored in AO memory, outcomes logged to Arweave via IRYS_PROCESS_ID.
-- Replace TOKEN_PROCESS_ID with actual $U token process ID.
-- Use AR.IO caching for ProcessTurn and SyncMatchState handlers.
-- Test with LuaUnit for at least 10 matches.
-- End of file