defmodule MAVLink.ConnectionSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias MAVLink.{SerialConnection, TCPOutConnection, UDPInConnection, UDPOutConnection}

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_connection(connection_string, dialect) when is_binary(connection_string) do
    start_connection(String.split(connection_string, [":", ","]), dialect)
  end

  def start_connection(["udpin" | _] = tokens, dialect) do
    [_, address, port] = validate_address_and_port(tokens)

    child_spec =
      {UDPInConnection, %{dialect: dialect, listen_address: address, listen_port: port}}

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def start_connection(["udpout" | _] = tokens, dialect) do
    [_, address, port] = validate_address_and_port(tokens)

    child_spec =
      {UDPOutConnection, %{dialect: dialect, address: address, port: port}}

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def start_connection(["tcpout" | _] = tokens, dialect) do
    [_, address, port] = validate_address_and_port(tokens)

    child_spec =
      {TCPOutConnection, %{dialect: dialect, address: address, port: port}}

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def start_connection(["serial" | _] = tokens, dialect) do
    ["serial", port, baud, uart] = validate_port_and_baud(tokens)

    child_spec =
      {SerialConnection, %{dialect: dialect, port: port, baud: baud, uart: uart}}

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def start_connection([invalid | _], _dialect) do
    raise ArgumentError, message: "invalid protocol #{invalid}"
  end

  defp validate_address_and_port([protocol, address, port]) do
    import MAVLink.Utils, only: [parse_ip_address: 1, parse_positive_integer: 1]

    case {parse_ip_address(address), parse_positive_integer(port)} do
      {{:error, :invalid_ip_address}, _} ->
        raise ArgumentError, message: "invalid ip address #{address}"

      {_, :error} ->
        raise ArgumentError, message: "invalid port #{port}"

      {parsed_address, parsed_port} ->
        [protocol, parsed_address, parsed_port]
    end
  end

  defp validate_port_and_baud(["serial", port, baud]) do
    import MAVLink.Utils, only: [parse_positive_integer: 1]

    case {is_binary(port), parse_positive_integer(baud)} do
      {false, _} ->
        raise ArgumentError, message: "Invalid port #{port}"

      {_, :error} ->
        raise ArgumentError, message: "invalid baud rate #{baud}"

      {true, parsed_baud} ->
        ["serial", port, parsed_baud, :poolboy.checkout(MAVLink.UARTPool)]
    end
  end
end
