import gleam/bit_array
import gleam/crypto
import gleam/string
import mist

// connects to user
// 
pub type Socket {
  // generics leak into request type
  Socket(mist.Connection)
  // TODO: can delete if we handle create_canned_connection somehow?
  NoSocket
}

pub type WebsocketConnection {
  // change this to a subject?
  WebsocketConnection(mist.WebsocketConnection)
}

pub type WsSupported {
  WsSupported
}
