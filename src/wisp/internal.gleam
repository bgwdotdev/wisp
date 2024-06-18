import gleam/bit_array
import gleam/crypto
import gleam/string
import mist

pub type WebsocketConnection {
  // change this to a subject?
  WebsocketConnection(mist.WebsocketConnection)
}

pub type WsSupported {
  WsSupported
}
