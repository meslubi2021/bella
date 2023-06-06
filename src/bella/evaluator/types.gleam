import gleam/map
import gleam/list
import gleam/float
import gleam/int
import gleam/string
import bella/error
import bella/parser

// TYPES .......................................................................

pub type DataType {
  Number(Float)
  String(String)
  Bool(Bool)
  Record(fields: map.Map(String, DataType))
  List(List(DataType))
  Lambda(param: String, body: parser.Expr, closure: Scope)
  Lambda0(body: parser.Expr, closure: Scope)
  Builtin(func: fn(DataType, Scope) -> Evaluated)
}

pub type Scope =
  map.Map(String, DataType)

pub type Evaluated =
  Result(#(DataType, Scope), error.Error)

// UTILS .......................................................................

pub fn to_string(x: DataType) -> String {
  case x {
    Number(n) ->
      case float.floor(n) == n {
        True -> int.to_string(float.truncate(n))
        False -> float.to_string(n)
      }
    String(s) -> unescape(s)
    Bool(b) ->
      case b {
        True -> "true"
        False -> "false"
      }
    Record(f) -> record_to_string(f)
    List(l) -> list_to_string(l)
    Lambda(param, ..) -> "#lambda<" <> param <> ">"
    Lambda0(..) -> "#lambda<>"
    Builtin(..) -> "#builtin"
  }
}

fn unescape(string: String) -> String {
  string
  |> string.replace("\\\"", "\"")
  |> string.replace("\\'", "'")
  |> string.replace("\\n", "\n")
  |> string.replace("\\r", "\r")
  |> string.replace("\\t", "\t")
  |> string.replace("\\\\", "\\")
}

fn list_to_string(items: List(DataType)) -> String {
  let items =
    items
    |> list.map(inspect)
    |> string.join(", ")

  "[" <> items <> "]"
}

fn record_to_string(fields: map.Map(String, DataType)) -> String {
  let fields =
    fields
    |> map.to_list
    |> list.map(fn(field) {
      let #(name, value) = field
      name <> ": " <> inspect(value)
    })
    |> string.join(", ")

  "{ " <> fields <> " }"
}

fn inspect(x: DataType) -> String {
  case x {
    String(s) -> "\"" <> s <> "\""
    _ -> to_string(x)
  }
}

pub fn to_type(x: DataType) -> String {
  case x {
    Number(..) -> "number"
    String(..) -> "string"
    Bool(..) -> "boolean"
    Record(..) -> "record"
    List(..) -> "list"
    Lambda(..) | Lambda0(..) -> "lambda"
    Builtin(..) -> "builtin"
  }
}
