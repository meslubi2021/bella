import gleam/list
import gleam/result.{try}
import bella/error
import bella/lexer/token.{Token, Tokens}

pub type Expr {
  Var(String)
  String(String)
  Number(Float)
  Bool(Bool)
  Block(List(Expr))
  Record(fields: List(#(String, Expr)))
  RecordAccess(record: Expr, field: String)
  BinOp(operator: Token, left: Expr, right: Expr)
  Unary(operator: Token, value: Expr)
  Lambda(param: String, body: Expr)
  Lambda0(body: Expr)
  Let(name: String, value: Expr, body: Expr)
  Call(callee: Expr, arg: Expr)
  Call0(callee: Expr)
  If(cond: Expr, true_branch: Expr, false_branch: Expr)
  Try(body: Expr, else: Expr)
  Throw(value: Expr)
}

type Parsed =
  Result(#(Expr, Tokens), error.Error)

type Parser =
  fn(Tokens) -> Parsed

pub fn parse(tokens: Tokens) -> Result(List(Expr), error.Error) {
  use result <- try(parse_exprs(tokens, []))
  result
  |> list.reverse
  |> Ok
}

fn parse_exprs(
  tokens: Tokens,
  exprs: List(Expr),
) -> Result(List(Expr), error.Error) {
  case tokens {
    [token.Eof] -> Ok(exprs)
    _ -> {
      use #(expr, rest) <- try(parse_expr(tokens))
      parse_exprs(rest, [expr, ..exprs])
    }
  }
}

fn parse_expr(tokens: Tokens) -> Parsed {
  case tokens {
    [token.If, ..rest] -> parse_if(rest)
    [token.Let, ..rest] -> parse_let(rest)
    [token.Ident(n), token.Arrow, ..rest] -> {
      use #(body, rest) <- try(parse_expr(rest))
      Ok(#(Lambda(n, body), rest))
    }
    [token.Arrow, ..rest] -> {
      use #(body, rest) <- try(parse_expr(rest))
      Ok(#(Lambda0(body), rest))
    }
    [token.Throw, ..rest] -> {
      use #(value, rest) <- try(parse_expr(rest))
      Ok(#(Throw(value), rest))
    }
    [token.Try, ..rest] -> parse_try(rest)
    _ -> parse_pipe(tokens)
  }
}

fn expect(
  tok: Token,
  tokens: Tokens,
  msg: String,
  callback: fn(Tokens) -> Parsed,
) -> Parsed {
  case tokens {
    [head, ..tail] if head == tok -> callback(tail)
    _ -> error.expected(msg)
  }
}

fn parse_let(tokens: Tokens) -> Parsed {
  case tokens {
    [token.Ident(name), ..rest] -> {
      use rest <- expect(token.Eq, rest, "= after identifier")
      use #(value, rest) <- try(parse_expr(rest))
      finish_let(Let(name, value, _), rest)
    }
    _ -> error.expected("identifier after let")
  }
}

fn finish_let(constructor: fn(Expr) -> Expr, tokens: Tokens) {
  case tokens {
    [token.Ident(name), ..rest] -> {
      use rest <- expect(token.Eq, rest, "= after identifier")
      use #(value, rest) <- try(parse_expr(rest))
      use #(body, rest) <- try(finish_let(Let(name, value, _), rest))
      Ok(#(constructor(body), rest))
    }
    [token.In, ..rest] -> {
      use #(body, rest) <- try(parse_expr(rest))
      Ok(#(constructor(body), rest))
    }
    _ -> error.expected("identifier after let")
  }
}

fn parse_if(tokens: Tokens) -> Parsed {
  use rest <- expect(token.LParen, tokens, "( before condition")
  use #(condition, rest) <- try(parse_expr(rest))
  use rest <- expect(token.RParen, rest, ") after condition")
  use #(true_branch, rest) <- try(parse_expr(rest))
  use rest <- expect(token.Else, rest, "`else` after true branch")
  use #(false_branch, rest) <- try(parse_expr(rest))
  Ok(#(If(condition, true_branch, false_branch), rest))
}

fn parse_try(tokens: Tokens) -> Parsed {
  use #(body, rest) <- try(parse_expr(tokens))
  use rest <- expect(token.Else, rest, "`else` after try body")
  use #(else, rest) <- try(parse_expr(rest))
  Ok(#(Try(body, else), rest))
}

fn parse_pipe(tokens: Tokens) -> Parsed {
  parse_binop([token.RPipe], parse_logic_or, tokens)
}

fn parse_logic_or(tokens: Tokens) -> Parsed {
  parse_binop([token.Or], parse_logic_and, tokens)
}

fn parse_logic_and(tokens: Tokens) -> Parsed {
  parse_binop([token.And], parse_equality, tokens)
}

fn parse_equality(tokens: Tokens) -> Parsed {
  parse_binop([token.EqEq, token.Neq], parse_comparison, tokens)
}

fn parse_comparison(tokens: Tokens) -> Parsed {
  parse_binop(
    [token.Greater, token.GreaterEq, token.Less, token.LessEq],
    parse_term,
    tokens,
  )
}

fn parse_term(tokens: Tokens) -> Parsed {
  parse_binop([token.Plus, token.Minus], parse_factor, tokens)
}

fn parse_factor(tokens: Tokens) -> Parsed {
  parse_binop([token.Star, token.Slash], parse_unary, tokens)
}

fn parse_unary(tokens: Tokens) -> Parsed {
  case tokens {
    [token.Minus as op, ..rest] | [token.Bang as op, ..rest] -> {
      use #(expr, rest) <- try(parse_unary(rest))
      Ok(#(Unary(op, expr), rest))
    }
    _ -> parse_call(tokens)
  }
}

fn parse_call(tokens: Tokens) -> Parsed {
  use #(expr, rest) <- try(parse_primary(tokens))
  finish_call(expr, rest)
}

fn finish_call(callee: Expr, tokens: Tokens) -> Parsed {
  case tokens {
    [token.LParen, token.RParen, ..rest] -> {
      finish_call(Call0(callee), rest)
    }
    [token.LParen, ..rest] -> {
      use #(arg, rest) <- try(parse_expr(rest))
      finish_call_args(Call(callee, arg), rest)
    }
    [token.Dot, ..rest] -> {
      case rest {
        [token.Ident(name), ..rest] -> {
          finish_call(RecordAccess(callee, name), rest)
        }
        _ -> error.expected("identifier after .")
      }
    }
    _ -> Ok(#(callee, tokens))
  }
}

fn finish_call_args(callee: Expr, tokens: Tokens) -> Parsed {
  case tokens {
    [token.Comma, ..rest] -> {
      use #(arg, rest) <- try(parse_expr(rest))
      finish_call_args(Call(callee, arg), rest)
    }
    [token.RParen, ..rest] -> finish_call(callee, rest)
    _ -> error.expected(", or )")
  }
}

fn parse_binop(ops: Tokens, subrule: Parser, tokens: Tokens) -> Parsed {
  use #(left, rest) <- try(subrule(tokens))
  finish_binop(left, ops, subrule, rest)
}

fn finish_binop(
  left: Expr,
  ops: Tokens,
  subrule: Parser,
  tokens: Tokens,
) -> Parsed {
  let [op, ..rest] = tokens
  case list.contains(ops, op) {
    True -> {
      use #(right, rest) <- try(subrule(rest))
      finish_binop(BinOp(op, left, right), ops, subrule, rest)
    }
    False -> Ok(#(left, tokens))
  }
}

fn parse_primary(tokens: Tokens) -> Parsed {
  case tokens {
    [token.Number(x), ..rest] -> Ok(#(Number(x), rest))
    [token.String(x), ..rest] -> Ok(#(String(x), rest))
    [token.Ident(x), ..rest] -> Ok(#(Var(x), rest))
    [token.True, ..rest] -> Ok(#(Bool(True), rest))
    [token.False, ..rest] -> Ok(#(Bool(False), rest))
    [token.LParen, ..rest] -> parse_block(rest, [])
    [token.LBrace, ..rest] -> parse_record(rest)
    [tok, ..] -> error.unexpected("token: " <> token.token_to_string(tok))
  }
}

fn parse_block(tokens: Tokens, acc: List(Expr)) -> Parsed {
  case tokens {
    [token.RParen, ..rest] -> {
      case acc {
        [] -> error.unexpected("end of block")
        _ -> Ok(#(Block(list.reverse(acc)), rest))
      }
    }
    _ -> {
      use #(expr, rest) <- try(parse_expr(tokens))
      parse_block(rest, [expr, ..acc])
    }
  }
}

fn parse_record_item(tokens: Tokens) {
  case tokens {
    [token.Ident(name), token.Colon, ..rest] -> {
      use #(value, rest) <- try(parse_expr(rest))
      Ok(#(#(name, value), rest))
    }
    [token.Ident(name), ..rest] -> {
      Ok(#(#(name, Var(name)), rest))
    }
    _ -> error.expected("identifier")
  }
}

fn parse_record(tokens: Tokens) -> Parsed {
  case tokens {
    [token.RBrace, ..rest] -> {
      Ok(#(Record([]), rest))
    }
    _ -> {
      use #(#(name, value), rest) <- try(parse_record_item(tokens))
      finish_record(rest, [#(name, value)])
    }
  }
}

fn finish_record(tokens: Tokens, fields: List(#(String, Expr))) -> Parsed {
  case tokens {
    [token.Comma, ..rest] -> {
      use #(#(name, value), rest) <- try(parse_record_item(rest))
      case list.any(fields, fn(f) { f.0 == name }) {
        True -> error.unexpected("duplicate record field: " <> name)
        False -> finish_record(rest, [#(name, value), ..fields])
      }
    }
    [token.RBrace, ..rest] -> Ok(#(Record(fields), rest))
    _ -> error.expected(", or }")
  }
}
