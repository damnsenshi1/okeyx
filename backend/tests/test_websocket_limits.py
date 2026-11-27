from app.api.game import MAX_SOCKET_MESSAGE_BYTES, _socket_message_too_large


def test_socket_message_limit_counts_utf8_bytes():
    assert not _socket_message_too_large('x' * MAX_SOCKET_MESSAGE_BYTES)
    assert _socket_message_too_large('x' * (MAX_SOCKET_MESSAGE_BYTES + 1))
    assert _socket_message_too_large('ğ' * (MAX_SOCKET_MESSAGE_BYTES // 2 + 1))
