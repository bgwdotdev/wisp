import exception
import gleam/bytes_builder
import gleam/erlang/process
import gleam/http/request.{type Request as HttpRequest}
import gleam/http/response.{
  type Response as HttpResponse, Response as HttpResponse,
}
import gleam/option.{type Option}
import gleam/otp/actor
import gleam/result
import gleam/string
import mist
import wisp
import wisp/internal

// HTTP 

pub fn handler(
  handler: fn(wisp.Request, wisp.WsSupported) -> wisp.Response,
  secret_key_base: String,
) -> fn(HttpRequest(mist.Connection)) -> HttpResponse(mist.ResponseData) {
  fn(request: HttpRequest(_)) {
    let connection =
      wisp.make_connection(
        mist_body_reader(request),
        secret_key_base,
        internal.Socket(request.body),
      )
    let request = request.set_body(request, connection)

    use <- exception.defer(fn() {
      let assert Ok(_) = wisp.delete_temporary_files(request)
    })

    let response =
      request
      |> handler(internal.WsSupported)
      |> mist_response

    response
  }
}

fn mist_body_reader(request: HttpRequest(mist.Connection)) -> wisp.Reader {
  case mist.stream(request) {
    Error(_) -> fn(_) { Ok(wisp.ReadingFinished) }
    Ok(stream) -> fn(size) { wrap_mist_chunk(stream(size)) }
  }
}

fn wrap_mist_chunk(
  chunk: Result(mist.Chunk, mist.ReadError),
) -> Result(wisp.Read, Nil) {
  chunk
  |> result.nil_error
  |> result.map(fn(chunk) {
    case chunk {
      mist.Done -> wisp.ReadingFinished
      mist.Chunk(data, consume) ->
        wisp.Chunk(data, fn(size) { wrap_mist_chunk(consume(size)) })
    }
  })
}

fn mist_response(response: wisp.Response) -> HttpResponse(mist.ResponseData) {
  let body = case response.body {
    wisp.Empty -> mist.Bytes(bytes_builder.new())
    wisp.Text(text) -> mist.Bytes(bytes_builder.from_string_builder(text))
    wisp.Bytes(bytes) -> mist.Bytes(bytes)
    wisp.File(path) -> mist_send_file(path)
    wisp.Websocket(x) -> mist.Websocket(x)
  }
  response
  |> response.set_body(body)
}

fn mist_send_file(path: String) -> mist.ResponseData {
  case mist.send_file(path, offset: 0, limit: option.None) {
    Ok(body) -> body
    Error(error) -> {
      wisp.log_error(string.inspect(error))
      // TODO: return 500
      mist.Bytes(bytes_builder.new())
    }
  }
}

// WEBSOCKETS

pub fn websocket(ws: wisp.WebsocketHandler(a, b)) -> wisp.Response {
  let handler = mist_ws_handler(ws)
  let on_init = mist_ws_on_init(ws)
  mist_websocket(ws.req, ws.socket, handler, on_init, ws.on_close)
}

fn mist_ws_handler(
  ws: wisp.WebsocketHandler(a, b),
) -> fn(a, mist.WebsocketConnection, mist.WebsocketMessage(b)) ->
  actor.Next(b, a) {
  fn(state: a, conn: mist.WebsocketConnection, msg: mist.WebsocketMessage(b)) {
    let msg = msg |> from_mist_websocket_message
    let conn = internal.WebsocketConnection(conn)
    ws.handler(state, conn, msg)
  }
}

fn mist_ws_on_init(
  ws: wisp.WebsocketHandler(a, b),
) -> fn(mist.WebsocketConnection) -> #(a, Option(process.Selector(b))) {
  fn(conn: mist.WebsocketConnection) {
    let conn = internal.WebsocketConnection(conn)
    ws.on_init(conn)
  }
}

fn mist_websocket(
  req: wisp.Request,
  socket: internal.Socket,
  handler handler: fn(a, mist.WebsocketConnection, mist.WebsocketMessage(b)) ->
    actor.Next(b, a),
  on_init on_init: fn(mist.WebsocketConnection) ->
    #(a, Option(process.Selector(b))),
  on_close on_close: fn(a) -> Nil,
) -> wisp.Response {
  let assert internal.Socket(x) = socket
  let req = request.set_body(req, x)
  let resp = mist.websocket(req, handler, on_init(_), on_close)
  case resp.status, resp.body {
    200, mist.Websocket(x) ->
      wisp.ok()
      |> wisp.set_body(wisp.Websocket(x))
    400, _ -> wisp.bad_request()
    _, _ -> wisp.internal_server_error()
  }
}

fn from_mist_websocket_message(
  msg: mist.WebsocketMessage(a),
) -> wisp.WebsocketMessage(a) {
  case msg {
    mist.Text(x) -> wisp.WsText(x)
    mist.Binary(x) -> wisp.WsBinary(x)
    mist.Closed -> wisp.WsClosed
    mist.Shutdown -> wisp.WsShutdown
    mist.Custom(x) -> wisp.WsCustom(x)
  }
}

pub opaque type WebsocketConnection {
  WebsocketConnection(mist.WebsocketConnection)
}

/// Sends text to a websocket connection
pub fn send_text(connection: wisp.WebsocketConnection, text: String) {
  let conn = case connection {
    internal.WebsocketConnection(conn) -> conn
  }
  mist.send_text_frame(conn, text)
}

/// Sends binary data to a websocket connection
pub fn send_binary(connection: WebsocketConnection, binary: BitArray) {
  let conn = case connection {
    WebsocketConnection(conn) -> conn
  }
  mist.send_binary_frame(conn, binary)
}
