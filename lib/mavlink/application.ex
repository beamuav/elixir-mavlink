defmodule Mavlink.Application do
  @moduledoc false
  
  
  use Application
  
  
  def start(_, _) do
    children = [Mavlink.Supervisor]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
  
end
