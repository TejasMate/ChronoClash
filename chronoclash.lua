-- ChronoClash: The Arena of Echoes - AO Game Logic
-- Implements 1v1 PvP card game with wagering, using AO process state

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

-- Utility: Format CLI Panel (from word-wars.lua)
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

-- Utility: Get Display Address (from word-wars.lua)
function getDisplayAddress(address)
  return address or "None"
end

-- Utility: Get Table Keys (from word-wars.lua)
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
  local process_id = msg.From
  local message_id = generateMessageID()

  print("JoinGame: From " .. process_id .. ", Address: " .. tostring(wallet_address) .. ", MsgID: " .. message_id)
  if not wallet_address then
    print("JoinGame: Missing wallet address, MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "JoinGameResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Wallet address required (Address=<wallet_address>)" .. Colors.reset })
    })
    return
  end

  if Players[wallet_address] then
    print("JoinGame: Address already registered: " .. wallet_address .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "JoinGameResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Wallet address already registered: " .. getDisplayAddress(wallet_address) .. Colors.reset })
    })
    return
  end

  Players[wallet_address] = { ProcessID = process_id, Tokens = 10 }
  print("JoinGame: Player joined: " .. wallet_address .. ", MsgID: " .. message_id)
  ao.send({
    Target = ao.env.Process.Id,
    Tags = { Action = "Player-Joined", MessageID = message_id },
    Data = Colors.gray .. "Player " .. Colors.blue .. getDisplayAddress(wallet_address) .. Colors.gray .. " joined ChronoClash" .. Colors.reset
  })

  local lines = {
    Colors.green .. "Welcome to ChronoClash!" .. Colors.reset,
    Colors.gray .. "Wallet Address: " .. Colors.blue .. getDisplayAddress(wallet_address) .. Colors.reset,
    Colors.gray .. "Tokens: " .. Colors.green .. Players[wallet_address].Tokens .. Colors.gray .. " (10 minted!)" .. Colors.reset,
    Colors.gray .. "Commands:" .. Colors.reset,
    Colors.gray .. "  CoordinateRoom (Address=<wallet_address>, WagerAmount=<number>)" .. Colors.reset,
    Colors.gray .. "  CoordinateRoom (Address=<wallet_address>, RoomCode=<code>)" .. Colors.reset,
    Colors.gray .. "  ProcessTurn (Address=<wallet_address>, MatchID=<id>|RoomCode=<code>, CardIdx=<1-4>, MoveType=Normal|Special, TargetIdx=<1-4>)" .. Colors.reset,
    Colors.gray .. "  GetLeaderboard, GetMatchState" .. Colors.reset
  }
  print("JoinGame: Sending response to " .. process_id .. ", MsgID: " .. message_id)
  ao.send({
    Target = process_id,
    Tags = { Action = "JoinGameResponse", MessageID = message_id },
    Data = formatPanel("Welcome", lines)
  })
end)

-- Handler: Coordinate Room (Create/Join Match)
Handlers.add("CoordinateRoom", Handlers.utils.hasMatchingTag("Action", "CoordinateRoom"), function(msg)
  local wallet_address = msg.Tags.Address
  local wager_amount = tonumber(msg.Tags.WagerAmount)
  local room_code = msg.Tags.RoomCode
  local process_id = msg.From
  local message_id = generateMessageID()

  print("CoordinateRoom: From " .. process_id .. ", Address: " .. tostring(wallet_address) .. ", RoomCode: " .. tostring(room_code) .. ", Wager: " .. tostring(wager_amount) .. ", MsgID: " .. message_id)
  if not wallet_address or not Players[wallet_address] then
    print("CoordinateRoom: Invalid wallet address: " .. tostring(wallet_address) .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Invalid or missing wallet address" .. Colors.reset })
    })
    return
  end

  if not room_code then
    -- Create Room
    if not wager_amount or wager_amount <= 0 then
      print("CoordinateRoom: Invalid wager amount: " .. tostring(wager_amount) .. ", MsgID: " .. message_id)
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = formatPanel("Error", { Colors.red .. "Invalid wager amount" .. Colors.reset })
      })
      return
    end

    if Players[wallet_address].Tokens < wager_amount then
      print("CoordinateRoom: Insufficient tokens for " .. wallet_address .. ": " .. Players[wallet_address].Tokens .. ", MsgID: " .. message_id)
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = formatPanel("Error", { Colors.red .. "Not enough tokens (need " .. wager_amount .. ")" .. Colors.reset })
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
    print("CoordinateRoom: Room created: " .. match_id .. ", Code: " .. new_room_code .. ", MsgID: " .. message_id)
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "RoomCreated", MessageID = message_id },
      Data = Colors.gray .. "Room created by " .. Colors.blue .. getDisplayAddress(wallet_address) .. Colors.gray .. ": " .. new_room_code .. Colors.reset
    })
    print("CoordinateRoom: Sending response to " .. process_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
      Data = formatPanel("Room Created", {
        Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
        Colors.gray .. "Room Code: " .. Colors.blue .. new_room_code .. Colors.reset,
        Colors.gray .. "Wager: " .. Colors.green .. wager_amount .. Colors.gray .. " tokens" .. Colors.reset,
        Colors.gray .. "Opponent: " .. Colors.blue .. "Waiting for opponent" .. Colors.reset,
        Colors.gray .. "Tokens Remaining: " .. Colors.green .. Players[wallet_address].Tokens .. Colors.reset
      })
    })
  else
    -- Join Room
    local match_id = findMatchByRoomCode(room_code)
    if not match_id then
      print("CoordinateRoom: Invalid room code: " .. room_code .. ", MsgID: " .. message_id)
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = formatPanel("Error", { Colors.red .. "Invalid or expired room code" .. Colors.reset })
      })
      return
    end

    if Matches[match_id].Players.A == wallet_address then
      print("CoordinateRoom: Cannot join own room: " .. wallet_address .. ", MatchID: " .. match_id .. ", MsgID: " .. message_id)
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = formatPanel("Error", { Colors.red .. "Cannot join your own room (use a different wallet address)" .. Colors.reset })
      })
      return
    end

    if Matches[match_id].Players.B and Matches[match_id].Players.B == wallet_address then
      print("CoordinateRoom: Already joined room: " .. wallet_address .. ", MatchID: " .. match_id .. ", MsgID: " .. message_id)
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = formatPanel("Error", { Colors.red .. "You have already joined this room" .. Colors.reset })
      })
      return
    end

    if Players[wallet_address].Tokens < Matches[match_id].Wager then
      print("CoordinateRoom: Insufficient tokens for " .. wallet_address .. ": " .. Players[wallet_address].Tokens .. ", MsgID: " .. message_id)
      ao.send({
        Target = process_id,
        Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
        Data = formatPanel("Error", { Colors.red .. "Not enough tokens (need " .. Matches[match_id].Wager .. ")" .. Colors.reset })
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

    local lines = {
      Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
      Colors.gray .. "Opponent: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.A) .. Colors.reset,
      Colors.gray .. "Wager: " .. Colors.green .. Matches[match_id].Wager .. Colors.gray .. " tokens" .. Colors.reset,
      Colors.gray .. "Cards: " .. Colors.blue .. table.concat(card_names, ", ") .. Colors.reset,
      Colors.gray .. "Current Turn: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.A) .. Colors.gray .. " (Player A)" .. Colors.reset
    }
    print("CoordinateRoom: Match started: " .. match_id .. ", Player B: " .. wallet_address .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "CoordinateRoomResponse", MessageID = message_id },
      Data = formatPanel("Match Started", lines)
    })
    print("CoordinateRoom: Notifying Player A: " .. Matches[match_id].Players.A .. ", ProcessID: " .. Players[Matches[match_id].Players.A].ProcessID .. ", MsgID: " .. message_id)
    ao.send({
      Target = Players[Matches[match_id].Players.A].ProcessID,
      Tags = { Action = "MatchStarted", MessageID = message_id },
      Data = formatPanel("Match Started", {
        Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
        Colors.gray .. "Opponent: " .. Colors.blue .. getDisplayAddress(wallet_address) .. Colors.reset,
        Colors.gray .. "Wager: " .. Colors.green .. Matches[match_id].Wager .. Colors.gray .. " tokens" .. Colors.reset,
        Colors.gray .. "Cards: " .. Colors.blue .. table.concat(card_names, ", ") .. Colors.reset,
        Colors.gray .. "Your Turn: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.A) .. Colors.gray .. " (Player A)" .. Colors.reset
      })
    })
  end
end)

-- Handler: Sync Match State
Handlers.add("SyncMatchState", Handlers.utils.hasMatchingTag("Action", "SyncMatchState"), function(msg)
  local match_id = msg.Tags.MatchID
  local wallet_address = msg.Tags.Address
  local move_data = msg.Tags.MoveData
  local process_id = msg.From
  local message_id = generateMessageID()

  print("SyncMatchState: From " .. process_id .. ", MatchID: " .. tostring(match_id) .. ", Address: " .. tostring(wallet_address) .. ", MsgID: " .. message_id)
  if not match_id or not Matches[match_id] then
    print("SyncMatchState: Invalid match ID: " .. tostring(match_id) .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "SyncMatchStateResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Invalid match ID" .. Colors.reset })
    })
    return
  end

  if not wallet_address or (Matches[match_id].Players.A ~= wallet_address and Matches[match_id].Players.B ~= wallet_address) then
    print("SyncMatchState: Invalid address: " .. tostring(wallet_address) .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "SyncMatchStateResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Invalid or unauthorized wallet address" .. Colors.reset })
    })
    return
  end

  if move_data then
    local success, data = pcall(json.decode, move_data)
    if not success then
      print("SyncMatchState: Invalid move data: " .. tostring(move_data) .. ", MsgID: " .. message_id)
      ao.send({
        Target = process_id,
        Tags = { Action = "SyncMatchStateResponse", MessageID = message_id },
        Data = formatPanel("Error", { Colors.red .. "Invalid move data format" .. Colors.reset })
      })
      return
    end
    local player_key = Matches[match_id].Players.A == wallet_address and "A" or "B"
    local opponent_key = player_key == "A" and "B" or "A"
    if data.Damage and data.TargetIdx and Matches[match_id].Cards[opponent_key][data.TargetIdx] then
      Matches[match_id].Cards[opponent_key][data.TargetIdx].HP = math.max(0, Matches[match_id].Cards[opponent_key][data.TargetIdx].HP - data.Damage)
      Matches[match_id].Cards[player_key][data.CardIdx].PlayCount = Matches[match_id].Cards[player_key][data.CardIdx].PlayCount + 1
      print("SyncMatchState: Updated state for match: " .. match_id .. ", MsgID: " .. message_id)
    end
  end

  local card_names = {}
  for _, card in ipairs(Cards) do
    card_names[#card_names + 1] = card.Name
  end

  print("SyncMatchState: Sending response to " .. process_id .. ", MsgID: " .. message_id)
  ao.send({
    Target = process_id,
    Tags = { Action = "SyncMatchStateResponse", MessageID = message_id },
    Data = formatPanel("Match State", {
      Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
      Colors.gray .. "Turn: " .. Colors.blue .. Matches[match_id].Turn .. Colors.reset,
      Colors.gray .. "Player A Cards: " .. Colors.blue .. table.concat(card_names, ", ") .. Colors.reset,
      Colors.gray .. "Player B Cards: " .. Colors.blue .. table.concat(card_names, ", ") .. Colors.reset
    })
  })
end)

-- Handler: Process Turn (Fixed applyTurn)
Handlers.add("ProcessTurn", Handlers.utils.hasMatchingTag("Action", "ProcessTurn"), function(msg)
  local match_id = msg.Tags.MatchID
  local room_code = msg.Tags.RoomCode
  local wallet_address = msg.Tags.Address
  local card_idx = tonumber(msg.Tags.CardIdx)
  local move_type = msg.Tags.MoveType
  local target_idx = tonumber(msg.Tags.TargetIdx)
  local process_id = msg.From
  local message_id = generateMessageID()

  print("ProcessTurn: From " .. process_id .. ", MsgID: " .. message_id .. ", Address: " .. tostring(wallet_address) .. ", MatchID: " .. tostring(match_id) .. ", RoomCode: " .. tostring(room_code) .. ", CardIdx: " .. tostring(card_idx) .. ", MoveType: " .. tostring(move_type) .. ", TargetIdx: " .. tostring(target_idx))

  local function sendError(target, message)
    print("ProcessTurn: Error: " .. message .. ", Sending to " .. target .. ", MsgID: " .. message_id)
    ao.send({
      Target = target,
      Tags = { Action = "ProcessTurnResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. message .. Colors.reset })
    })
  end

  local function validateTurn()
    print("ProcessTurn: Validating turn, MsgID: " .. message_id)
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

    print("ProcessTurn: Turn validated, PlayerKey: " .. player_key .. ", Match.Turn: " .. Matches[match_id].Turn .. ", MsgID: " .. message_id)
    return true, { player_key = player_key, opponent_key = opponent_key }
  end

  local function applyTurn(player_key, opponent_key)
    print("ProcessTurn: Applying turn, Current Turn: " .. Matches[match_id].Turn .. ", MsgID: " .. message_id)
    local damage = move_type == "Special" and Cards[card_idx].SpecialAttack or Cards[card_idx].Attack
    local target_hp = Matches[match_id].Cards[opponent_key][target_idx].HP
    Matches[match_id].Cards[opponent_key][target_idx].HP = math.max(0, target_hp - damage)
    Matches[match_id].Cards[player_key][card_idx].PlayCount = Matches[match_id].Cards[player_key][card_idx].PlayCount + 1
    Matches[match_id].Turn = opponent_key
    print("ProcessTurn: Damage: " .. damage .. ", New HP: " .. Matches[match_id].Cards[opponent_key][target_idx].HP .. ", New PlayCount: " .. Matches[match_id].Cards[player_key][card_idx].PlayCount .. ", New Turn: " .. Matches[match_id].Turn .. ", MsgID: " .. message_id)
    return damage
  end

  local function notifyPlayers(player_key, opponent_key, damage)
    print("ProcessTurn: Notifying players, MsgID: " .. message_id)
    local response_lines = {
      Colors.gray .. "Card: " .. Colors.blue .. Cards[card_idx].Name .. Colors.reset,
      Colors.gray .. "Move: " .. Colors.blue .. move_type .. Colors.reset,
      Colors.gray .. "Target: " .. Colors.blue .. Cards[target_idx].Name .. Colors.reset,
      Colors.gray .. "Damage: " .. Colors.green .. damage .. Colors.reset,
      Colors.gray .. "Next Turn: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players[opponent_key]) .. Colors.reset
    }
    ao.send({
      Target = process_id,
      Tags = { Action = "ProcessTurnResponse", MessageID = message_id },
      Data = formatPanel("Turn Processed", response_lines)
    })

    local opponent_lines = {
      Colors.gray .. "Opponent played: " .. Colors.blue .. Cards[card_idx].Name .. Colors.gray .. " (" .. move_type .. ")" .. Colors.reset,
      Colors.gray .. "Target: " .. Colors.blue .. Cards[target_idx].Name .. Colors.reset,
      Colors.gray .. "Damage: " .. Colors.green .. damage .. Colors.reset,
      Colors.gray .. "Your Turn" .. Colors.reset
    }
    local opponent_process_id = Players[Matches[match_id].Players[opponent_key]].ProcessID
    print("ProcessTurn: Notifying opponent " .. Matches[match_id].Players[opponent_key] .. ", ProcessID: " .. opponent_process_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = opponent_process_id,
      Tags = { Action = "YourTurn", MessageID = message_id },
      Data = formatPanel("Your Turn", opponent_lines)
    })
  end

  local function checkDefeat(opponent_key)
    print("ProcessTurn: Checking for defeat, MsgID: " .. message_id)
    local opponent_cards = Matches[match_id].Cards[opponent_key]
    local defeated = true
    for _, card in pairs(opponent_cards) do
      if card.HP > 0 then defeated = false break end
    end
    if defeated then
      print("ProcessTurn: Triggering EndGame for match: " .. match_id .. ", MsgID: " .. message_id)
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
    print("ProcessTurn: Fatal error: " .. tostring(result) .. ", Sending to " .. process_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "ProcessTurnResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Internal error: " .. tostring(result) .. Colors.reset })
    })
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "ProcessTurnError", MessageID = message_id },
      Data = "ProcessTurn failed: " .. tostring(result)
    })
  elseif not result then
    print("ProcessTurn: Early return, response already sent, MsgID: " .. message_id)
  end
end)

-- Handler: End Game
Handlers.add("EndGame", Handlers.utils.hasMatchingTag("Action", "EndGame"), function(msg)
  local match_id = msg.Tags.MatchID
  local process_id = msg.From
  local message_id = generateMessageID()

  print("EndGame: From " .. process_id .. ", MatchID: " .. tostring(match_id) .. ", MsgID: " .. message_id)
  if not match_id or not Matches[match_id] or Matches[match_id].State ~= "Active" then
    print("EndGame: Invalid or inactive match: " .. tostring(match_id) .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "EndGameResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Invalid or inactive match" .. Colors.reset })
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
    print("EndGame: Draw for match: " .. match_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "DistributeWinnings", MatchID = match_id, WinnerID = "Draw", MessageID = message_id }
    })
  elseif a_defeated then
    winner = Matches[match_id].Players.B
    Matches[match_id].State = "Ended"
    print("EndGame: Winner " .. winner .. " for match: " .. match_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "DistributeWinnings", MatchID = match_id, WinnerID = winner, MessageID = message_id }
    })
  elseif b_defeated then
    winner = Matches[match_id].Players.A
    Matches[match_id].State = "Ended"
    print("EndGame: Winner " .. winner .. " for match: " .. match_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = ao.env.Process.Id,
      Tags = { Action = "DistributeWinnings", MatchID = match_id, WinnerID = winner, MessageID = message_id }
    })
  end

  if winner then
    Leaderboard[winner] = (Leaderboard[winner] or 0) + 1
    local winner_lines = {
      Colors.gray .. "Winner: " .. Colors.blue .. getDisplayAddress(winner) .. Colors.reset
    }
    print("EndGame: Notifying players for match: " .. match_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = Players[Matches[match_id].Players.A].ProcessID,
      Tags = { Action = "MatchEnded", MessageID = message_id },
      Data = formatPanel("Match Ended", winner_lines)
    })
    ao.send({
      Target = Players[Matches[match_id].Players.B].ProcessID,
      Tags = { Action = "MatchEnded", MessageID = message_id },
      Data = formatPanel("Match Ended", winner_lines)
    })
  end
end)

-- Handler: Distribute Winnings
Handlers.add("DistributeWinnings", Handlers.utils.hasMatchingTag("Action", "DistributeWinnings"), function(msg)
  local match_id = msg.Tags.MatchID
  local winner_id = msg.Tags.WinnerID
  local process_id = msg.From
  local message_id = generateMessageID()

  print("DistributeWinnings: From " .. process_id .. ", MatchID: " .. tostring(match_id) .. ", WinnerID: " .. tostring(winner_id) .. ", MsgID: " .. message_id)
  if not match_id or not Matches[match_id] or Matches[match_id].State ~= "Ended" then
    print("DistributeWinnings: Invalid or not ended match: " .. tostring(match_id) .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "DistributeWinningsResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Invalid or not ended match" .. Colors.reset })
    })
    return
  end

  local token_process = "TOKEN_PROCESS_ID"
  if winner_id == "Draw" then
    local refund = Matches[match_id].Wager / 2
    Players[Matches[match_id].Players.A].Tokens = Players[Matches[match_id].Players.A].Tokens + refund
    Players[Matches[match_id].Players.B].Tokens = Players[Matches[match_id].Players.B].Tokens + refund
    local refund_lines = {
      Colors.gray .. "Refunded: " .. Colors.green .. refund .. Colors.gray .. " tokens" .. Colors.reset,
      Colors.gray .. "New Balance: " .. Colors.green .. Players[Matches[match_id].Players.A].Tokens .. Colors.reset
    }
    print("DistributeWinnings: Refunding " .. refund .. " to players for match: " .. match_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = Players[Matches[match_id].Players.A].ProcessID,
      Tags = { Action = "WinningsDistributed", MessageID = message_id },
      Data = formatPanel("Draw", refund_lines)
    })
    ao.send({
      Target = Players[Matches[match_id].Players.B].ProcessID,
      Tags = { Action = "WinningsDistributed", MessageID = message_id },
      Data = formatPanel("Draw", refund_lines)
    })
  else
    Players[winner_id].Tokens = Players[winner_id].Tokens + Matches[match_id].Wager
    local winner_lines = {
      Colors.gray .. "Won: " .. Colors.green .. Matches[match_id].Wager .. Colors.gray .. " tokens" .. Colors.reset,
      Colors.gray .. "New Balance: " .. Colors.green .. Players[winner_id].Tokens .. Colors.reset
    }
    print("DistributeWinnings: Awarding " .. Matches[match_id].Wager .. " to " .. winner_id .. " for match: " .. match_id .. ", MsgID: " .. message_id)
    ao.send({
      Target = Players[winner_id].ProcessID,
      Tags = { Action = "WinningsDistributed", MessageID = message_id },
      Data = formatPanel("Victory", winner_lines)
    })
    local loser_id = Matches[match_id].Players.A == winner_id and Matches[match_id].Players.B or Matches[match_id].Players.A
    local loser_lines = {
      Colors.gray .. "Winner: " .. Colors.blue .. getDisplayAddress(winner_id) .. Colors.reset
    }
    ao.send({
      Target = Players[loser_id].ProcessID,
      Tags = { Action = "WinningsDistributed", MessageID = message_id },
      Data = formatPanel("Defeat", loser_lines)
    })
    ao.send({
      Target = token_process,
      Tags = { Action = "Transfer", From = ao.env.Process.Id, To = winner_id, Amount = tostring(Matches[match_id].Wager), MessageID = message_id }
    })
  end

  -- Log to Arweave
  print("DistributeWinnings: Logging match " .. match_id .. " to Arweave, MsgID: " .. message_id)
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
  local process_id = msg.From
  local message_id = generateMessageID()

  print("GetMatchState: From " .. process_id .. ", MatchID: " .. tostring(match_id) .. ", RoomCode: " .. tostring(room_code) .. ", MsgID: " .. message_id)
  if room_code then
    match_id = findMatchByRoomCode(room_code)
  end

  if not match_id or not Matches[match_id] then
    print("GetMatchState: Invalid match ID or room code: " .. tostring(match_id or room_code) .. ", MsgID: " .. message_id)
    ao.send({
      Target = process_id,
      Tags = { Action = "MatchStateResponse", MessageID = message_id },
      Data = formatPanel("Error", { Colors.red .. "Invalid match ID or room code" .. Colors.reset })
    })
    return
  end

  local lines = {
    Colors.gray .. "Match ID: " .. Colors.blue .. match_id .. Colors.reset,
    Colors.gray .. "Room Code: " .. Colors.blue .. Matches[match_id].RoomCode .. Colors.reset,
    Colors.gray .. "State: " .. Colors.blue .. Matches[match_id].State .. Colors.reset,
    Colors.gray .. "Wager: " .. Colors.green .. Matches[match_id].Wager .. Colors.gray .. " tokens" .. Colors.reset,
    Colors.gray .. "Turn: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players[Matches[match_id].Turn]) .. Colors.reset,
    Colors.gray .. "Player A: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.A) .. Colors.reset,
    Colors.gray .. "Player B: " .. Colors.blue .. getDisplayAddress(Matches[match_id].Players.B) .. Colors.reset
  }
  for player_key, cards in pairs(Matches[match_id].Cards) do
    local player_address = Matches[match_id].Players[player_key]
    local card_lines = {}
    for i, card in ipairs(cards) do
      card_lines[#card_lines + 1] = Colors.gray .. Cards[i].Name .. ": " .. Colors.green .. card.HP .. Colors.gray .. " HP, " .. card.PlayCount .. "/3 plays" .. Colors.reset
    end
    lines[#lines + 1] = Colors.gray .. "Player " .. player_key .. " (" .. Colors.blue .. getDisplayAddress(player_address) .. Colors.gray .. "):" .. Colors.reset
    for _, line in ipairs(card_lines) do lines[#lines + 1] = line end
  end

  print("GetMatchState: Sending state for match: " .. match_id .. " to " .. process_id .. ", MsgID: " .. message_id)
  ao.send({
    Target = process_id,
    Tags = { Action = "MatchStateResponse", MessageID = message_id },
    Data = formatPanel("Match State", lines)
  })
end)

-- Handler: Get Leaderboard
Handlers.add("GetLeaderboard", Handlers.utils.hasMatchingTag("Action", "GetLeaderboard"), function(msg)
  local process_id = msg.From
  local message_id = generateMessageID()

  print("GetLeaderboard: From " .. process_id .. ", MsgID: " .. message_id)
  local sorted = {}
  for addr, wins in pairs(Leaderboard) do
    sorted[#sorted + 1] = { address = addr, wins = wins, tokens = Players[addr] and Players[addr].Tokens or 0 }
  end
  table.sort(sorted, function(a, b) return a.wins > b.wins end)
  local lines = {}
  for i = 1, math.min(5, #sorted) do
    local address = getDisplayAddress(sorted[i].address)
    lines[#lines + 1] = Colors.gray .. i .. ". " .. Colors.blue .. address .. Colors.gray .. ": " .. Colors.green .. sorted[i].wins .. Colors.gray .. " wins, " .. Colors.green .. sorted[i].tokens .. Colors.gray .. " tokens" .. Colors.reset
  end
  print("GetLeaderboard: Sending leaderboard to " .. process_id .. ", MsgID: " .. message_id)
  ao.send({
    Target = process_id,
    Tags = { Action = "LeaderboardResponse", MessageID = message_id },
    Data = formatPanel("Leaderboard", lines)
  })
end)

-- Notes:
-- Match state stored in AO memory, outcomes logged to Arweave via IRYS_PROCESS_ID.
-- Replace TOKEN_PROCESS_ID with actual $U token process ID.
-- Use AR.IO caching for ProcessTurn and SyncMatchState handlers.
-- Test with LuaUnit for at least 10 matches.
-- End of file