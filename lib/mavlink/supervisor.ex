defmodule Mavlink.Supervisor do
  @moduledoc false
  
  use Supervisor


  
  def start_link(_) do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    children = [
      {
        Mavlink.Router,
        %{
            system: Application.get_env(:mavlink, :system),
            component: Application.get_env(:mavlink, :component)
         }
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
