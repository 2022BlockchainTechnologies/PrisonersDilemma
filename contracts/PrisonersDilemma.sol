// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

enum Move {
  Hidden,
  StaySilent,
  Defect
}

struct Commitment {
  address owner;
  uint wager;
  bytes32 hashed;
  Move move;
}

struct Game {
  Commitment a;
  Commitment b;
  bool paid;
}

contract PrisonersDilemma {
  address owner;

  Game[] committedGames;
  Game currentGame;

  constructor() {
    owner = msg.sender;
  }

  receive() external payable { }

  fallback() external payable { }

  function getBalance() public view returns (uint) {
    return address(this).balance;
  }

  function destroy() public {
    if(msg.sender != owner) {
      revert ("owner only");
    }
    selfdestruct(payable(owner));
  }

  function getCommittedGames() public view returns(Game[] memory) {
    return committedGames;
  }

  function getCurrentGame() public view returns(Game memory) {
    return currentGame;
  }

  function getWorstCasePendingPayout() public view returns(uint) {
    uint pending = currentGame.a.wager + currentGame.b.wager;
    for(uint i = 0; i < committedGames.length; i++) {
      Game storage g = committedGames[i];
      if(!g.paid) {
        pending += g.a.wager + g.b.wager;
      }
    }
    // worst case everybody cooperates
    return pending * 14 / 10;
  }

  function getMaxWager() public view returns(uint) {
    return (getBalance() - getWorstCasePendingPayout()) / 10;
  }
  
  function hashMove(Move move, bytes32 nonce) public pure returns(bytes32) {
    return keccak256(abi.encodePacked(move, nonce));
  }

  function commit(bytes32 commitmentHash) public payable {
    if(msg.value > getMaxWager()) {
      revert("commit: wager too high");
    }

    if(currentGame.a.owner == address(0)) {
      currentGame.a.owner = msg.sender;
      currentGame.a.hashed = commitmentHash;
      currentGame.a.wager = msg.value;
    }
    else {
      currentGame.b.owner = msg.sender;
      currentGame.b.hashed = commitmentHash;
      currentGame.b.wager = msg.value;

      committedGames.push(currentGame);

      delete currentGame;
    }
  }

  function reveal(Move move, bytes32 nonce) public {
    
    if(!(move == Move.StaySilent || move == Move.Defect)) {
      revert ("reveal: invalid move");
    }

    bytes32 h = hashMove(move, nonce);

    for(uint i = 0; i < committedGames.length; i++) {

      Game storage g = committedGames[i];
      
      if(g.a.owner == msg.sender && g.a.hashed == h && g.a.move == Move.Hidden) {
        g.a.move = move;
        return;
      }
      if(g.b.owner == msg.sender && g.b.hashed == h && g.b.move == Move.Hidden) {
        g.b.move = move;
        return;
      }
    }

    revert ("reveal: no matching game found");
  }

  function playUnsafe(Move move) public payable {
    if(!(move == Move.StaySilent || move == Move.Defect)) {
      revert ("playUnsafe: invalid move");
    }

    bytes32 defaultNonce = 0;
    bytes32 h = hashMove(move, defaultNonce);
    
    commit(h);
    if(currentGame.a.owner == msg.sender) {
      currentGame.a.move = move;
    }
    else {
      committedGames[committedGames.length - 1].b.move = move;
    }
  }

  event GameResult(uint wagerA, uint payoutA, uint wagerB, uint payoutB);

  function payout() public {

    for(uint i = 0; i < committedGames.length; i++) {
      Game storage g = committedGames[i];

      if(g.paid || (g.a.owner != msg.sender && g.b.owner != msg.sender)) {
        continue;
      }

      uint amountA;
      uint amountB;

      if(g.a.move == Move.StaySilent && g.b.move == Move.StaySilent) {
        amountA = g.a.wager * 14 / 10;
        amountB = g.b.wager * 14 / 10;
      }
      else if(g.a.move == Move.Defect && g.b.move == Move.StaySilent) {
        amountA = g.a.wager * 17 / 10;
        amountB = g.b.wager *  1 / 10;
      }
      else if(g.a.move == Move.StaySilent && g.b.move == Move.Defect) {
        amountA = g.a.wager *  1 / 10;
        amountB = g.b.wager * 17 / 10;
      }
      else if(g.a.move == Move.Defect && g.b.move == Move.Defect) {
        amountA = g.a.wager *  8 / 10;
        amountB = g.b.wager *  8 / 10;
      }
      else {
        continue;
      }

      bool success;

      (success, ) = payable(g.a.owner).call { value: amountA }("");
      require (success, "tx failed");
      (success, ) = payable(g.b.owner).call { value: amountB }("");
      require (success, "tx failed");
      
      emit GameResult(g.a.wager, amountA, g.b.wager, amountB);

      // ideally delete from the array instead but it was buggy idk
      committedGames[i].paid = true; 
      return;
    }
    revert ('payout: no matching game found');
  }
}
