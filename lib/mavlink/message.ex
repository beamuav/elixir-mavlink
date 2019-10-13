defprotocol MAVLink.Message do
  @spec pack(MAVLink.Message.t()) :: {:ok, MAVLink.Types.message_id, binary()} | {:error, String.t}
  def pack(message)
end


defimpl MAVLink.Message, for: [Atom, BitString, Float, Function, Integer, List, Map, PID, Port, Reference, Tuple] do
  def pack(not_a_message), do: {:error, "pack(): #{inspect(not_a_message)} is not a MAVLink message"}
end
