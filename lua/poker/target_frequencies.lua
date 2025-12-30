-- Target solver-inspired frequencies the tuner should move toward.
return {
  preflop = {
    open = 0.18,
    call = 0.14,
    three_bet = 0.06,
  },
  flop = {
    fold = 0.18,
    raise = 0.10,
  },
  turn = {
    fold = 0.20,
    raise = 0.11,
  },
  river = {
    fold = 0.22,
    raise = 0.12,
  },
}
