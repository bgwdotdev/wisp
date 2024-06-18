import gleam/bit_array
import gleam/crypto
import gleam/string
import mist

pub type Ws {
  Ws
}

// connects to user
// 
pub type Socket {
  Socket(mist.Connection)
  // TODO: can delete if we handle create_canned_connection somehow?
  NoSocket
}

pub type WebsocketConnection {
  WebsocketConnection(mist.WebsocketConnection)
}

pub type WsSupported {
  WsSupported
}
