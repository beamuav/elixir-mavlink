defmodule MAVLink.SerialConnection do
  @moduledoc """
  MAVLink.Router delegate for Serial connections
  """
  
  @smallest_mavlink_message 8
  
  require Logger
  
  alias MAVLink.Frame
  alias Circuits.UART
  
  import MAVLink.Frame, only: [binary_to_frame_and_tail: 1, validate_and_unpack: 2]
  
  
  defstruct [
    port: nil,
    baud: nil,
    uart: nil,
    buffer: <<>>]
  @type t :: %MAVLink.SerialConnection{
               port: binary,
               baud: non_neg_integer,
               uart: pid,
               buffer: binary}
  
  
  def handle_info({:circuits_uart, port, raw}, receiving_connection=%MAVLink.SerialConnection{buffer: buffer}, dialect) do
    case binary_to_frame_and_tail(buffer <> raw) do
      :not_a_frame ->
        # Noise or malformed frame
        if byte_size(buffer) + byte_size(raw) > 0 do
          :ok = Logger.debug("SerialConnection.handle_info: Not a frame: #{inspect(buffer <> raw)}")
        end
        {:error, :not_a_frame, port, struct(receiving_connection, [buffer: <<>>])}
      {nil, rest} ->
        {:error, :incomplete_frame, port, struct(receiving_connection, [buffer: rest])}
      {received_frame, rest} ->
        # Rest could include a complete message, return later to try emptying the buffer
        if byte_size(rest) >= @smallest_mavlink_message, do: send(self(), {:circuits_uart, port, <<>>})
        case validate_and_unpack(received_frame, dialect) do
          {:ok, valid_frame} ->
            {:ok, port, struct(receiving_connection, [buffer: rest]), valid_frame}
          :unknown_message ->
            # We re-broadcast valid frames with unknown messages
            :ok = Logger.debug "rebroadcasting unknown message with id #{received_frame.message_id}}"
            {:ok, port, struct(receiving_connection, [buffer: rest]), struct(received_frame, [target: :broadcast])}
          reason ->
              :ok = Logger.debug(
                "SerialConnection.handle_info: frame received failed: #{Atom.to_string(reason)}")
              {:error, reason, port, struct(receiving_connection, [buffer: rest])}
        end
    end
  end
  
  
  def connect(["serial", port, baud, uart], controlling_process) do
    if Map.has_key?(UART.enumerate(), port) do
      case UART.open(uart, port, speed: baud, active: true) do
        :ok ->
          :ok = Logger.info("Opened serial port #{port} at #{baud} baud")
          send(
            controlling_process,
            {
              :add_connection,
              port,
              struct(
                MAVLink.SerialConnection,
                [port: port, baud: baud, uart: uart]
              )
            }
          )
          UART.controlling_process(uart, controlling_process)
        {:error, _} ->
          :ok = Logger.warn "Could not open serial port #{port}. Retrying in 1 second"
          :timer.sleep(1000)
          connect(["serial", port, baud, uart], controlling_process)
      end
    else
      :ok = Logger.warn "Serial port #{port} not attached. Retrying in 1 second"
      :timer.sleep(1000)
      connect(["serial", port, baud, uart], controlling_process)
    end
  end
  
  
  def forward(%MAVLink.SerialConnection{uart: uart},
      %Frame{version: 1, mavlink_1_raw: packet}) do
    UART.write(uart, packet)
  end
  
  def forward(%MAVLink.SerialConnection{uart: uart},
      %Frame{version: 2, mavlink_2_raw: packet}) do
    UART.write(uart, packet)
  end

end
