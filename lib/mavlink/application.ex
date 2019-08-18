defmodule MAVLink.Application do
  @moduledoc false
  
  
  use Application
  
  
  def start(_, _) do
    children = case Mix.env do
      :test -> []
      _ -> [MAVLink.Supervisor]
    end

    Supervisor.start_link(children, strategy: :one_for_one)
  end
  
end
