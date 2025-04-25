// ChronoClash: The Arena of Echoes Wallet Integration, Game State Display, and Turn Submission
const processId = "OUjbV7GD2mNHTFxx1iAm7E8nqLpvChMDCEHo_-zglVI";

document.addEventListener("DOMContentLoaded", () => {
  const walletView = document.getElementById("wallet-view");
  const matchOptionsView = document.getElementById("match-options-view");
  const matchView = document.getElementById("match-view");
  const connectButton = document.getElementById("connect-wallet");
  const disconnectButton = document.getElementById("disconnect-wallet");
  const statusText = document.getElementById("status");
  const matchIdDisplay = document.getElementById("match-id-display");
  const roomCodeDisplay = document.getElementById("room-code-display");
  const wagerDisplay = document.getElementById("wager-display");
  const turnDisplay = document.getElementById("turn-display");
  const yourCardsDisplay = document.getElementById("your-cards-display");
  const opponentCardsDisplay = document.getElementById("opponent-cards-display");
  const tokensDisplay = document.getElementById("tokens-display");
  const tokensProgress = document.getElementById("tokens-progress");
  const leaderboardBody = document.getElementById("leaderboard-body");
  const wagerInput = document.getElementById("wager-input");
  const createMatchButton = document.getElementById("create-match");
  const roomCodeInput = document.getElementById("room-code-input");
  const joinMatchButton = document.getElementById("join-match");
  const cardSelect = document.getElementById("card-select");
  const moveTypeSelect = document.getElementById("move-type-select");
  const targetSelect = document.getElementById("target-select");
  const playTurnButton = document.getElementById("play-turn");
  const refreshStateButton = document.getElementById("refresh-state");
  const refreshLeaderboardButton = document.getElementById("refresh-leaderboard");
  const responseDiv = document.getElementById("response");
  let walletAddress = null;
  let currentMatchId = null;

  function showResponse(message, className) {
    responseDiv.textContent = message;
    responseDiv.className = `response ${className}`;
    responseDiv.classList.add("show");
    setTimeout(() => responseDiv.classList.remove("show"), 3000);
  }

  function showView(view) {
    [walletView, matchOptionsView, matchView].forEach(v => v.classList.remove("active"));
    view.classList.add("active");
  }

  async function loadLeaderboard() {
    try {
      const dryrunResponse = await window.dryrun({
        process: processId,
        tags: [{ name: "Action", value: "GetLeaderboard" }, { name: "filetype", value: "json" }]
      });
      console.log("Dryrun GetLeaderboard response:", JSON.stringify(dryrunResponse, null, 2));
      const data = JSON.parse(dryrunResponse.Messages[0]?.Data || "{}");

      if (data.status === "success" && data.leaderboard) {
        const entries = data.leaderboard.slice(0, 5).map(entry => ({
          address: entry.address.length > 10 ? `${entry.address.slice(0, 6)}...${entry.address.slice(-4)}` : entry.address,
          wins: entry.wins,
          tokens: entry.tokens
        }));

        if (entries.length === 0) {
          leaderboardBody.innerHTML = '<tr><td colspan="4">No leaderboard data</td></tr>';
          showResponse("Leaderboard empty", "error");
          return;
        }

        leaderboardBody.innerHTML = entries.map((entry, index) => `
          <tr>
            <td>${index + 1}</td>
            <td>${entry.address}</td>
            <td>${entry.wins}</td>
            <td>${entry.tokens}</td>
          </tr>
        `).join("");
      } else {
        leaderboardBody.innerHTML = '<tr><td colspan="4">Error fetching leaderboard</td></tr>';
        showResponse(`Error fetching leaderboard: ${data.message || "Unexpected response"}`, "error");
      }
    } catch (error) {
      console.error("Dryrun GetLeaderboard failed:", error);
      leaderboardBody.innerHTML = '<tr><td colspan="4">Error fetching leaderboard</td></tr>';
      showResponse(`Error fetching leaderboard: ${error.message}`, "error");
    }
  }

  async function fetchMatchState() {
    try {
      const dryrunResponse = await window.dryrun({
        process: processId,
        tags: [
          { name: "Action", value: "GetMatchState" },
          { name: "Address", value: walletAddress || "" },
          { name: "RoomCode", value: roomCodeInput.value.trim() || "" },
          { name: "filetype", value: "json" }
        ]
      });
      console.log("Dryrun GetMatchState response:", JSON.stringify(dryrunResponse, null, 2));
      const data = JSON.parse(dryrunResponse.Messages[0]?.Data || "{}");

      if (data.status === "success") {
        currentMatchId = data.match_id;
        matchIdDisplay.textContent = data.match_id || "None";
        roomCodeDisplay.textContent = data.room_code || "None";
        wagerDisplay.textContent = data.wager || "0";
        turnDisplay.textContent = data.turn ? (data.turn.length > 10 ? `${data.turn.slice(0, 6)}...${data.turn.slice(-4)}` : data.turn) : "None";

        const yourKey = data.player_a === walletAddress ? "A" : (data.player_b === walletAddress ? "B" : null);
        const opponentKey = yourKey === "A" ? "B" : (yourKey === "B" ? "A" : null);

        yourCardsDisplay.textContent = yourKey && data.cards[yourKey] ? data.cards[yourKey].cards.map(c => `${c.name}: ${c.hp} HP, ${c.play_count}/3`).join(", ") : "None";
        opponentCardsDisplay.textContent = opponentKey && data.cards[opponentKey] ? data.cards[opponentKey].cards.map(c => `${c.name}: ${c.hp} HP, ${c.play_count}/3`).join(", ") : "None";

        const tokensResponse = await window.dryrun({
          process: processId,
          tags: [
            { name: "Action", value: "JoinGame" },
            { name: "Address", value: walletAddress },
            { name: "filetype", value: "json" }
          ]
        });
        console.log("Dryrun JoinGame for tokens response:", JSON.stringify(tokensResponse, null, 2));
        const tokensData = JSON.parse(tokensResponse.Messages[0]?.Data || "{}");
        const tokens = tokensData.tokens || "0";
        tokensDisplay.textContent = tokens;
        tokensProgress.style.width = `${Math.min((parseInt(tokens) / 100) * 100, 100)}%`;
      } else {
        throw new Error(data.message || "Invalid match state");
      }
    } catch (error) {
      console.error("Fetch match state failed:", error);
      showResponse(`Error fetching match state: ${error.message}`, "error");
      matchIdDisplay.textContent = "None";
      roomCodeDisplay.textContent = "None";
      wagerDisplay.textContent = "0";
      turnDisplay.textContent = "None";
      yourCardsDisplay.textContent = "None";
      opponentCardsDisplay.textContent = "None";
      tokensDisplay.textContent = "0";
      tokensProgress.style.width = "0%";
    }
  }

  connectButton.addEventListener("click", async () => {
    try {
      if (!window.arweaveWallet) {
        statusText.textContent = "ArConnect not installed";
        showResponse("Please install ArConnect wallet extension.", "error");
        console.error("ArConnect is not installed.");
        return;
      }

      await window.arweaveWallet.connect(["ACCESS_ADDRESS", "SIGNATURE", "SIGN_TRANSACTION"]);
      walletAddress = await window.arweaveWallet.getActiveAddress();

      if (typeof window.createDataItemSigner !== "function") {
        throw new Error("createDataItemSigner is not available.");
      }

      statusText.textContent = `Connected: ${walletAddress.slice(0, 8)}...`;
      showView(matchOptionsView);
      showResponse("Wallet connected successfully!", "success");

      const signer = window.createDataItemSigner(window.arweaveWallet);
      const messageResponse = await window.message({
        process: processId,
        tags: [
          { name: "Action", value: "JoinGame" },
          { name: "Address", value: walletAddress },
          { name: "filetype", value: "json" }
        ],
        signer: signer
      });
      console.log("Message JoinGame response:", JSON.stringify(messageResponse, null, 2));
      showResponse("Joined game successfully!", "success");
      loadLeaderboard();
    } catch (error) {
      console.error("Wallet connection failed:", error);
      showResponse(`Error connecting wallet: ${error.message}`, "error");
    }
  });

  disconnectButton.addEventListener("click", async () => {
    try {
      if (window.arweaveWallet) {
        await window.arweaveWallet.disconnect();
      }
      walletAddress = null;
      currentMatchId = null;
      statusText.textContent = "Not connected";
      showView(walletView);
      showResponse("Wallet disconnected successfully!", "success");
      matchIdDisplay.textContent = "None";
      roomCodeDisplay.textContent = "None";
      wagerDisplay.textContent = "0";
      turnDisplay.textContent = "None";
      yourCardsDisplay.textContent = "None";
      opponentCardsDisplay.textContent = "None";
      tokensDisplay.textContent = "0";
      tokensProgress.style.width = "0%";
      leaderboardBody.innerHTML = "";
      wagerInput.value = "";
      roomCodeInput.value = "";
      cardSelect.value = "";
      moveTypeSelect.value = "";
      targetSelect.value = "";
      console.log("Wallet disconnected");
    } catch (error) {
      console.error("Wallet disconnect failed:", error);
      showResponse(`Error disconnecting wallet: ${error.message}`, "error");
    }
  });

  createMatchButton.addEventListener("click", async () => {
    if (!walletAddress) {
      showResponse("Please connect wallet first", "error");
      return;
    }

    const wager = parseInt(wagerInput.value.trim());
    if (!wager || wager <= 0) {
      showResponse("Please enter a valid wager greater than 0", "error");
      return;
    }

    try {
      const signer = window.createDataItemSigner(window.arweaveWallet);
      const dryrunResponse = await window.dryrun({
        process: processId,
        tags: [
          { name: "Action", value: "CoordinateRoom" },
          { name: "Address", value: walletAddress },
          { name: "WagerAmount", value: wager.toString() },
          { name: "filetype", value: "json" }
        ],
        signer: signer
      });
      console.log("Dryrun CoordinateRoom (create) response:", JSON.stringify(dryrunResponse, null, 2));

      const responseMessage = dryrunResponse.Messages.find(msg => msg.Tags.some(tag => tag.name === "Action" && tag.value === "CoordinateRoomResponse"));
      if (!responseMessage) {
        throw new Error("CoordinateRoomResponse not found in messages");
      }

      const data = JSON.parse(responseMessage.Data || "{}");

      if (data.status === "success") {
        currentMatchId = data.match_id;
        roomCodeInput.value = data.room_code;
        showResponse(`Room created! Code: ${data.room_code}, Wager: ${data.wager}, Match ID: ${data.match_id}`, "success");

        const messageResponse = await window.message({
          process: processId,
          tags: [
            { name: "Action", value: "CoordinateRoom" },
            { name: "Address", value: walletAddress },
            { name: "WagerAmount", value: wager.toString() },
            { name: "filetype", value: "json" }
          ],
          signer: signer
        });
        console.log("Message CoordinateRoom (create) response:", JSON.stringify(messageResponse, null, 2));
        showResponse(`Room created! Code: ${data.room_code}, Tokens: ${data.tokens_remaining}, Match ID: ${data.match_id}`, "success");
        wagerInput.value = "";
        fetchMatchState();
        showView(matchView);
      } else {
        showResponse(`Error creating room: ${data.message}`, "error");
      }
    } catch (error) {
      console.error("Dryrun CoordinateRoom (create) failed:", error);
      showResponse(`Error creating room: ${error.message}`, "error");
    }
  });

  joinMatchButton.addEventListener("click", async () => {
    if (!walletAddress) {
      showResponse("Please connect wallet first", "error");
      return;
    }

    const roomCode = roomCodeInput.value.trim();
    if (!roomCode) {
      showResponse("Please enter a room code", "error");
      return;
    }

    try {
      const signer = window.createDataItemSigner(window.arweaveWallet);
      const dryrunResponse = await window.dryrun({
        process: processId,
        tags: [
          { name: "Action", value: "CoordinateRoom" },
          { name: "Address", value: walletAddress },
          { name: "RoomCode", value: roomCode },
          { name: "filetype", value: "json" }
        ],
        signer: signer
      });
      console.log("Dryrun CoordinateRoom (join) response:", JSON.stringify(dryrunResponse, null, 2));

      const responseMessage = dryrunResponse.Messages.find(msg => msg.Tags.some(tag => tag.name === "Action" && tag.value === "CoordinateRoomResponse"));
      if (!responseMessage) {
        throw new Error("CoordinateRoomResponse not found in messages");
      }

      const data = JSON.parse(responseMessage.Data || "{}");

      if (data.status === "success") {
        currentMatchId = data.match_id;
        const shortOpponent = data.opponent.length > 10 ? `${data.opponent.slice(0, 6)}...${data.opponent.slice(-4)}` : data.opponent;
        const shortTurn = data.current_turn.length > 10 ? `${data.current_turn.replace(" (Player A)", "").slice(0, 6)}...${data.current_turn.replace(" (Player A)", "").slice(-4)}` : data.current_turn.replace(" (Player A)", "");
        showResponse(`Joined match! Opponent: ${shortOpponent}, Wager: ${data.wager}, Match ID: ${data.match_id}`, "success");

        const messageResponse = await window.message({
          process: processId,
          tags: [
            { name: "Action", value: "CoordinateRoom" },
            { name: "Address", value: walletAddress },
            { name: "RoomCode", value: roomCode },
            { name: "filetype", value: "json" }
          ],
          signer: signer
        });
        console.log("Message CoordinateRoom (join) response:", JSON.stringify(messageResponse, null, 2));
        showResponse(`Match started! Your turn: ${shortTurn}, Match ID: ${data.match_id}`, "success");
        fetchMatchState();
        showView(matchView);
      } else {
        showResponse(`Error joining match: ${data.message || "Invalid response format"}`, "error");
      }
    } catch (error) {
      console.error("Dryrun CoordinateRoom (join) failed:", error);
      showResponse(`Error joining match: ${error.message}`, "error");
    }
  });

  playTurnButton.addEventListener("click", async () => {
    if (!walletAddress) {
      showResponse("Please connect wallet first", "error");
      return;
    }

    const cardIdx = cardSelect.value;
    const moveType = moveTypeSelect.value;
    const targetIdx = targetSelect.value;
    const roomCode = roomCodeInput.value.trim();

    if (!cardIdx || !moveType || !targetIdx || !roomCode) {
      showResponse("Please select card, move type, target, and ensure room code is set", "error");
      return;
    }

    if (!["1", "2", "3", "4"].includes(cardIdx) || !["1", "2", "3", "4"].includes(targetIdx)) {
      showResponse("Invalid card or target index (must be 1-4)", "error");
      return;
    }

    if (!["Normal", "Special"].includes(moveType)) {
      showResponse("Invalid move type (must be Normal or Special)", "error");
      return;
    }

    try {
      const signer = window.createDataItemSigner(window.arweaveWallet);
      const dryrunResponse = await window.dryrun({
        process: processId,
        tags: [
          { name: "Action", value: "ProcessTurn" },
          { name: "Address", value: walletAddress },
          { name: "RoomCode", value: roomCode },
          { name: "CardIdx", value: cardIdx },
          { name: "MoveType", value: moveType },
          { name: "TargetIdx", value: targetIdx },
          { name: "filetype", value: "json" }
        ],
        signer: signer
      });
      console.log("Dryrun ProcessTurn response:", JSON.stringify(dryrunResponse, null, 2));
      const data = JSON.parse(dryrunResponse.Messages[0]?.Data || "{}");

      if (data.status === "success") {
        showResponse(`Turn played! ${data.card} (${data.move}) dealt ${data.damage} to ${data.target}`, "success");

        const messageResponse = await window.message({
          process: processId,
          tags: [
            { name: "Action", value: "ProcessTurn" },
            { name: "Address", value: walletAddress },
            { name: "RoomCode", value: roomCode },
            { name: "CardIdx", value: cardIdx },
            { name: "MoveType", value: moveType },
            { name: "TargetIdx", value: targetIdx },
            { name: "filetype", value: "json" }
          ],
          signer: signer
        });
        console.log("Message ProcessTurn response:", JSON.stringify(messageResponse, null, 2));
        showResponse(`Turn processed! Next: ${data.next_turn.length > 10 ? `${data.next_turn.slice(0, 6)}...${data.next_turn.slice(-4)}` : data.next_turn}`, "success");
        cardSelect.value = "";
        moveTypeSelect.value = "";
        targetSelect.value = "";
        fetchMatchState();
        loadLeaderboard();
      } else {
        showResponse(`Error playing turn: ${data.message}`, "error");
      }
    } catch (error) {
      console.error("Dryrun ProcessTurn failed:", error);
      showResponse(`Error playing turn: ${error.message}`, "error");
    }
  });

  refreshStateButton.addEventListener("click", () => {
    if (!walletAddress) {
      showResponse("Please connect wallet first", "error");
      return;
    }
    fetchMatchState();
    showResponse("Match state refreshed", "success");
  });

  refreshLeaderboardButton.addEventListener("click", () => {
    loadLeaderboard();
    showResponse("Leaderboard refreshed", "success");
  });
});